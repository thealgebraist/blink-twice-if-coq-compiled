(* ========================================================================= *)
(*               BlinkCSSBackgroundClipSemantics.v                           *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS Background Painting Area and       *)
(* Clipping per W3C CSS Backgrounds and Borders Module Level 3 §3.           *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Require Import BlinkCSSPaddingGeometrySemantics.
Open Scope Z_scope.

Inductive BackgroundClipMode : Type :=
  | ClipBorderBox
  | ClipPaddingBox
  | ClipContentBox.

Definition point_in_rect (px py rx ry rw rh : Z) : Prop :=
  rx <= px <= rx + rw /\ ry <= py <= ry + rh.

Theorem padding_box_contained_in_border_box : forall x y w h bl br bt bb,
  w >= bl + br ->
  h >= bt + bb ->
  bl >= 0 -> br >= 0 -> bt >= 0 -> bb >= 0 ->
  let pad_x := x + bl in
  let pad_y := y + bt in
  let pad_w := w - bl - br in
  let pad_h := h - bt - bb in
  forall px py,
  point_in_rect px py pad_x pad_y pad_w pad_h ->
  point_in_rect px py x y w h.
Proof.
  intros x y w h bl br bt bb Hw Hh Hbl Hbr Hbt Hbb pad_x pad_y pad_w pad_h px py [Hpx Hpy].
  unfold pad_x, pad_y, pad_w, pad_h in *.
  split; lia.
Qed.

Theorem content_box_contained_in_padding_box : forall pad_x pad_y pad_w pad_h p,
  valid_padding_strut p ->
  pad_w >= pad_left p + pad_right p ->
  pad_h >= pad_top p + pad_bottom p ->
  forall px py,
  point_in_rect px py (content_box_x pad_x p) (content_box_y pad_y p)
                      (content_box_w pad_w p) (content_box_h pad_h p) ->
  point_in_rect px py pad_x pad_y pad_w pad_h.
Proof.
  intros pad_x pad_y pad_w pad_h p Hval Hfit_w Hfit_h px py [Hpx Hpy].
  pose proof (content_box_contained_x pad_x pad_w p Hval Hfit_w) as [Hx_low Hx_high].
  pose proof (content_box_contained_y pad_y pad_h p Hval Hfit_h) as [Hy_low Hy_high].
  split; lia.
Qed.

Theorem content_box_transitive_in_border_box : forall x y w h bl br bt bb p,
  w >= bl + br ->
  h >= bt + bb ->
  bl >= 0 -> br >= 0 -> bt >= 0 -> bb >= 0 ->
  let pad_x := x + bl in
  let pad_y := y + bt in
  let pad_w := w - bl - br in
  let pad_h := h - bt - bb in
  valid_padding_strut p ->
  pad_w >= pad_left p + pad_right p ->
  pad_h >= pad_top p + pad_bottom p ->
  forall px py,
  point_in_rect px py (content_box_x pad_x p) (content_box_y pad_y p)
                      (content_box_w pad_w p) (content_box_h pad_h p) ->
  point_in_rect px py x y w h.
Proof.
  intros x y w h bl br bt bb p Hw Hh Hbl Hbr Hbt Hbb pad_x pad_y pad_w pad_h Hval Hfit_w Hfit_h px py Hpt.
  apply (padding_box_contained_in_border_box x y w h bl br bt bb Hw Hh Hbl Hbr Hbt Hbb px py).
  apply (content_box_contained_in_padding_box pad_x pad_y pad_w pad_h p Hval Hfit_w Hfit_h px py Hpt).
Qed.
