(* ========================================================================= *)
(*               BlinkOverflowClippingSemantics.v                            *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS Overflow Clipping                  *)
(* per W3C CSS Overflow Module Level 3 §3.                                   *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Inductive OverflowMode : Type :=
  | OverflowVisible
  | OverflowHidden
  | OverflowClip.

Definition clip_rect_x (border_x : Z) (border_l : Z) : Z :=
  border_x + border_l.

Definition clip_rect_y (border_y : Z) (border_t : Z) : Z :=
  border_y + border_t.

Definition clip_rect_w (border_w : Z) (border_l border_r : Z) : Z :=
  Z.max 0 (border_w - border_l - border_r).

Definition clip_rect_h (border_h : Z) (border_t border_b : Z) : Z :=
  Z.max 0 (border_h - border_t - border_b).

Definition point_in_clip (px py b_x b_y b_w b_h bl br bt bb : Z) : Prop :=
  let cx := clip_rect_x b_x bl in
  let cy := clip_rect_y b_y bt in
  let cw := clip_rect_w b_w bl br in
  let ch := clip_rect_h b_h bt bb in
  cx <= px <= cx + cw /\ cy <= py <= cy + ch.

Theorem clip_rect_w_nonneg : forall b_w bl br,
  clip_rect_w b_w bl br >= 0.
Proof.
  intros. unfold clip_rect_w. apply Z.le_ge, Z.le_max_l.
Qed.

Theorem clip_rect_h_nonneg : forall b_h bt bb,
  clip_rect_h b_h bt bb >= 0.
Proof.
  intros. unfold clip_rect_h. apply Z.le_ge, Z.le_max_l.
Qed.

Theorem point_in_clip_contained : forall px py b_x b_y b_w b_h bl br bt bb,
  b_w >= bl + br ->
  b_h >= bt + bb ->
  bl >= 0 -> br >= 0 -> bt >= 0 -> bb >= 0 ->
  point_in_clip px py b_x b_y b_w b_h bl br bt bb ->
  b_x <= px <= b_x + b_w /\ b_y <= py <= b_y + b_h.
Proof.
  intros px py b_x b_y b_w b_h bl br bt bb Hw Hh Hbl Hbr Hbt Hbb Hpt.
  unfold point_in_clip in Hpt.
  unfold clip_rect_x, clip_rect_y, clip_rect_w, clip_rect_h in Hpt.
  assert (Z.max 0 (b_w - bl - br) = b_w - bl - br) by (apply Z.max_r; lia).
  assert (Z.max 0 (b_h - bt - bb) = b_h - bt - bb) by (apply Z.max_r; lia).
  rewrite H, H0 in Hpt.
  destruct Hpt as [[Hx1 Hx2] [Hy1 Hy2]].
  split; lia.
Qed.
