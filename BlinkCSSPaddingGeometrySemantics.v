(* ========================================================================= *)
(*               BlinkCSSPaddingGeometrySemantics.v                          *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS Padding Geometry and Content Box   *)
(* Derivation per W3C CSS Box Model 3 §6.                                    *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Record PaddingStrut := mkPaddingStrut {
  pad_top : Z;
  pad_right : Z;
  pad_bottom : Z;
  pad_left : Z
}.

Definition valid_padding_strut (p : PaddingStrut) : Prop :=
  pad_top p >= 0 /\
  pad_right p >= 0 /\
  pad_bottom p >= 0 /\
  pad_left p >= 0.

Definition content_box_x (pad_x : Z) (p : PaddingStrut) : Z :=
  pad_x + pad_left p.

Definition content_box_y (pad_y : Z) (p : PaddingStrut) : Z :=
  pad_y + pad_top p.

Definition content_box_w (pad_w : Z) (p : PaddingStrut) : Z :=
  Z.max 0 (pad_w - pad_left p - pad_right p).

Definition content_box_h (pad_h : Z) (p : PaddingStrut) : Z :=
  Z.max 0 (pad_h - pad_top p - pad_bottom p).

Theorem content_box_w_nonneg : forall pad_w p,
  content_box_w pad_w p >= 0.
Proof.
  intros pad_w p.
  unfold content_box_w.
  apply Z.le_ge, Z.le_max_l.
Qed.

Theorem content_box_contained_x : forall pad_x pad_w p,
  valid_padding_strut p ->
  pad_w >= pad_left p + pad_right p ->
  pad_x <= content_box_x pad_x p /\
  content_box_x pad_x p + content_box_w pad_w p <= pad_x + pad_w.
Proof.
  intros pad_x pad_w p [Hpt [Hpr [Hpb Hpl]]] Hfit.
  unfold content_box_x, content_box_w.
  assert (Z.max 0 (pad_w - pad_left p - pad_right p) = pad_w - pad_left p - pad_right p).
  { apply Z.max_r; lia. }
  rewrite H.
  split; lia.
Qed.

Theorem content_box_contained_y : forall pad_y pad_h p,
  valid_padding_strut p ->
  pad_h >= pad_top p + pad_bottom p ->
  pad_y <= content_box_y pad_y p /\
  content_box_y pad_y p + content_box_h pad_h p <= pad_y + pad_h.
Proof.
  intros pad_y pad_h p [Hpt [Hpr [Hpb Hpl]]] Hfit.
  unfold content_box_y, content_box_h.
  assert (Z.max 0 (pad_h - pad_top p - pad_bottom p) = pad_h - pad_top p - pad_bottom p).
  { apply Z.max_r; lia. }
  rewrite H.
  split; lia.
Qed.
