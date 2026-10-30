### 1. Core Data Structures in Blink Fragment Trees

In Chromium’s Blink rendering engine (specifically the LayoutNG architecture), the CSS Display Level 3 §3 "Box Tree" is transformed during the layout phase into an immutable **Fragment Tree**. Because a single CSS box can fragment across multiple lines, columns, or pages, a 1-to-N relationship exists between `LayoutObject` nodes and `PhysicalFragment` instances.

#### `PhysicalBoxFragment` (`third_party/blink/renderer/core/layout/physical_box_fragment.h`)
The immutable output of a layout pass for a box. Once constructed, its geometry and children cannot be mutated in place (with controlled exceptions for post-layout visual/ink overflow recalculations).
*   **Geometry:** Stores `size_` (`PhysicalSize`, representing the border-box dimensions in physical coordinates), `borders_` (`PhysicalBoxStrut`), and `padding_` (`PhysicalBoxStrut`).
*   **Children:** Stored in a contiguous trailing array of `PhysicalFragmentLink` structures allocated inline with the fragment via `oilpan` (Blink's garbage collector) using `AdditionalBytes`.
*   **Overflow:** Contains `ink_overflow_` (`InkOverflow` union) and optional `rarer_data_` storing `scrollable_overflow_` (`PhysicalRect`).
*   **Fragmentation & Margins:** Holds a reference to an optional `BlockBreakToken` (`break_token_`) and flags such as `is_first_for_node_`, `may_have_descendant_above_block_start_`, and `is_self_collapsing_`.

#### `BoxFragmentBuilder` (`third_party/blink/renderer/core/layout/box_fragment_builder.h`)
The mutable accumulator used by a `LayoutAlgorithm` (e.g., `BlockLayoutAlgorithm`, `FlexLayoutAlgorithm`) to construct a `PhysicalBoxFragment`.
*   **Coordinate Space:** Operates entirely in **logical coordinates** (`LogicalSize`, `LogicalOffset`, `WritingDirectionMode`).
*   **Child Accumulation:** Maintains a `HeapVector<LogicalFragmentLink>` (`children_`). When `AddChild(const PhysicalFragment&, const LogicalOffset&, ...)` is invoked, the builder records the child, its logical offset relative to the parent's border box, and immediately triggers propagation routines for margins, break tokens, OOF (Out-Of-Flow) candidates, and named page states.
*   **Conversion:** Calling `ToBoxFragment()` converts all accumulated logical offsets into physical offsets (`PhysicalOffset`) based on the resolved physical size of the container and its `WritingDirectionMode`, then allocates the immutable `PhysicalBoxFragment`.

#### `PhysicalFragmentLink` / `LogicalFragmentLink`
Value types acting as directed edges in the fragment tree.
```cpp
struct PhysicalFragmentLink {
  Member<const PhysicalFragment> fragment;
  PhysicalOffset offset; // Relative to parent's physical top-left border edge
};
```
Because the child's relative offset belongs to the *parent's* layout context rather than the child itself, `PhysicalFragment` instances do not know their own position relative to their parent. This allows Blink to reuse cached `PhysicalFragment` subtrees across layout passes even if their position within their parent changes (cache hits via `LayoutResult`).

---

### 2. Tree Assembly and Overflow Propagation

CSS Display Level 3 §3 dictates how formatting contexts nest and generate boxes; CSS Overflow Level 3 defines how their geometry aggregates into **Scrollable Overflow** (which affects scrollbars and scrolling bounds) and **Ink Overflow** (visual paint bounds, such as box-shadows, text glyphs overhanging the font ascent/descent, and outlines, which do not affect layout or scrollbars).

#### Scrollable Overflow Aggregation
Scrollable overflow is computed during fragment construction or immediately thereafter via `ScrollableOverflowCalculator` (`third_party/blink/renderer/core/layout/scrollable_overflow_calculator.h`).

Let a parent fragment $P$ have physical border-box size $S_P = (W_P, H_P)$, generating an initial local border box rect $R_{\text{border}}(P) = [0, W_P] \times [0, H_P]$.
The initial scrollable overflow of $P$ is its **padding box** (or content box/border box depending on scroll container rules), bounded by $R_{\text{scroll}}(P) = R_{\text{padding}}(P)$.

For each child link $L_i = (C_i, O_i)$ where $C_i$ is a child `PhysicalBoxFragment` and $O_i = (x_i, y_i)$ is its physical offset relative to $P$:

1.  **Child Contribution Extraction:**
    *   Obtain the child's local border box: $B(C_i) = [0, W_{C_i}] \times [0, H_{C_i}]$.
    *   If $C_i$ does **not** establish a scroll container (`!C_i.IsScrollContainer()`) and does **not** clip overflow along both axes (`!C_i.ShouldClipOverflowAlongBothAxes()`):
        Let $S(C_i)$ be $C_i$'s own local scrollable overflow rect. The effective child rect in $C_i$'s local space is:
        $$E(C_i) = B(C_i) \cup \text{Clip}_{C_i}(S(C_i))$$
        where $\text{Clip}_{C_i}$ restricts $S(C_i)$ along any axis where `overflow-x` or `overflow-y` is `clip` or `hidden`.
    *   If $C_i$ **is** a scroll container or clips both axes:
        Its internal scrollable overflow is trapped within $C_i$'s own scrollport/clip. Thus, its contribution to $P$ is strictly its border box (plus any layout-affecting margins in specific flex/grid contexts):
        $$E(C_i) = B(C_i)$$

2.  **Coordinate Translation & Union:**
    Translate $E(C_i)$ into $P$'s coordinate space by adding offset $O_i$, and union it with $P$'s running scrollable overflow:
    $$R_{\text{scroll}}(P) \leftarrow R_{\text{scroll}}(P) \cup (E(C_i) + O_i)$$
    *(Note: Hanging inline whitespace and certain end-edge margins are conditionally adjusted before unioning).*

#### Ink Overflow Aggregation
Ink overflow is computed bottom-up (`PhysicalBoxFragment::RecalcInkOverflow` and `InkOverflow::SetContentsInkOverflow`).

For a fragment $P$:
1.  **Self Ink Overflow ($I_{\text{self}}(P)$):** Starts with $R_{\text{border}}(P)$ and expands outward by `box-shadow`, `outline`, and border-image outsets.
2.  **Contents Ink Overflow ($I_{\text{contents}}(P)$):**
    For each child $L_i = (C_i, O_i)$:
    *   If $C_i$ clips overflow (`HasOverflowClip()`), $C_i$'s `contents_ink_overflow` is clipped to $C_i$'s `OverflowClipRect()` before unioning with $C_i$'s `self_ink_overflow`.
    *   Otherwise, $C_i$'s total ink overflow is $I_{\text{total}}(C_i) = I_{\text{self}}(C_i) \cup I_{\text{contents}}(C_i)$.
    *   Translate into $P$'s space and union:
        $$I_{\text{contents}}(P) \leftarrow \bigcup_{i} \big( \text{EffectiveInk}(C_i) + O_i \big)$$
3.  **Total Ink Overflow:** $I_{\text{total}}(P) = I_{\text{self}}(P) \cup \text{Clip}_P(I_{\text{contents}}(P))$.

---

### 3. Propagating Self-Collapsing Margin Struts and Break Tokens

During `BoxFragmentBuilder::AddChild`, layout state must cross fragment boundaries to satisfy CSS 2.1 §8.3.1 (Collapsing Margins) and CSS Fragmentation Level 3.

#### Self-Collapsing Boxes and Margin Struts (`MarginStrut`)
A block-level box is **self-collapsing** (`is_self_collapsing_`) if its block-size is zero, it has no block-axis borders or padding, it does not establish a new formatting context (e.g., BFC), and all of its in-flow children are also self-collapsing.

In Blink, adjacent block margins are accumulated in a `MarginStrut` structure:
```cpp
struct MarginStrut {
  LayoutUnit positive_margin;      // Max of positive collapsing margins
  LayoutUnit negative_margin;      // Min (most negative) of negative collapsing margins
  bool is_quirky_margin = false;
  LayoutUnit Sum() const { return positive_margin + negative_margin; }
  void Append(LayoutUnit value, bool is_quirky);
};
```
When `BlockLayoutAlgorithm` processes child $C_i$:
1.  An incoming `MarginStrut` $M_{\text{in}}$ is passed down into $C_i$'s layout via `ConstraintSpace` if $C_i$ can collapse its block-start margin with preceding margins.
2.  $C_i$ returns a `LayoutResult` containing an `end_margin_strut` ($M_{\text{out}}$) stored on the `LayoutResult` (not the `PhysicalFragment`, because margin struts are layout-time transient values).
3.  **Propagation Rule:**
    *   If $C_i$ is **self-collapsing**, its block-start and block-end margins collapse together with $M_{\text{in}}$:
        $$M_{\text{next}} = \text{Append}(\text{Append}(M_{\text{in}}, m_{\text{start}}(C_i)), m_{\text{end}}(C_i))$$
        The logical block-offset of $C_i$ is resolved tentatively, and $M_{\text{next}}$ continues directly to sibling $C_{i+1}$.
    *   If $C_i$ is **not self-collapsing** and does not collapse through to the parent's block-end, $M_{\text{in}} \oplus m_{\text{start}}(C_i)$ is resolved into a concrete physical/logical block-offset delta $\Delta_{\text{block}} = M_{\text{combined}}.\text{Sum}()$, positioning $C_i$'s border box. Then, the running strut resets to $C_i$'s outgoing end margin strut: $M_{\text{next}} = M_{\text{out}}(C_i)$.
    *   If the last in-flow child collapses with the parent's block-end (no parent bottom border/padding), the final $M_{\text{next}}$ is attached to the parent's `LayoutResult::EndMarginStrut()` and bubbles up to the parent's parent.

#### Break Tokens (`BlockBreakToken`)
When a box fragments across fragmentainers (columns/pages), `BoxFragmentBuilder::AddBreakBeforeChild` or `PropagateBreakToken` manages continuation state.

1.  When child $C_i$ cannot fit completely in the current fragmentainer, $C_i$'s layout produces a partial `PhysicalBoxFragment` containing a `BlockBreakToken` $T_{C_i}$.
2.  When `BoxFragmentBuilder::AddChild` adds this partial $C_i$ to parent builder $P$:
    ```cpp
    if (const auto* child_break_token = DynamicTo<BlockBreakToken>(child.GetBreakToken())) {
      child_break_tokens_.push_back(child_break_token);
      has_block_fragmentation_ = true;
    }
    ```
3.  When $P$ finishes its current fragmentainer pass and calls `ToBoxFragment()`, `BlockBreakToken::Create(builder)` constructs $P$'s break token $T_P$.
4.  $T_P$ encapsulates:
    *   `consumed_block_size_`: Total block size of $P$ consumed across all prior and current fragmentainers.
    *   `sequence_number_`: Monotonically increasing index for $P$'s fragments.
    *   `child_break_tokens_`: An array containing all unexhausted `BlockBreakToken`s ($T_{C_i}$) from $P$'s children, plus break tokens created for children that broke *before* entering layout (`IsBreakBefore()`).
5.  In the next fragmentainer, $P$'s algorithm receives $T_P$, resumes iterating over `T_P->ChildBreakTokens()`, and feeds each $T_{C_i}$ back into the layout pass of child $C_i$.

---

### 4. Mathematical Invariants

Let $\mathcal{F}$ be the set of all `PhysicalBoxFragment` instances produced by a Blink layout pass.

#### Invariant 1: Parent Scrollable Overflow Contains Unclipped Child Border Boxes
For any parent fragment $P \in \mathcal{F}$ that does not clip its own scrollable overflow, and for any in-flow or positioned child link $(C, O) \in \text{Children}(P)$ governed by $P$'s containing block context:
$$B(C) + O \subseteq R_{\text{scroll}}(P)$$
Furthermore, if $C$ does not clip overflow along either axis (`overflow: visible`) and is not a scroll container:
$$(B(C) \cup R_{\text{scroll}}(C)) + O \subseteq R_{\text{scroll}}(P)$$
*Edge Case Note:* In Blink, if $P$ has `overflow: clip` or `overflow: hidden`, the raw `ScrollableOverflow` calculated before clipping still unions $B(C) + O$, and the clip rect is applied when querying `ScrollableOverflowFromChildren` or scroll ranges.

#### Invariant 2: Fragment Structure is a Directed Acyclic Graph (Rooted Tree up to Caching)
Define the directed graph $G = (\mathcal{F}, E)$ where $(P, C) \in E \iff \exists O, (C, O) \in \text{Children}(P)$.
*   **Acyclicity:** There exists no non-empty sequence of fragments $(F_0, F_1, \dots, F_k)$ such that $(F_i, F_{i+1}) \in E$ for all $0 \le i < k$ and $F_0 = F_k$.
*   **Strict Construction Order:** A `PhysicalBoxFragment` $P$ can only be constructed by `BoxFragmentBuilder::ToBoxFragment()` *after* all of its child `PhysicalFragment` pointers $C_i$ have already been allocated and finalized. Since `PhysicalBoxFragment::children_` is immutable post-construction, memory allocation timestamps strictly increase from leaves to the root:
    $$\forall (P, C) \in E, \quad \text{alloc\_time}(C) < \text{alloc\_time}(P)$$
    Because `<` on timestamps is a strict total order, cycles are impossible. (If layout caching reuses a subtree across sibling branches in rare layout measurement passes, $G$ is a finite DAG; in final committed layout trees, each fragment corresponds to a unique box-fragmentation slice, forming a strict tree).

#### Invariant 3: Determinism of Propagation
Let $\text{BuildFragment}$ be the pure state-transition function representing `BoxFragmentBuilder` taking an initial builder configuration $B_0$ and an ordered sequence of child links and layout results $\vec{L} = [(C_1, O_1, M_1), \dots, (C_n, O_n, M_n)]$.
