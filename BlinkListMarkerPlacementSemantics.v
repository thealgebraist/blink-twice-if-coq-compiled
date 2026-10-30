(**
  BlinkListMarkerPlacementSemantics.v
  Formal specification of Chromium Blink list marker positioning (inside vs outside)
  derived from third_party/blink/renderer/core/layout/list/layout_inline_list_item.cc
  and core/layout/list/list_marker.cc
  according to W3C CSS Lists and Counters Module Level 3 (§3 Markers: list-style-position).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Inductive EListStylePosition : Type :=
  | ListMarkerInside
  | ListMarkerOutside.

Record MarkerMetrics := {
  marker_width : Z;
  suffix_spacing : Z
}.

Record LinePlacementResult := {
  marker_inline_offset : Z;
  content_inline_offset : Z;
  line_box_advance : Z
}.

Definition place_list_marker
    (pos : EListStylePosition) (m : MarkerMetrics) (content_w : Z) : LinePlacementResult :=
  let total_marker := m.(marker_width) + m.(suffix_spacing) in
  match pos with
  | ListMarkerInside => {|
      marker_inline_offset := 0;
      content_inline_offset := total_marker;
      line_box_advance := content_w + total_marker
    |}
  | ListMarkerOutside => {|
      marker_inline_offset := - total_marker;
      content_inline_offset := 0;
      line_box_advance := content_w
    |}
  end.

(** 1. Placement Geometry Invariants *)

Theorem inside_marker_increases_line_advance :
  forall (m : MarkerMetrics) (content_w : Z),
    let res := place_list_marker ListMarkerInside m content_w in
    res.(line_box_advance) - content_w = m.(marker_width) + m.(suffix_spacing).
Proof.
  intros m content_w res.
  unfold res, place_list_marker.
  simpl. lia.
Qed.

Theorem outside_marker_leaves_line_advance_invariant :
  forall (m : MarkerMetrics) (content_w : Z),
    let res := place_list_marker ListMarkerOutside m content_w in
    res.(line_box_advance) = content_w.
Proof.
  intros m content_w res.
  unfold res, place_list_marker.
  simpl. reflexivity.
Qed.

Theorem outside_marker_gutter_abutting :
  forall (m : MarkerMetrics) (content_w : Z),
    let res := place_list_marker ListMarkerOutside m content_w in
    res.(marker_inline_offset) + (m.(marker_width) + m.(suffix_spacing)) = 0.
Proof.
  intros m content_w res.
  unfold res, place_list_marker.
  simpl. lia.
Qed.

Theorem inside_content_offset_nonneg :
  forall (m : MarkerMetrics) (content_w : Z),
    0 <= m.(marker_width) ->
    0 <= m.(suffix_spacing) ->
    let res := place_list_marker ListMarkerInside m content_w in
    0 <= res.(content_inline_offset).
Proof.
  intros m content_w Hw Hs res.
  unfold res, place_list_marker.
  simpl. lia.
Qed.

