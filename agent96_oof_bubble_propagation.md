# Agent 96 Audit Report: Blink OOF Candidate Bubbling vs. CSS Specifications

**Target Subsystems:** Chromium Blink `third_party/blink/renderer/core/layout/` (LayoutNG / Block Fragmentation)  
**Reference Specifications:** CSS Positioned Layout Module Level 3 (CSS-POSITION-3), CSS Fragmentation Module Level 3 (CSS-BREAK-3)  
**Formalization Target:** `BlinkOOFBubblePropagationSemantics.v`

---

## 1. Core Data Structures in Blink OOF Bubbling

In Blink’s LayoutNG architecture, Out-Of-Flow (OOF) positioned elements (`position: absolute` or `position: fixed`) are not laid out at their DOM tree location if their containing block (CB) is an ancestor of their parent. Because layout produces immutable physical fragments bottom-up, OOF nodes must "bubble" up the fragment tree until their containing block's builder is reached.

### 1.1 `LogicalOOFPositionedNode` (`ng_oof_positioned_node.h`)
Represents an unlaid-out OOF candidate during the mutable builder phase (in the parent or ancestor's writing-mode/logical coordinate space).
*   `Node` (`BlockNode`): The layout input node representing the OOF element.
*   `static_position` (`LogicalStaticPosition`): The logical offset where the node would have been placed had it been in-flow, along with alignment edges (`InlineEdge`, `BlockEdge`). This is transformed across coordinate spaces during bubbling.
*   `inline_container` (`InlineContainer<LogicalOffset>`): If the containing block is an inline box (e.g., a `<span>` with `position: relative`), this tracks the specific inline container and its fragments to compute the bounding box.
*   `is_for_fragmentation` (Boolean / Sub-struct `LogicalFragmentedOOFPositionedNode`): When block fragmentation (multicol, printing) is active, tracks the fragmentainer index, additional ContainingBlock descriptors (`OOFContainingBlock<LogicalOffset>`), and fixedpos containing block scopes.

### 1.2 `PhysicalFragment` (`physical_fragment.h`)
The immutable output of a layout pass. Once a `BoxFragmentBuilder` finishes, it produces a `PhysicalFragment` (specifically `PhysicalBoxFragment`).
*   `oof_positioned_descendants_` (Array of `PhysicalOOFPositionedNode`): If a fragment is **not** the containing block for all OOF candidates discovered within its subtree, it stores the remaining candidates on the `PhysicalFragment` in physical coordinates (`PhysicalStaticPosition`).
*   `HasOutOfFlowFragmentChild()`: A fast-path bitflag indicating whether any direct child of this fragment is a laid-out OOF fragment.
*   `HasOutOfFlowPositionedDescendants()`: Bitflag indicating whether `oof_positioned_descendants_` is non-empty, triggering propagation in the parent builder.

### 1.3 `BoxFragmentBuilder` (`box_fragment_builder.h`)
The mutable accumulator used by layout algorithms (e.g., `BlockLayoutAlgorithm`, `FlexLayoutAlgorithm`) to construct a `PhysicalBoxFragment`.
*   `oof_positioned_candidates_` (`HeapVector<LogicalOOFPositionedNode>`): Candidates that have bubbled up into this builder and **might** have this builder's node as their containing block, or are awaiting further propagation.
*   `oof_positioned_descendants_` (`HeapVector<LogicalOOFPositionedNode>`): In fragmentation contexts, candidates that bypass layout at the current level and are explicitly queued to be stored on the resulting `PhysicalFragment` for a higher-level fragmentation context (e.g., `OutOfFlowLayoutPart` at the fragmentation root) to handle.

### 1.4 `ContainingBlockScope` / `OOFContainingBlock` (`ng_oof_positioned_node.h`)
Under CSS Fragmentation Level 3, an OOF element's containing block might itself be fragmented across multiple column/page fragmentainers. The OOF cannot be laid out inside a single fragment of its containing block; it must be laid out by the **fragmentation context root** (e.g., the multicol container).
*   `OOFContainingBlock<OffsetType>` encapsulates the `ContainingBlockScope`:
    *   `Fragment` (`const PhysicalFragment*`): The specific fragment of the containing block.
    *   `ClippedContainerBlockOffset` (`LayoutUnit`): Accumulates block progression across fragmentainers to establish a continuous coordinate space for the OOF node.
    *   `Offset` (`OffsetType`): The relative offset from the fragmentation root to the containing block fragment.

---

## 2. Propagation Mechanism

Propagation occurs via a strict bottom-up accumulation and coordinate transformation pipeline during `ContainerFragmentBuilder::AddChild`.

### Step-by-Step Execution Pipeline:
1.  **Discovery at DOM Parent:** When a layout algorithm encounters an OOF child `N` in its `LayoutInputNode` iteration, it calculates `N`'s `LogicalStaticPosition` (based on current `BfcOffset` and text direction) and calls `Builder.AddOutOfFlowChildCandidate(N, static_position)`.
2.  **Unresolved Freezing (`ToBoxFragment`):** When a child builder `B_child` completes layout (after running `OutOfFlowLayoutPart` for candidates it *can* resolve), any remaining unconsumed candidates in `B_child.oof_positioned_candidates_` (or `descendants_`) have their `LogicalStaticPosition` converted to `PhysicalStaticPosition` using `B_child`'s `WritingDirectionMode` and outer size. They are frozen into `PhysicalFragment::oof_positioned_descendants_`.
3.  **Bubbling via `AddChild`:** The parent builder `B_parent` lays out `B_child`, obtaining `PhysicalFragment` `F_child`, and places it at `child_offset` (a `LogicalOffset` relative to `B_parent`).
4.  **Propagation Extraction (`PropagateOOFPositionedInfo`):** Inside `B_parent.AddChild(F_child, child_offset)`:
    *   `B_parent` checks `F_child.HasOutOfFlowPositionedDescendants()`.
    *   For each `PhysicalOOFPositionedNode` $d \in F_{\text{child}}.\text{oof\_positioned\_descendants\_}$:
        *   **Coordinate Transformation:** $d$'s `PhysicalStaticPosition` (which is relative to `F_child`'s top-left physical corner) is converted back to a `LogicalStaticPosition` in `B_parent`'s writing mode.
        *   **Offset Accumulation:** `child_offset` is added to the newly converted `LogicalStaticPosition.offset`:
            $$\text{pos}_{\text{parent}} = \text{ToLogical}(d.\text{physical\_pos}, \text{WM}_{\text{parent}}, \text{Size}_{\text{child}}) + \text{child\_offset}$$
        *   **Scope Wrapping (Fragmentation):** If `B_child` was the actual CSS containing block for $d$, but `B_child` is inside a fragmentation context (`IsBlockFragmentationContextRoot() == false`), `B_child` could not lay out $d$ across fragmentainers. `B_parent` wraps $d$ into a `LogicalFragmentedOOFPositionedNode`, binding `F_child` into $d$'s `OOFContainingBlock` scope and accumulating `child_offset` into the `ContainingBlock`'s relative offset.
        *   $d$ is appended to `B_parent.oof_positioned_candidates_`.

---

## 3. Containing Block Matching & Consumption (`OutOfFlowLayoutPart`)

Before a `BoxFragmentBuilder` `B` finalizes its `PhysicalBoxFragment`, the layout algorithm instantiates `OutOfFlowLayoutPart(&B)` and invokes `Run()`.

### 3.1 Matching Predicate
`BoxFragmentBuilder::SwapOutOfFlowPositionedCandidates(&candidates)` extracts all currently bubbled candidates. For each candidate $N$, Blink determines if $B$'s layout box (`B.Node()`) is the target consumer.

By CSS-POSITION-3 § 2.1, $B$ is the containing block for $N$ ($\text{IsCB}(B, N)$) iff:
*   $N$ is `position: absolute` and $B$ is the nearest ancestor with `CanContainAbsolutePositionObjects()` (i.e., `position != static`, or `transform`, `contain: layout/paint`, `will-change`, etc.).
*   $N$ is `position: fixed` and $B$ is the nearest ancestor with `CanContainFixedPositionObjects()` (e.g., `transform`, `contain`, or the `LayoutView` / initial containing block).

### 3.2 Consumption vs. Forwarding Logic
In `OutOfFlowLayoutPart::SweepCandidates`:
*   **Case A: Non-Fragmented Match ($\text{IsCB}(B, N) \land \neg \text{InFragmentation}(B)$):**
    *   $N$ is **consumed**.
    *   `OutOfFlowLayoutPart::CalculateOffset` resolves `top`/`right`/`bottom`/`left` or falls back to `N.static_position` (converting inline/block static edges to the IMCB — Inset-Modified Containing Block).
    *   `LayoutOOFNode` invokes layout on `N.Node`, producing an OOF `PhysicalBoxFragment` $F_N$.
    *   $F_N$ is added directly as a child fragment to $B$ via `B.AddResult(F_N, oof_offset)`. $N$ ceases to exist as a candidate.
*   **Case B: Fragmented Match ($\text{IsCB}(B, N) \land \text{InFragmentation}(B) \land \neg \text{IsFragmentationRoot}(B)$):**
    *   $B$ is the CSS containing block, *but* $B$ is being fragmented (e.g., $B$ is a `div` inside a multicol). $B$ cannot lay out $N$ because $N$ might span multiple columns that $B$ doesn't manage.
    *   $N$ is **forwarded** to `B.oof_positioned_descendants_` with a newly bound `ContainingBlockScope` pointing to $B$.
*   **Case C: Fragmentation Root Match ($\text{IsFragmentationRoot}(B) \land N.\text{HasContainingBlockScope}()$):**
    *   $B$ is the multicol/page root. $N$’s containing block was already matched inside the subtree (Case B).
    *   $N$ is **consumed** by `OutOfFlowLayoutPart::LayoutFragmentainerDescendants`, which lays out $N$ across the generated fragmentainer children of $B$.
*   **Case D: Unmatched ($\neg \text{IsCB}(B, N)$):**
    *   If $N$'s containing block is an inline split across lines (`N.inline_container`), and $B$ is the anonymous block or containing block that encloses those inlines, $B$ resolves the inline container geometry.
    *   Otherwise, $N$ is re-inserted into `B` to be serialized into `PhysicalFragment::oof_positioned_descendants_` and bubbled to `B`'s parent.

---

## 4. Mathematical Invariants

Let $\mathcal{T}$ be the layout fragment tree, where each node $u \in \mathcal{T}$ represents a builder/fragment invocation.
For any node $u \in \mathcal{T}$:
*   Let $\text{Gen}(u)$ be the set of OOF nodes directly discovered as DOM children of $u$ whose CB is not $u$'s inline formatting context unless $u$ resolves it.
*   Let $\text{In}(u)$ be the set of OOF candidates entering $u$ before `OutOfFlowLayoutPart::Run()`.
*   Let $\text{Cons}(u)$ be the set of OOF candidates consumed and converted into physical child fragments at $u$.
*   Let $\text{Out}(u)$ be the set of OOF candidates stored in $u$'s `PhysicalFragment::oof_positioned_descendants_` (forwarded to $\text{parent}(u)$).

### Invariant 1: Recursive Candidate Entry Union
The candidate set entering `OutOfFlowLayoutPart` at builder $u$ is the disjoint union of candidates generated at $u$ and candidates forwarded by all children $c \in \text{children}(u)$:
$$\text{In}(u) = \text{Gen}(u) \sqcup \bigsqcup_{c \in \text{children}(u)} \text{Out}(c)$$

### Invariant 2: Strict Partitioning at `OutOfFlowLayoutPart`
At every builder $u$, the incoming candidate set $\text{In}(u)$ is strictly partitioned into the consumed set $\text{Cons}(u)$ and the forwarded set $\text{Out}(u)$ based on the effective consumption predicate $P_{\text{consume}}(u, n)$:
$$\text{Cons}(u) = \{ n \in \text{In}(u) \mid P_{\text{consume}}(u, n) \}$$
$$\text{Out}(u) = \{ n \in \text{In}(u) \mid \neg P_{\text{consume}}(u, n) \}$$
$$\text{In}(u) = \text{Cons}(u) \cup \text{Out}(u) \quad \land \quad \text{Cons}(u) \cap \text{Out}(u) = \emptyset$$

### Invariant 3: Monotonic Subtree Growth Prior to Containing Block
For any OOF node $n \in \text{Gen}(u_0)$ whose effective consumer is ancestor $u_{\text{cb}}$, along the ancestor path $u_0 \prec u_1 \prec \dots \prec u_k \prec u_{\text{cb}}$, for all $0 \le i \le k$:
$$\neg P_{\text{consume}}(u_i, n) \implies n \in \text{Out}(u_i) \implies n \in \text{In}(u_{i+1})$$
The set of active unconsumed OOF candidates from any subtree without internal containing blocks grows monotonically as a union of child candidate sets.

### Invariant 4: Conservation of OOF Nodes (No Loss / No Duplication)
Across the entire layout tree rooted at $r$ (the `LayoutView` / Initial Containing Block), since $P_{\text{consume}}(r, n) = \text{True}$ for all remaining $n$ (CSS-POSITION-3 guarantees the Initial Containing Block catches all unconsumed `fixed` and `absolute` elements), we have $\text{Out}(r) = \emptyset$, and:
$$\bigsqcup_{u \in \mathcal{T}} \text{Gen}(u) = \bigsqcup_{u \in \mathcal{T}} \text{Cons}(u)$$
Every generated OOF node is laid out **exactly once**.

### Invariant 5: Affine Coordinate Telescope
If $n$ originates at $u_0$ with local static offset $\vec{p}_0$ and is consumed at $u_m$, where $\vec{\delta}_i$ is the relative offset of $u_{i-1}$ inside $u_i$ (modulo writing-mode orthogonal transforms $M_i$), the static position evaluated at $u_m$ satisfies:
$$\vec{p}_m = M_m(\dots M_1(\vec{p}_0) + \vec{\delta}_1 \dots) + \vec{\delta}_m$$

---

## 5. Formal Verification in Rocq / Coq (`BlinkOOFBubblePropagationSemantics.v`)

Below is a complete, self-contained, and mechanized Rocq (Coq) formalization of Blink's OOF Candidate Bubbling semantics, proving partitioning, path propagation, conservation of OOF nodes across the layout tree, and coordinate