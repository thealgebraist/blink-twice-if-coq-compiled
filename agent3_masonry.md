# Agent 3 Audit Report: Chromium Blink Masonry Layout vs. W3C CSS Masonry Layout

**Target:** `third_party/blink/renderer/core/layout/grid/` and `third_party/blink/renderer/core/layout/masonry/`  
**Spec Reference:** W3C CSS Grid Layout Module Level 3 (Masonry Layout) & CSS Box Alignment Module Level 3  
**Formalization Target:** `BlinkMasonrySemantics.v` (Rocq/Coq)

---

## 1. Core Data Structures in Blink Masonry

Blink’s Masonry implementation is built atop the LayoutNG infrastructure, sharing foundational primitives with `GridLayoutAlgorithm` while decoupling the two-dimensional matrix constraint in favor of a 1D track template + 1D running stack accumulation model.

### 1.1 `MasonryLayoutAlgorithm`
Inherits from `LayoutAlgorithm<GridNode, BoxFragmentBuilder, BlockBreakToken>`. It orchestrates the three phases of masonry layout:
1. **Track Sizing (Grid Axis):** Resolves `grid-template-columns` or `grid-template-rows` into absolute `LayoutUnit` sizes using `GridTrackSizingAlgorithm`.
2. **Item Placement & Stacking (Masonry Axis):** Iterates over `GridItems`, resolving their cross-axis span, measuring their block-axis contribution, and mutating the running track state.
3. **Fragment Generation:** Commits physical offsets to `BoxFragmentBuilder` and computes the intrinsic block size of the masonry container.

### 1.2 `MasonryTrackStack` (and Track Collection)
Represents the structural geometry of the non-masonry (grid) axis.
* **`GridSizingTrackCollection` / `MasonryTrackCollection`:** Maintains the explicit and implicit tracks along the grid axis. Each track $i \in [0, N-1]$ has an associated `offset` ($x_i$) and `size` ($w_i$) in `LayoutUnit`, alongside a resolved `grid_gap` ($g_{\text{cross}}$).
* **Item Grouping / Virtual Masonry Items:** Before final placement, items with definite and indefinite spans are categorized to compute intrinsic track sizes via the virtual item grouping mechanism specified in CSS Grid 3.

### 1.3 `RunningTrackLengths` (The Running Position Vector)
The core state machine vector during the placement phase:
```cpp
struct RunningTrackLengths {
  WTF::Vector<LayoutUnit> running_positions; // Size = N (number of grid-axis tracks)
  wtf_size_t auto_placement_cursor = 0;      // Used when masonry-auto-flow: next
  LayoutUnit masonry_axis_gap = LayoutUnit(); // row-gap or column-gap in masonry axis
};
```
* **`running_positions`:** A vector $R = \langle r_0, r_1, \dots, r_{N-1} \rangle$ where $r_i \in \mathbb{Z}_{\ge 0}$ (represented as 26.6 fixed-point `LayoutUnit`) tracks the current high-water mark (outer block-end edge of the lowest placed item) in track $i$.
* **Initialization:** $\forall i \in [0, N-1], r_i = \text{BorderScrollbarPadding}_{\text{start}}$.

---

## 2. Placement Algorithm Mechanics

Let $N$ be the number of tracks in the grid axis. Let $R^{(t)} = \langle r_0^{(t)}, \dots, r_{N-1}^{(t)} \rangle$ be the `running_positions` state before placing item $t$. Let $g_m$ be the masonry-axis gap.

An item $t$ has:
* **Span:** $s_t \in [1, N]$. (If $s_t > N$, it is clamped to $N$).
* **Placement Type:**
  * `Definite(i)`: Explicit start track $i \in [0, N - s_t]$.
  * `Indefinite`: Auto-placed.

### 2.1 Candidate Span Evaluation
For any valid starting track index $i \in [0, N - s_t]$, the item spans the contiguous track interval $I(i, s_t) = [i, i + s_t - 1]$.
Because an item cannot overlap previously placed items in any of the tracks it spans, its block-start offset if placed at index $i$ is determined by the maximum running position across that span:
$$\text{SpanPos}(R^{(t)}, i, s_t) = \max_{k \in [i, i + s_t - 1]} r_k^{(t)}$$

### 2.2 Finding the Target Track Index $i^*$
1. **Definite Placement:** If item $t$ has a definitegrid-axis placement starting at $i_{\text{def}}$, then $i^* = i_{\text{def}}$.
2. **Indefinite Placement (`masonry-auto-flow: pack` / default):**
   The algorithm searches all valid starting indices $i \in [0, N - s_t]$ to find the minimum $\text{SpanPos}$. Ties are broken by choosing the earliest track index (lowest $i$, or starting from the auto-placement cursor if `next` is specified):
   $$i^* = \min \left\{ i \in [0, N - s_t] \;\middle|\; \text{SpanPos}(R^{(t)}, i, s_t) = \min_{j \in [0, N - s_t]} \text{SpanPos}(R^{(t)}, j, s_t) \right\}$$
   *(Note: W3C introduces a `masonry-slack` threshold $\tau$. In Blink's baseline heuristic without slack or when $\tau = 0$, this is a strict `<` comparison during linear scan from $0$ to $N - s_t$.)*

### 2.3 Item Layout and Running Position Advancement
Once $i^*$ is selected:
1. **Cross-axis Sizing:** The available inline size (assuming column masonry) for item $t$ is computed from the `MasonryTrackCollection`:
   $$\text{InlineSize}_t = \left(\sum_{k=i^*}^{i^* + s_t - 1} w_k\right) + (s_t - 1) \cdot g_{\text{cross}}$$
2. **Sub-layout:** Blink constructs a `ConstraintSpace` with fixed inline size $\text{InlineSize}_t$ and invokes `Layout()` on the item's `BlockNode`. This yields a `PhysicalBoxFragment` with outer block size (margin box) $B_t = \max(0, \text{fragment.BlockSize}() + \text{margins})$.
3. **Coordinate Assignment:**
   * Grid-axis offset: $x_t = \text{TrackOffset}(i^*) + \text{MarginStart}_{\text{grid}}$.
   * Masonry-axis offset: $y_t = \text{SpanPos}(R^{(t)}, i^*, s_t) + \text{MarginStart}_{\text{masonry}}$.
4. **Advancing the Running Position:**
   Let $y_{\text{new}} = \text{SpanPos}(R^{(t)}, i^*, s_t) + B_t + g_m$.
   The state vector transitions to $R^{(t+1)}$:
   $$r_k^{(t+1)} = \begin{cases} y_{\text{new}} & \text{if } k \in [i^*, i^* + s_t - 1] \\ r_k^{(t)} & \text{otherwise} \end{cases}$$
   *(Edge Case Note: Gap $g_m$ is either applied before the next item is placed via a boolean `has_items[k]` flag, or appended immediately and stripped at the end when computing container intrinsic block size. In formalizing the core step, we model immediate advancement by $B_t \ge 0$, subsuming non-negative gaps into $B_t$).*

---

## 3. Cross-Axis Track Sizing vs. Main-Axis Running Stack Accumulation

The architectural separation between the two axes is the defining characteristic of Masonry layout:

| Dimension / Property | Cross-Axis (Grid Axis) | Main-Axis (Masonry Axis) |
| :--- | :--- | :--- |
| **Governing Spec** | CSS Grid Layout (Track Sizing Algorithm) | CSS Grid Level 3 (Masonry Layout) |
| **Blink Component** | `GridTrackSizingAlgorithm` | `MasonryLayoutAlgorithm::PlaceMasonryItems` |
| **Data Structure** | `GridSizingTrackCollection` (1D array of Tracks) | `RunningTrackLengths` (1D array of `LayoutUnit` accumulators) |
| **Dependency Direction** | **Phase 1:** Sized *before* item placement. Depends on intrinsic inline contributions of items. | **Phase 2:** Accumulated *during* item placement. Depends on resolved Cross-Axis track sizes to compute item block sizes ($B_t = f(\text{InlineSize}_t)$). |
| **Multi-Span Resolution** | Distributes extra space across flexible/intrinsic tracks via iterative freeze-and-distribute pass. | Synchronizes spanned tracks by setting all $k \in [i^*, i^*+s_t-1]$ to $\max_{k} r_k + B_t$, creating a horizontal "shelf" across the spanned tracks. |

### The Circularity Breaker (Virtual Item Grouping)
When a cross-axis track is intrinsically sized (`auto`, `min-content`, `max-content`), Blink cannot know which track an auto-placed item will land in until tracks are sized, yet cannot size tracks without knowing which items are in them. 
* **W3C & Blink Resolution:** In Phase 1, Blink groups auto-placed items by their span size $s$ into **Virtual Masonry Items**, synthesizing a single combined min-content and max-content contribution placed in *every* possible starting track position $i \in [0, N-s]$. Once Phase 1 locks the track widths $w_k$, Phase 2 executes concrete placement using `RunningTrackLengths`.

---

## 4. Mathematical Invariants, Edge Cases, and Divergences

### 4.1 Mathematical Invariants
1. **Deterministic Placement:** Given an initial track vector $R^{(0)}$ and a sequence of items $L$, the resulting placement assignments and final running positions $R^{(|L|)}$ are unique and deterministic.
2. **Track Monotonicity:** For all tracks $k \in [0, N-1]$ and step $t$, $r_k^{(t+1)} \ge r_k^{(t)}$ provided outer block size $B_t \ge 0$ and gap $g_m \ge 0$.
3. **Non-Negativity:** If $\forall k, r_k^{(0)} \ge 0$ and $\forall t, B_t \ge 0$, then $\forall t, k, r_k^{(t)} \ge 0$.
4. **Span Synchronization:** Immediately after placing item $t$ with span $s_t$ at index $i^*$, $\forall k_1, k_2 \in [i^*, i^* + s_t - 1], r_{k_1}^{(t+1)} = r_{k_2}^{(t+1)}$.
5. **Container Intrinsic Block Size Bound:** The intrinsic content block size of the masonry container is $\max_{k \in [0, N-1]} r_k^{(|L|)}$ (adjusted for trailing gaps).

### 4.2 Edge Cases & Blink vs. W3C Divergences

| Edge Case | W3C CSS Masonry Specification | Chromium Blink Implementation | Divergence / Audit Status |
| :--- | :--- | :--- | :--- |
| **Negative Outer Block Size ($B_t < 0$)** | Outer size is clamped at `0px` for grid/masonry track progression, OR negative margins pull subsequent items upward. Spec states running position advances by margin-box size. | If negative margins exceed border-box size, $B_t < 0$. If unclamped, $r_k^{(t+1)} < r_k^{(t)}$, violating Monotonicity. Blink clamps negative item contributions in specific grid contexts, but raw margin-box addition can pull running position backward. | **Potential Invariant Violation:** Monotonicity only holds if $B_t = \max(0, \text{MarginBox}_t)$. In formal semantics, $B_t \in \mathbb{N}$ enforces clamping. |
| **`LayoutUnit` Saturation** | CSS theoretically operates on $\mathbb{R}$. | Blink uses `LayoutUnit` (32-bit signed integer, 1/64th pixel precision, `kMaxLayoutUnit` $\approx 3.35 \times 10^7$ px). | Addition $r_k + B_t$ saturates at `LayoutUnit::Max()`. If saturated, ties occur across all saturated tracks, forcing placement to index $0$. |
| **`masonry-slack` (Tie-Breaking Threshold)** | Spec defines `masonry-slack` (default `1em`). Any track within `slack` of the absolute minimum $\min_j \text{SpanPos}(j)$ is eligible, and the *first* (or cursor-next) eligible track is chosen. | Early Blink prototypes implemented strict minimum ($\text{slack} = 0$) before adding support for `masonry-slack` / `item-tolerance`. | When `slack > 0`, the selected track $i^*$ is NOT necessarily the global minimum $\min_j \text{SpanPos}(j)$, but the first $i$ such that $\text{SpanPos}(i) - \min_j \text{SpanPos}(j) \le \text{slack}$. |
| **Over-sized Spans ($s_t > N$)** | Clamped to $N$. Start line clamped to $0$. | Clamped during `GridItemData` resolution prior to `PlaceMasonryItems`. | **Aligned.** |
| **Subgrid in Masonry Axis** | Items with `grid-template-rows: subgrid` must align to something, or fallback to normal layout because masonry axis has no tracks. | Blink forces subgrid along the masonry axis to behave as a standard non-subgridded formatting context (no tracks to subgrid to). | **Aligned** with CSS Grid 3 resolution. |

---

## 5. Formalization in Rocq/Coq (`BlinkMasonrySemantics.v`)

Below is the complete, self-contained Rocq/Coq formalization of Blink's Masonry Placement Engine. It defines the data structures, the multi-span `SpanPos` evaluation, the `masonry-slack` aware minimum-finding algorithm, running track updates, and complete proofs of the core invariants (**Determinism, Length Preservation, Non-Negativity, Monotonicity, and Span Synchronization**).

```coq
(** * BlinkMasonrySemantics.v
    Formalization of Chromium Blink Masonry Layout Placement & Running Track Accumulation
    Agent 3 Audit: Chromium Blink vs W3C CSS Masonry Layout *)

From Coq Require Import Arith.Arith.
From Coq Require Import Arith.PeanoNat.
From Coq Require Import Bool.Bool.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

(** ** 1. Core Data Structures *)

(** In Blink, LayoutUnit is a fixed-point integer. Since outer block sizes
    are clamped at 0 for progression (or modeled as non-negative ticks of 1/64px),
    we model layout coordinates using [nat]. *)
Definition LayoutUnit := nat.

(** RunningTrackLengths: Vector of current running block-end positions for each track. *)
Definition RunningTracks := list LayoutUnit.

(** Placement specifier for a Masonry Item along the Grid (Cross) Axis. *)
