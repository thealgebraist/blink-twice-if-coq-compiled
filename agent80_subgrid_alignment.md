# Audit Report: Agent 80 — Chromium Blink CSS Subgrid Track Alignment vs. CSS Grid Layout Level 2 §2

**Target Specification**: W3C CSS Grid Layout Module Level 2, §2 (Subgrids)  
**Target Implementation**: Chromium Blink (`third_party/blink/renderer/core/layout/grid/`)  
**Verification Artifact**: `BlinkSubgridAlignmentSemantics.v`

---

## 1. Core Data Structures in Blink Subgrid

In Blink’s LayoutNG Grid architecture (`NGGridLayoutAlgorithm` / `GridLayoutAlgorithm`), subgrid track alignment is managed by decoupling track geometry ownership (held by the root grid) from local coordinate indexing (projected into subgrid layout data).

### 1.1 `GridSpan` (`grid_span.h`)
Represents a half-open interval $[start\_line, end\_line)$ in 0-indexed translated grid coordinates.
* **Fields**: `wtf_size_t start_line_`, `wtf_size_t end_line_`.
* **Invariants**: For definite spans, $0 \le start\_line\_ < end\_line\_$. The spanned track count is `SpanSize() = end_line_ - start_line_`.

### 1.2 `GridLayoutTrackCollection` & `GridSizingTrackCollection` (`grid_track_collection.h`)
Abstracts a sequence of tracks, ranges, and gutter sizes along a single axis (columns or rows).
* **Ranges**: Consecutive tracks sharing identical sizing properties are grouped into `Range` structs (`start_line`, `track_count`, `begin_set_index`, `set_count`).
* **Sets**: Actual sizing units (`GridSet`) storing `base_size`, `growth_limit`, and `track_count`.
* **Subgrid View**: When a subgrid inherits a parent’s track collection, Blink constructs a sub-collection view (`CreateSubgridTrackCollection(begin_range_index, end_range_index)`) that slices the parent’s ranges to the subgrid's spanned interval $[start\_line, end\_line)$, rebasing local track indices to start at `0`.

### 1.3 `GridLayoutSubtree` & `GridLayoutData` (`grid_data.h`)
During sizing and layout, a tree of grid contexts is maintained instead of copying track sets:
* **`GridLayoutData`**: Holds two pointers/instances of `GridLayoutTrackCollection` (`columns_` and `rows_`).
* **`GridLayoutSubtree`**: Wraps a pointer to the root `GridTree` and an index into a flat pre-order vector of `SubtreeNode`s. Each node stores its `GridLayoutData` (sliced from the parent along subgridded axes) and child node offsets.
* **`GridSizingTree` / `GridSizingSubtree`**: The mutable counterpart used during the track sizing algorithm (`InitializeTrackSizes`, `ResolveIntrinsicTrackSizes`), holding `GridNodes` (`GridItemData` for the subgrid container, its `GridLayoutData`, and its scoped `GridItems`).

---

## 2. Subgrid Track Alignment & Coordinate Mapping

Per **CSS Grid Layout Level 2 §2.1**, a subgrid does not define new tracks along its subgridded dimension(s); its tracks *are* the parent tracks it spans.

### 2.1 Index Translation Isomorphism
In CSS specification coordinates (1-indexed), if a subgrid spans parent grid lines $L_{start}$ to $L_{end}$ (where $K = L_{end} - L_{start} \ge 1$), the subgrid exposes $K$ local tracks indexed $1 \dots K$ (bounded by $K+1$ local lines $1 \dots K+1$).

In Blink’s internal 0-indexed translated coordinates:
* Let the parent grid have $N$ tracks indexed $0 \dots N-1$.
* Let the subgrid item occupy a resolved `GridSpan` $[S, E)$ on the parent, where $0 \le S < E \le N$ and $K = E - S$.
* A local subgrid track index $i_{local} \in [0, K-1]$ maps bijectively to the parent track index:
  $$\phi(i_{local}) = S + i_{local}$$
* Conversely, for an item placed inside the subgrid with local span $[s_{local}, e_{local}) \subseteq [0, K)$, its projection into the parent’s track sizing coordinate space is:
  $$\Phi([s_{local}, e_{local})) = [S + s_{local}, S + e_{local})$$

### 2.2 Nested Subgrid Composition
In Blink (`GridLayoutAlgorithm::BuildGridSizingSubtree`), if Subgrid $B$ (span $[S_B, E_B)$ in $A$) is nested inside Subgrid $A$ (span $[S_A, E_A)$ in Root), the translation composes associatively:
$$\phi_{A \circ B}(i) = S_A + (S_B + i) = (S_A + S_B) + i$$
Subject to the containment constraint $S_B + (E_B - S_B) \le E_A - S_A$.

---

## 3. Subgrid Margin, Border, and Padding (MBP) Absorption

Per **CSS Grid Layout Level 2 §2.3 & §2.4**, a subgrid container itself has layout edges (margin, border, scrollbar, padding) and may specify a different `column-gap` or `row-gap` than its parent. Because the subgrid's tracks must remain visually aligned with the parent's tracks, these edges cannot push all tracks uniformly without breaking alignment.

Blink resolves this during track sizing (`ComputeSubgridMarginBorderPadding` and item contribution accumulation in `GridLayoutAlgorithm`):

### 3.1 Edge Absorption into Boundary Tracks
Let the subgrid’s inline or block start edge sum be:
$$MBP_{start} = \text{margin}_{start} + \text{border}_{start} + \text{scrollbar}_{start} + \text{padding}_{start}$$
And the end edge sum be:
$$MBP_{end} = \text{margin}_{end} + \text{border}_{end} + \text{scrollbar}_{end} + \text{padding}_{end}$$

* **First Track ($i_{local} = 0$, Parent Track $S$)**: Absorbs $MBP_{start}$. Any subgrid item touching local line $0$ ($i_{local} = 0$) has its effective margin-box size contribution to Parent Track $S$ increased by $MBP_{start}$. Conversely, during layout positioning, the local available space inside Track $0$ is reduced by $MBP_{start}$ on the start side.
* **Last Track ($i_{local} = K - 1$, Parent Track $E - 1$)**: Absorbs $MBP_{end}$. Any subgrid item touching local line $K$ ($i_{local} = K-1$) has its contribution to Parent Track $E - 1$ increased by $MBP_{end}$.
* **Single-Track Degeneracy ($K = 1$, i.e., $S = E - 1$)**: Both $MBP_{start}$ and $MBP_{end}$ are absorbed into the single spanned track $S$. The extra size contribution is $MBP_{start} + MBP_{end}$.
* **Interior Tracks ($0 < i_{local} < K - 1$)**: Receive $0$ edge adjustment from this subgrid level.

### 3.2 Gutter (Gap) Difference Adjustment
If the parent grid has gutter size $G_{parent}$ and the subgrid has gutter size $G_{subgrid}$, the tracks remain aligned at their *centers* between gutters. Blink computes a `gutter_size_difference`:
$$\Delta G = \frac{G_{subgrid} - G_{parent}}{2}$$
For interior tracks, $\Delta G$ acts as virtual padding on both sides of the track ($2\Delta G$ total), while boundary tracks absorb $\Delta G$ on their inner gutter side.

---

## 4. Mathematical Invariants

1. **Track Cardinality Conservation**: The number of tracks exposed by a subgrid along a subgridded axis equals the exact span size of the subgrid item in its parent:
   $$|\text{Tracks}(Subgrid)| = E - S$$
2. **Order-Preserving Isomorphism**: The mapping $\phi: [0, K-1] \to [S, E-1]$ defined by $\phi(i) = S + i$ is strictly monotonic ($i < j \iff \phi(i) < \phi(j)$), injective, and surjective onto $[S, E-1]$.
3. **Span Containment Preservation**: Any valid local item span $[s, e) \subseteq [0, K)$ maps to a valid parent span $[\phi(s), \phi(e)) \subseteq [S, E) \subseteq [0, N)$ with invariant span length:
   $$\phi(e) - \phi(s) = (S + e) - (S + s) = e - s$$
4. **Additive MBP Partitioning**: Across all tracks $i \in [0, K-1]$ of a subgrid, the total edge overhead $\sum_{i=0}^{K-1} \text{Overhead}(i)$ equals $MBP_{start} + MBP_{end}$, regardless of whether $K = 1$ or $K > 1$.
5. **Determinism**: Given fixed parent track sizes, parent span $[S, E)$, and subgrid box edges $(MBP_{start}, MBP_{end})$, the projected parent track index and effective track contribution of any subgrid item are uniquely determined.

---

## 5. Formal Verification in Rocq/Coq (`BlinkSubgridAlignmentSemantics.v`)

The following standalone Rocq/Coq module formalizes Blink's subgrid data structures, coordinate translation, nested subgrid composition, and MBP boundary absorption, proving all required invariants without axioms.

```coq
(** * BlinkSubgridAlignmentSemantics.v
    Formal Audit of Chromium Blink CSS Subgrid Track Alignment
    against W3C CSS Grid Layout Module Level 2, Section 2.
    Agent 80 Verification Artifact. *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

Open Scope nat_scope.

(** ** 1. Core Data Structures *)

(** Represents Blink's [GridSpan] (0-indexed half-open interval [start_line, end_line)). *)
Record GridSpan : Type := mkGridSpan {
  span_start : nat;
  span_end   : nat
}.

(** A definite GridSpan in Blink must satisfy start_line < end_line. *)
Definition wf_span (s : GridSpan) : Prop :=
  span_start s < span_end s.

(** Number of tracks spanned ([GridSpan::SpanSize()]). *)
Definition span_size (s : GridSpan) : nat :=
  span_end s - span_start s.

(** A span [s] is contained within a grid of [num_tracks] tracks. *)
Definition span_in_bounds (s : GridSpan) (num_tracks : nat) : Prop :=
  wf_span s /\ span_end s <= num_tracks.

(** Subgrid Margin/Border/Padding (MBP) along a single axis. *)
Record SubgridEdges : Type := mkSubgridEdges {
  mbp_start : nat;
  mbp_end   : nat
}.

(** Represents a single track's sizing state in [GridTrackCollection]. *)
Record TrackSize : Type := mkTrackSize {
  base_size : nat
}.

(** Represents Blink's [GridData] / [SubgridData] along one axis. *)
Record SubgridData : Type := mkSubgridData {
  parent_track_count : nat;
  subgrid_span       : GridSpan;
  subgrid_edges      : SubgridEdges
}.

Definition wf_subgrid (sg : SubgridData) : Prop :=
  span_in_bounds (subgrid_span sg) (parent_track_count sg).

(** Number of local tracks in the subgrid. *)
Definition subgrid_track_count (sg : SubgridData) : nat :=
  span_size (subgrid_span sg).

(** ** 2. Subgrid Track Coordinate Translation *)

(** Maps a 0-indexed local subgrid track [local_idx] in [0, K-1]
    to the parent grid track in [start, start + K - 1]. *)
Definition local_to_parent_track (sg_span : GridSpan) (local_idx : nat) : nat :=
  span_start sg_span + local_idx.

(** Inverse mapping from parent track index to local subgrid track index. *)
Definition parent_to_local_track (sg_span : GridSpan) (parent_idx : nat) : nat :=
  parent_idx - span_start sg_span.

(** Translates a local item's [GridSpan] inside a subgrid into the parent grid's coordinate space. *)
Definition translate_span (sg_span : GridSpan) (item_local_span : GridSpan) : GridSpan :=
  mkGridSpan
    (span_start sg_span + span_start item_local_span)
    (span_start sg_span + span_end item_local_span).

(** Inductive relational specification of track alignment. *)
Inductive TrackAligned (sg : SubgridData) : nat -> nat -> Prop :=
  | Align_Track : forall local_idx parent_idx,
      wf_subgrid sg ->
      local_idx < subgrid_track_count sg ->
      parent_idx = local_to_parent_track (subgrid_span sg) local_idx ->
      TrackAligned sg local_idx parent_idx.

(** ** 3. Margin, Border, and Padding (MBP) Absorption *)

(** Computes the MBP absorbed by local track [local_idx] out of [K] total subgrid tracks.
    - Track 0 absorbs [mbp_start].
    - Track K-1 absorbs [mbp_end].
    - If K = 1, Track 0 absorbs both [mbp_start + mbp_end]. *)
Definition track_mbp_absorption (K : nat) (edges : SubgridEdges) (local_idx : nat) : nat :=
  let start_contrib := if Nat.eqb local_idx 0 then mbp_start edges else 0 in
  let end_contrib   := if Nat.eqb (S local_idx) K then mbp_end edges else 0 in
  start_contrib + end_contrib.

(** Inductive specification of MBP absorption per track role. *)
Inductive AbsorbMBP (K : nat) (edges : SubgridEdges) : nat -> nat -> Prop :=
  | Absorb_Single :
      K = 1 ->
      AbsorbMBP K edges 0 (mbp_start edges + mbp_end edges)
  | Absorb_First :
      K > 1 ->
      AbsorbMBP K edges 0 (mbp_start edges)
  | Absorb_Last : forall idx,
      K > 1 ->
      idx > 0 ->
      S idx = K ->
      AbsorbMBP K edges idx (mbp_end edges)
  | Absorb_Interior : forall idx,
      K > 1 ->
      idx > 0 ->
      S idx < K ->
      AbsorbMBP K edges idx 0.

(** Applies subgrid slice and MBP deduction to parent track sizes to yield local usable track sizes. *)
