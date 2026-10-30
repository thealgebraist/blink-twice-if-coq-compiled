### 1. Representation in `LayoutOutsideListMarker`

In Chromium Blink (`third_party/blink/renderer/core/layout/`), outside list markers are represented by the `LayoutOutsideListMarker` class (which inherits from `LayoutBlockFlow`) and formatted by the Next-Gen layout engine via `BlockNode` and `OutsideListMarkerLayoutAlgorithm` (or handled during `BlockLayoutAlgorithm::PositionOrPropagateListMarker`).

Key architectural mechanics:
* **Out-of-Flow-like Inline Positioning:** Although `LayoutOutsideListMarker` is DOM-wise and layout-tree-wise a child of `LayoutListItem`, it does not participate in the normal inline formatting context flow of the list item's principal block box in the same way an `inside` marker does. Instead, its inline size (`marker_width`) and margin/spacing (`marker_spacing`) are computed independently.
* **Margin / Intrinsic Spacing:** Blink computes the marker's inline margins using `ListMarker::InlineMarginsForOutside`. For typical text/symbol markers (e.g., `disc`, `decimal`), the marker's inline offset is calculated relative to the list item's content box start edge.
* **Line-Box Alignment:** Vertically (in the block direction), the marker is aligned with the baseline of the first line box of the list item's content (or the top border/padding edge if the list item is empty or lacks a baseline). In the inline direction, it is shifted outside the content box.

---

### 2. Outside Placement Mechanics (CSS Lists 3 §3 vs. Blink)

According to **CSS Lists and Counters Module Level 3 §3.1 (`list-style-position: outside`)**, the marker box is placed outside the principal block box of the list item. While CSS Lists 3 leaves the exact inline offset somewhat flexible to user agents for legacy compatibility (unless `marker-side` and modern box models are strictly applied), Blink enforces a deterministic geometric placement:

In a Left-to-Right (`LTR`) horizontal writing mode:
1. Let the list item's content box inline-start edge be at $X = 0$ in the local coordinate space of the list item's content area.
2. The marker has a computed non-negative inline width $W_{\text{marker}} \ge 0$ (`marker_width`).
3. A non-negative inline spacing (margin-end in LTR) $S_{\text{marker}} \ge 0$ (`marker_spacing`) separates the marker from the list item's content edge.
4. The marker's inline-start offset $X_{\text{marker}}$ relative to the list item's content box start edge is placed at:
   $$X_{\text{marker}} = -(W_{\text{marker}} + S_{\text{marker}})$$
5. Consequently, the marker's inline-end (right) edge is at:
   $$X_{\text{marker\_end}} = X_{\text{marker}} + W_{\text{marker}} = -S_{\text{marker}}$$

If the list item contains nested block elements with negative margins or special text-indent values, Blink adjusts the reference edge, but relative to the baseline content start edge ($0$), the marker sits entirely in the negative coordinate space.

---

### 3. Geometric & Layout Invariants

To verify Blink's outside list marker alignment against CSS Lists 3 §3, the following invariants must hold for all valid layout states in LTR mode:

1. **Non-Negative Advance (`marker_advance_nonneg`):**
   The total inline advance consumed outside the box, defined as $\text{Advance} = W_{\text{marker}} + S_{\text{marker}}$, is always non-negative ($\text{Advance} \ge 0$).
2. **Disjointness / No Overlap (`marker_content_disjoint`):**
   The right edge of the outside marker box must never exceed the left edge of the list item's principal content box:
   $$X_{\text{marker\_right}} \le X_{\text{content\_left}}$$
   Since $X_{\text{content\_left}} = 0$ and $X_{\text{marker\_right}} = -S_{\text{marker}}$, this holds whenever $S_{\text{marker}} \ge 0$.
3. **Strictly Negative Offset (`marker_offset_negative`):**
   Whenever the marker has a strictly positive width ($W_{\text{marker}} > 0$) or strictly positive spacing ($S_{\text{marker}} > 0$), the marker's inline-start offset relative to the content box is strictly negative ($X_{\text{marker}} < 0$).

---

### 4. Concrete Rocq/Coq Formalization

Below is the complete, self-contained formalization for `BlinkOutsideListMarkerAlignmentSemantics.v` using `Z` (integers, modeling Blink's fixed-point `LayoutUnit` raw values).

```coq
(** * BlinkOutsideListMarkerAlignmentSemantics.v
    Formal audit of Chromium Blink Outside List Marker Alignment
    against CSS Lists and Counters Module Level 3 §3.
    Agent 159. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Data Structures and Layout Types *)

(** In Blink, LayoutUnit is a fixed-point number represented as an integer.
    We model inline coordinates and dimensions in Z. *)
Definition LayoutUnit := Z.

(** Directionality of the list item formatting context. *)
Inductive TextDirection : Type :=
  | LTR
  | RTL.

(** Parameters for an Outside List Marker in Blink (LayoutOutsideListMarker). *)
Record OutsideMarkerMetrics : Type := mkOutsideMarkerMetrics {
  marker_width   : LayoutUnit; (** Inline size of the marker box *)
  marker_spacing : LayoutUnit; (** Inline margin/spacing between marker and content *)
}.

(** Well-formedness predicate for marker metrics:
    Both width and spacing are non-negative in standard Blink layout. *)
Definition wf_marker_metrics (m : OutsideMarkerMetrics) : Prop :=
  marker_width m >= 0 /\ marker_spacing m >= 0.

(** Strictly visible marker predicate:
    At least the width or the spacing is strictly positive. *)
Definition active_marker_metrics (m : OutsideMarkerMetrics) : Prop :=
  wf_marker_metrics m /\ (marker_width m > 0 \/ marker_spacing m > 0).

(** Representation of the List Item's content box inline edges. *)
Record ContentBoxEdges : Type := mkContentBoxEdges {
  content_left  : LayoutUnit;
  content_right : LayoutUnit;
}.

Definition wf_content_box (c : ContentBoxEdges) : Prop :=
  content_left c <= content_right c.

(** ** 2. Blink Outside Placement Semantics *)

(** Total inline distance the marker is shifted outside the content box. *)
Definition marker_advance (m : OutsideMarkerMetrics) : LayoutUnit :=
  marker_width m + marker_spacing m.

(** Inline offset of the marker's left edge relative to the content box origin (0) in LTR. *)
Definition compute_ltr_marker_offset (m : OutsideMarkerMetrics) : LayoutUnit :=
  - (marker_advance m).

(** Absolute inline coordinates [left, right] of the placed marker given a content box. *)
Record PlacedMarkerBox : Type := mkPlacedMarkerBox {
  marker_left  : LayoutUnit;
  marker_right : LayoutUnit;
}.

(** Blink's placement algorithm for LayoutOutsideListMarker in LTR and RTL. *)
Definition place_outside_marker
  (dir : TextDirection)
  (c : ContentBoxEdges)
  (m : OutsideMarkerMetrics) : PlacedMarkerBox :=
  match dir with
  | LTR =>
      let m_left := content_left c + compute_ltr_marker_offset m in
      mkPlacedMarkerBox m_left (m_left + marker_width m)
  | RTL =>
      let m_left := content_right c + marker_spacing m in
      mkPlacedMarkerBox m_left (m_left + marker_width m)
  end.

(** ** 3. Verification of Invariants and Theorems *)

(** Invariant 1: Marker advance is always non-negative for well-formed metrics. *)
Theorem marker_advance_nonneg :
  forall (m : OutsideMarkerMetrics),
    wf_marker_metrics m ->
    marker_advance m >= 0.
Proof.
  intros m [Hwidth Hspacing].
  unfold marker_advance.
  lia.
Qed.

(** Invariant 2: Marker width is preserved under placement. *)
Theorem placed_marker_width_preserved :
  forall (dir : TextDirection) (c : ContentBoxEdges) (m : OutsideMarkerMetrics),
    let p := place_outside_marker dir c m in
    marker_right p - marker_left p = marker_width m.
Proof.
  intros dir c m.
  destruct dir; simpl; lia.
Qed.

(** Invariant 3: LTR Disjointness (No Overlap).
    The marker's right edge is less than or equal to the list item's content left edge. *)
Theorem ltr_marker_content_disjoint :
  forall (c : ContentBoxEdges) (m : OutsideMarkerMetrics),
    wf_marker_metrics m ->
    let p := place_outside_marker LTR c m in
    marker_right p <= content_left c.
Proof.
  intros c m [Hwidth Hspacing] p.
  unfold p, place_outside_marker, compute_ltr_marker_offset, marker_advance.
  simpl.
  lia.
Qed.

(** Invariant 4: RTL Disjointness (No Overlap).
    In RTL, the marker's left edge is greater than or equal to the content right edge. *)
Theorem rtl_marker_content_disjoint :
  forall (c : ContentBoxEdges) (m : OutsideMarkerMetrics),
    wf_marker_metrics m ->
    let p := place_outside_marker RTL c m in
    content_right c <= marker_left p.
Proof.
  intros c m [Hwidth Hspacing] p.
  unfold p, place_outside_marker.
  simpl.
  lia.
Qed.

(** Invariant 5: Relative Offset Non-Positivity (LTR).
    Relative to the content box origin (content_left = 0), the marker offset is <= 0. *)
Theorem ltr_marker_offset_nonpositive :
  forall (m : OutsideMarkerMetrics),
    wf_marker_metrics m ->
    compute_ltr_marker_offset m <= 0.
Proof.
  intros m [Hwidth Hspacing].
  unfold compute_ltr_marker_offset, marker_advance.
  lia.
Qed.

(** Invariant 6: Strictly Negative Offset relative to Content Box (LTR).
    For any active marker (width > 0 or spacing > 0), the offset relative to
    the content box start edge is strictly negative. *)
Theorem ltr_marker_offset_strictly_negative :
  forall (m : OutsideMarkerMetrics),
    active_marker_metrics m ->
    compute_ltr_marker_offset m < 0.
Proof.
  intros m [[Hwidth Hspacing] Hactive].
  unfold compute_ltr_marker_offset, marker_advance.
  lia.
Qed.

(** Invariant 7: Exact separation between marker right edge and content left edge (LTR).
    Proves that the gap between the marker and the text edge is exactly marker_spacing. *)
Theorem ltr_marker_exact_gap :
  forall (c : ContentBoxEdges) (m : OutsideMarkerMetrics),
    let p := place_outside_marker LTR c m in
    content_left c - marker_right p = marker_spacing m.
Proof.
  intros c m p.
  unfold p, place_outside_marker, compute_ltr_marker_offset, marker_advance.
  simpl.
  lia.
Qed.
```