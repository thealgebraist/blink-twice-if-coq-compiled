# Formal Verification Research Report: Subgrid Margin and Padding Passthrough Alignment in Chromium Blink

**Agent:** Formal Verification Agent 691 (W3C/WHATWG Layout Rules: Grid, Tables, Shapes)  
**Topic:** Subgrid margin and padding passthrough alignment into parent grid tracks  
**Chromium Source:** `third_party/blink/renderer/core/layout/grid/grid_node.cc`  
**Specification:** CSS Grid Layout Module Level 2, §2.2 & §3 (Subgrids: Sizing and Margin/Border/Padding Accumulation)  
**Formal Theory Target:** `BlinkSubgridMarginPaddingPassthroughSemantics.v`  
**Mathematical Property:** $\text{subgrid\_start\_offset} = \text{parent\_track\_start} + \text{subgrid\_margin\_start}$

---

## 1. Normative W3C CSS Grid Layout Level 2 Requirements

The CSS Grid Layout Module Level 2 specification introduces the `subgrid` keyword for `grid-template-columns` and `grid-template-rows`, enabling a nested grid container (the *subgrid*) to adopt the track sizing and alignment context of its parent grid container across the spanned grid tracks.

### 1.1 Track Adoption and Sizing Participation (§2 & §2.2)
Under CSS Grid Level 2 §2, when a grid item is itself a grid container and declares a subgridded axis:
1. **Track Sharing:** The subgrid does not establish an independent set of tracks in the subgridded dimension. Instead, its items participate directly in the intrinsic track sizing algorithm (§12) of the parent grid across the tracks spanned by the subgrid.
2. **Coordinate Alignment:** The inner grid tracks of the subgrid correspond 1-to-1 with the spanned tracks of the parent grid container.

### 1.2 Subgrid Margins, Borders, and Padding (§2.2 / §3)
Unlike an independent formatting context where a child grid’s margins, borders, and padding (MBP) merely offset the child container's content box as a monolithic whole, a subgrid's MBP must be absorbed *into* the outer edges of the first and last spanned tracks so that internal tracks remain strictly aligned with the parent grid's tracks:
1. **Start Edge Absorption:** The subgrid's start margin, start border, and start padding ($\text{MBP}_{\text{start}} = M_{\text{start}} + B_{\text{start}} + P_{\text{start}}$) act as an extra layer of margin on items placed in the *first* track of the subgrid during parent track sizing.
2. **End Edge Absorption:** Similarly, the subgrid's end margin, end border, and end padding ($\text{MBP}_{\text{end}} = M_{\text{end}} + B_{\text{end}} + P_{\text{end}}$) act as an extra layer of margin on items placed in the *last* track of the subgrid.
3. **Physical / Logical Coordinate Passthrough:**
   - The margin-box start of the subgrid aligns exactly with the start edge of the first spanned parent track ($\text{parent\_track\_start}$).
   - The border-box start of the subgrid is positioned at:
     $$\text{subgrid\_start\_offset} = \text{parent\_track\_start} + \text{subgrid\_margin\_start}$$
   - The content-box start of the subgrid (which coincides with the usable start of its first adopted track) is positioned at:
     $$\text{subgrid\_content\_start} = \text{subgrid\_start\_offset} + \text{subgrid\_border\_start} + \text{subgrid\_padding\_start}$$
   - For any internal track $i > 0$ (0-indexed within the subgrid's span $[S, E)$), its start offset in the parent's coordinate system equals $\text{parent\_track\_start}(S + i)$, which in the subgrid's local border-box coordinate system is shifted by $-\text{subgrid\_start\_offset}$.

---

## 2. Chromium Blink Implementation Details and Invariants

In Chromium Blink's LayoutNG Grid architecture (`third_party/blink/renderer/core/layout/grid/`), subgrid geometry and sizing contributions are orchestrated primarily within `grid_node.cc`, `grid_layout_algorithm.cc`, and `grid_Sizing_tree.h`.

### 2.1 Architectural Flow in `grid_node.cc`
`GridNode` represents a layout node with `display: grid` or `display: inline-grid`. During tree construction and track sizing:
1. **`GridNode::ConstructGridItems` & Subgrid Accumulation:**
   When a `GridNode` constructs its `GridItems`, it inspects child `GridItemData` instances. If a child `GridItemData::IsSubgrid()` is true, Blink recursively traverses the subgrid's descendants, lifting subgrid items into the ancestor sizing tree while accumulating the subgrid's outer edges.
2. **Margin/Border/Padding Passthrough (`SubgridMarginBorderPadding`):**
   In `grid_node.cc` (and helper structures in `grid_item.h` / `grid_layout_algorithm.cc`), when computing the sizing contribution or layout geometry of a subgrid:
   - The subgrid's physical/logical margins (`margins`) and borders/padding (`border_scrollbar_padding`) in the subgridded track direction are computed via `ComputeMarginsFor` and `ComputeBorders` + `ComputePadding`.
   - When translating parent `GridLayoutData` tracks into a subgrid's local `GridLayoutSubtree` (`LayoutGridTrackCollection::CreateSubgridTrackCollection`), the parent track offsets are sliced over the subgrid's `GridSpan(begin_line, end_line)`.
   - The subgrid's border-box offset relative to the parent grid container is anchored at `parent_track_start + subgrid_margin_start`.
   - Inside the subgrid's local coordinate space, the copied track collection applies `subgrid_border_padding_start` to the first track's start offset (reducing its available size for items in track $0$) and `subgrid_border_padding_end` to the last track's end offset, while shifting all copied track line offsets by `-(parent_track_start + subgrid_margin_start)`.

### 2.2 Critical Blink Layout Invariants
1. **Border-Box Offset Invariant:**
   $$\text{subgrid\_start\_offset} = \text{parent\_track\_start}(S) + M_{\text{start}}$$
2. **First Track Content Alignment Invariant:**
   The usable content area of track $0$ inside the subgrid starts at local offset $B_{\text{start}} + P_{\text{start}}$, which in parent coordinates equals $\text{parent\_track\_start}(S) + M_{\text{start}} + B_{\text{start}} + P_{\text{start}}$.
3. **Interior Track Passthrough Invariant:**
   For any interior track $k \in \{1, \dots, N-1\}$ of a subgrid spanning $N$ parent tracks starting at $S$, its global coordinate in the parent grid is strictly invariant under the subgrid's $M, B, P$:
   $$\text{subgrid\_start\_offset} + \text{local\_track\_start}(k) = \text{parent\_track\_start}(S + k)$$
4. **Total Span Conservation Invariant:**
   The sum of the subgrid's start/end margins, start/end border+padding, all reduced inner track sizes, and all $(N-1)$ gutter gaps equals the exact distance between the start of the first spanned parent track and the end of the last spanned parent track.
5. **Recursive Subgrid Nesting Invariant:**
   When a subgrid $G_2$ is nested inside another subgrid $G_1$ at relative track offset $0$, their start margins accumulate additively:
   $$\text{offset}(G_2) = \text{parent\_track\_start}(S) + M_{\text{start}}(G_1) + B_{\text{start}}(G_1) + P_{\text{start}}(G_1) + M_{\text{start}}(G_2)$$
   Wait—if $G_2$ is placed in track $0$ of $G_1$, $G_1$'s first track starts at local offset $B_{\text{start}}(G_1) + P_{\text{start}}(G_1)$, so $G_2$'s border box starts at $B_{\text{start}}(G_1) + P_{\text{start}}(G_1) + M_{\text{start}}(G_2)$ in $G_1$'s coordinate space, which in the root parent's coordinate space is $\text{parent\_track\_start}(S) + M_{\text{start}}(G_1) + B_{\text{start}}(G_1) + P_{\text{start}}(G_1) + M_{\text{start}}(G_2)$.

---

## 3. Formal Specification in Rocq/Coq (`BlinkSubgridMarginPaddingPassthroughSemantics.v`)

Below is the complete, self-contained formalization in Rocq/Coq using `ZArith` (representing Blink's fixed-point `LayoutUnit` raw integer ticks), `List`, `Bool`, and `Lia`.

```coq
(** * BlinkSubgridMarginPaddingPassthroughSemantics.v
    Formal Verification of W3C CSS Grid Layout Level 2 §2.2 & §3:
    Subgrid Margin, Border, and Padding Passthrough Alignment in Chromium Blink
    Source: third_party/blink/renderer/core/layout/grid/grid_node.cc
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Fundamental Layout Types *)

(** In Chromium Blink, LayoutUnit is a fixed-point 32/64-bit integer.
    We model LayoutUnit values directly in Z. *)
Definition LayoutUnit := Z.

(** Box edge dimensions along a single grid track axis (inline or block). *)
Record BoxEdges : Type := mkBoxEdges {
  margin_start  : LayoutUnit;
  margin_end    : LayoutUnit;
  border_start  : LayoutUnit;
  border_end    : LayoutUnit;
  padding_start : LayoutUnit;
  padding_end   : LayoutUnit
}.

(** Derived edge sums corresponding to Blink's BorderScrollbarPadding and Margin.*)
Definition border_padding_start (e : BoxEdges) : LayoutUnit :=
  border_start e + padding_start e.

Definition border_padding_end (e : BoxEdges) : LayoutUnit :=
  border_end e + padding_end e.

Definition mbp_start (e : BoxEdges) : LayoutUnit :=
  margin_start e + border_start e + padding_start e.

Definition mbp_end (e : BoxEdges) : LayoutUnit :=
  margin_end e + border_end e + padding_end e.

(** Non-negativity predicate for border and padding (W3C CSS Box Model invariant). *)
Definition wf_box_edges (e : BoxEdges) : Prop :=
  0 <= border_start e /\
  0 <= border_end e /\
  0 <= padding_start e /\
  0 <= padding_end e.

(** ** 2. Grid Track Representation *)

(** A resolved track interval in a grid track collection, specified by its
    start offset and base size in the grid container's coordinate space. *)
Record GridTrack : Type := mkGridTrack {
  track_start : LayoutUnit;
  track_size  : LayoutUnit
}.

Definition track_end (t : GridTrack) : LayoutUnit :=
  track_start t + track_size t.

(** Well-formedness of a single track: non-negative size. *)
Definition wf_track (t : GridTrack) : Prop :=
  0 <= track_size t.

(** A GridSpan represents a contiguous half-open range of tracks [span_start, span_end). *)
Record GridSpan : Type := mkGridSpan {
  span_start : nat;
  span_len   : nat  (** Number of spanned tracks; must be >= 1 for valid subgrids *)
}.

(** Slice a contiguous sub-list of tracks for a given GridSpan. *)
Definition slice_tracks (tracks : list GridTrack) (s : GridSpan) : list GridTrack :=
  firstn (span_len s) (skipn (span_start s) tracks).

(** ** 3. Blink Subgrid Passthrough Semantics (grid_node.cc) *)

(** Given the first spanned parent track and the subgrid's BoxEdges,
    compute the subgrid's border-box start offset in the parent's coordinate system. *)
Definition compute_subgrid_start_offset
  (parent_first_track : GridTrack) (edges : BoxEdges) : LayoutUnit :=
  track_start parent_first_track + margin_start edges.

(** Compute the subgrid's content-box start offset in the parent's coordinate system. *)
Definition compute_subgrid_content_start_offset
  (parent_first_track : GridTrack) (edges : BoxEdges) : LayoutUnit :=
  compute_subgrid_start_offset parent_first_track edges + border_padding_start edges.

(** Adjust a single parent track when adopted by a subgrid:
    - First track (is_first = true): start is shifted by +mbp_start (in parent coords),
      and its usable size is reduced by mbp_start.
    - Last track (is_last = true): usable size is reduced by mbp_end.
    - All local track coordinates are expressed relative to subgrid_start_offset. *)
Definition project_track_to_subgrid_local
  (subgrid_start_offset : LayoutUnit)
  (edges : BoxEdges)
  (is_first is_last : bool)
  (parent_track : GridTrack) : GridTrack :=
  let raw_local_start := track_start parent_track - subgrid_start_offset in
  let start_delta := if is_first then border_padding_start edges else 0 in
  let size_reduction_start := if is_first then mbp_start edges else 0 in
  let size_reduction_end   := if is_last  then mbp_end edges   else 0 in
  let local_start :=
    if is_first
    then border_padding_start edges
    else raw_local_start in
  let usable_size :=
    track_size parent_track - size_reduction_start - size_reduction_end in
  mkGridTrack local_start usable_size.

(** Project a list of spanned parent tracks into the subgrid's local coordinate system. *)
Fixpoint project_spanned_tracks_aux
  (subgrid_start_offset : LayoutUnit)
  (edges : BoxEdges)
  (is_first : bool)
  (spanned : list GridTrack) : list GridTrack :=
  match spanned with
  | [] => []
  | [t] =>
      [project_track_to_subgrid_local subgrid_start_offset edges is_first true t]
  | t :: rest =>
      project_track_to_subgrid_local subgrid_start_offset edges is_