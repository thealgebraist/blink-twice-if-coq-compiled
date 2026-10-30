(******************************************************************************)
(* BlinkListMarkerSemantics.v                                                 *)
(* Sound Formal Specification for CSS List Markers & Counter Sizing           *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Lists and Counters Module Level 3 (§3 Markers, §4 Positioning)   *)
(* 2. Blink LayoutListMarker (`layout_list_marker.cc`), ListMarker, &         *)
(*    ListItemLayoutAlgorithm (`list_item_layout_algorithm.cc`)               *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Require Import BlinkPhysicalFragment.
Open Scope Z_scope.

Inductive ListMarkerPosition : Type :=
  | MarkerInside
  | MarkerOutside.

Record ListMarkerStyle := mkListMarkerStyle {
  lms_position : ListMarkerPosition;
  lms_intrinsic_w : Z;
  lms_spacing : Z
}.

Record MarkerPlacement := mkMarkerPlacement {
  mp_x : Z;
  mp_w : Z;
  mp_content_start_x : Z
}.

(** Resolves marker offset and content start position according to W3C Lists 3 §4 *)
Definition resolve_marker_placement (style : ListMarkerStyle) (content_box_x : Z) : MarkerPlacement :=
  let w := sat_clamp (lms_intrinsic_w style) in
  let s := sat_clamp (lms_spacing style) in
  match lms_position style with
  | MarkerInside =>
      (* Inside marker: marker sits at content_box_x; content starts after marker + spacing *)
      mkMarkerPlacement content_box_x w (content_box_x + w + s)
  | MarkerOutside =>
      (* Outside marker: marker sits to the left outside content; content starts at content_box_x *)
      mkMarkerPlacement (content_box_x - w - s) w content_box_x
  end.

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Theorem outside_marker_precedes_content :
  forall style content_x,
    lms_position style = MarkerOutside ->
    0 <= sat_clamp (lms_spacing style) ->
    let mp := resolve_marker_placement style content_x in
    mp_x mp + mp_w mp <= mp_content_start_x mp.
Proof.
  intros style content_x Hpos Hspacing.
  unfold resolve_marker_placement.
  rewrite Hpos. simpl. lia.
Qed.

Theorem marker_placement_deterministic :
  forall style cx r1 r2,
    r1 = resolve_marker_placement style cx ->
    r2 = resolve_marker_placement style cx ->
    r1 = r2.
Proof.
  intros style cx r1 r2 H1 H2. subst. reflexivity.
Qed.
