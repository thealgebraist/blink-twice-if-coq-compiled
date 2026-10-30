**AGENT ID: 387**  
**SUBJECT: Audit of Blink CSS Anchor Positioning — Element Resolution & Fallback Architecture**  
**TARGET ENGINE: Chromium / Blink (`LayoutNG`)**  
**STATUS: CLASSIFIED // TECHNICAL AUDIT**

---

### 1. Executive Summary
This audit details the internal mechanisms utilized by the Blink rendering engine to resolve CSS Anchor Positioning (`anchor-name`, `position-anchor`, `anchor()`, and `position-try-fallbacks`). In Blink’s `LayoutNG` architecture, anchor resolution requires breaking standard top-down tree-traversal paradigms without inducing cyclic layout dependencies, relying heavily on `NGLogicalAnchorQuery` and out-of-flow (OOF) layout passes.

---

### 2. Anchor Matching & Element Resolution

Anchor resolution is the process of binding an Out-of-Flow (OOF) positioned element to a specific `LayoutObject` reference (the anchor) within the layout tree.

#### 2.1. Scoping and DOM/Layout Tree Order
Blink enforces strict scoping and tree-order rules during the layout phase via `NGAnchorScope` and `NGLogicalAnchorQuery`:
* **Acceptable Anchor Eligibility:** For an element $A$ to be a valid anchor for a positioned element $P$:
  1. $A$ must generate a box in the layout tree (cannot be `display: none` or `display: contents`).
  2. $A$'s `ContainingBlock` must be an ancestor of $P$'s `ContainingBlock` (or the same block).
  3. **Pre-order Traversal Rule:** If $A$ is also OOF-positioned, $A$ must precede $P$ in the flat tree (DOM order, accounting for Shadow DOM slotting) so that $A$'s layout is fully resolved *before* $P$ attempts to query it. In-flow elements are always laid out before OOF elements in the same containing block.

#### 2.2. `anchor-scope` Isolation
When `anchor-scope` is declared on an ancestor, Blink instantiates a scoped `NGLogicalAnchorQuery` boundary during box generation. Names defined inside this subtree are masked from propagating up to ancestor `NGAnchorQuery` maps, preventing namespace collisions in complex component trees.

#### 2.3. Propagation (`NGLogicalAnchorQuery`)
Blink does not search the DOM to find anchors during layout; doing so would violate $O(N)$ layout performance targets. Instead, it uses bottom-up geometry propagation:
1. As `NGBlockNode::Layout()` completes for a child fragment, any `anchor-name` declarations on that fragment (or its descendants) are registered into the fragment's local `NGPhysicalAnchorQuery`.
2. As the layout unwinds up the tree, parent fragments merge child queries into their own `NGLogicalAnchorQuery`, transforming physical coordinates into the parent's logical coordinate space.
3. **Conflict Resolution:** If two valid anchors share the same `anchor-name` within the same containing block scope, the **last one in pre-order flat-tree traversal wins**, overwriting the previous entry in the `NGLogicalAnchorQuery` hash map.

#### 2.4. Implicit vs. Explicit Anchors
* **Explicit:** Resolved by matching the `AtomicString` from `position-anchor` or inside `anchor(<anchor-name> ...)` against the `NGLogicalAnchorQuery` map attached to $P$'s containing block.
* **Implicit (`auto`):** If omitted, Blink queries `Element::ImplicitAnchorElement()`. This resolves to elements associated via the HTML `anchor` attribute, the Popover API (`invoker`), or CSS pseudo-element relationships.

---

### 3. The Fallback Engine (`@position-try`)

When an anchored element overflows its inset-modified containing block (IMCB), Blink triggers its fallback resolution loop inside `NGOutOfFlowLayoutPart`.

#### 3.1. Style Cascade Integration
Fallback styles (`position-try-fallbacks`) do not run through the standard global `StyleEngine::RecalcStyle()` pass on every layout iteration. Instead:
1. During initial style calculation, `StyleResolver` bundles the base `ComputedStyle` alongside a `PositionTryFallback` list.
2. When `NGOutOfFlowLayoutPart` tests a fallback option (e.g., `flip-block`, `--my-custom-try`), it invokes `StyleEngine::UpdateStyleForPositionTry()` to synchronously generate a speculative `ComputedStyle` restricted strictly to **position-try eligible properties** (insets, margins, sizing, alignments, and `position-anchor`).

#### 3.2. The Speculative Layout Loop
Located within `NGOutOfFlowLayoutPart::CalculateOffset()`, the engine executes a non-mutating trial loop:

```text
[Start OOF Layout for Element P]
       │
       ▼
1. Fetch Base ComputedStyle (No Try Tactics)
       │
       ▼
2. Compute Anchor Evaluator (NGAnchorEvaluatorImpl)
   └── Resolve anchor() and anchor-size() to LayoutUnit values.
   └── If an anchor reference is invalid, trigger Fallback value or resolve to 0px.
       │
       ▼
3. Compute Inset-Modified Containing Block (IMCB) & Element Offset/Size
       │
       ▼
4. Overflow Check: Does P's margin-box overflow the IMCB (accounting for Scroll Offsets)?
   ├── [NO] ──► Lock in this style. Exit loop and generate final NGPhysicalFragment.
   └── [YES] ─► Proceed to Next Fallback in `position-try-fallbacks`.
                     │
                     ├─► [More Fallbacks Exist] ──► Apply `PositionTry` Tactic/Rule -> Loop to Step 2.
                     └─► [Fallbacks Exhausted]  ──► Revert to Base Style (or last successful non-overflowing state).
```

#### 3.3. Try-Tactics (`flip-block`, `flip-inline`, `flip-start`)
For built-in keywords, Blink does not need a `@position-try` rule lookup. It uses an internal transformation matrix (`TryTacticTransform`) during `StyleResolver` evaluation that dynamically swaps CSS property values (e.g., `top` $\leftrightarrow$ `bottom`, `margin-top` $\leftrightarrow$ `margin-bottom`, `anchor(top)` $\leftrightarrow$ `anchor(bottom)`) before feeding them into the `NGAnchorEvaluatorImpl`.

#### 3.4. `position-try-order` (`most-width`, `most-height`, etc.)
If `position-try-order` is set to something other than `normal`:
1. `NGOutOfFlowLayoutPart` cannot short-circuit on the first non-overflowing option.
2. It must evaluate the IMCB dimensions for the base style and **all** `@position-try` fallbacks.
3. It sorts the candidate list based on the available space in the IMCB along the specified axis (`most-block-size`, `most-inline-size`), and *then* runs the overflow validation loop in that newly sorted order.

---

### 4. Compositor Integration & Scroll Independence

A critical vulnerability in naive anchor resolution is scroll lag: if the anchor is inside a scroller and the positioned element is outside (or vice versa), main-thread layout cannot run on every frame of smooth scrolling.

**Blink's Mitigation (`AnchorScrollData`):**
1. During the main-thread layout pass, `NGOutOfFlowLayoutPart` evaluates the default scroll position (scroll offset = 0).
2. Blink creates an `AnchorPositionScrollData` object attached to the positioned element, recording the scroll container hierarchy between the anchor and the OOF element.
3. This data is pushed to the **Compositor Thread (`cc`)** as a property tree node (`TransformNode` translation offset).
4. As the user scrolls on the compositor thread, `cc` updates the OOF element's position at 60/120Hz.
5. **Fallback Triggering on Scroll:** If scrolling causes the OOF element to breach its IMCB, the `AnchorPositionScrollData` invalidates the layout on the next `BeginMainFrame`, triggering a fast-path OOF re-layout pass to switch to the next `@position-try` fallback.

---

### 5. Edge Cases & Audit Findings

* **Invalid Anchor References:** If `anchor(--non-existent top, 50px)` is evaluated by `NGAnchorEvaluatorImpl`, the lookup in `NGLogicalAnchorQuery` returns `nullptr`. The evaluator immediately substitutes the fallback parameter (`50px`). If no fallback parameter is provided, the declaration becomes invalid at computed-value time (behaving as `auto` for insets).
* **Fragmentation (Multicol / Printing):** In fragmented contexts, an anchor may split across multiple `NGPhysicalBoxFragment`s. Blink aggregates the bounding box of all fragments belonging to the anchor within the fragmentation context to synthesize a unified reference box.
* **`position-visibility: no-overflow` / `anchors-visible`:** Handled *post-layout* during the Pre-Paint phase (`PrePaintTreeWalk`). If all `@position-try` fallbacks fail and `no-overflow` is set, Blink sets a paint-invalidation flag on the `FragmentData` to suppress painting of the OOF element without mutating the layout tree.

**END OF AUDIT REPORT — AGENT 387**