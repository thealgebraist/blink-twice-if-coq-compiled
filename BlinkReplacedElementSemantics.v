(* ========================================================================= *)
(*               BlinkReplacedElementSemantics.v                             *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Replaced Element Layout (img) and      *)
(* Aspect Ratio Preservation per CSS 2.1 §10.3.2 and CSS Sizing 3 §5.        *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Definition resolve_height_from_ratio (w : Z) (w0 h0 : Z) : Z :=
  if w0 <=? 0 then 0
  else (w * h0) / w0.

Definition resolve_width_from_ratio (h : Z) (w0 h0 : Z) : Z :=
  if h0 <=? 0 then 0
  else (h * w0) / h0.

Theorem resolve_height_nonneg : forall w w0 h0,
  w >= 0 ->
  w0 > 0 ->
  h0 >= 0 ->
  resolve_height_from_ratio w w0 h0 >= 0.
Proof.
  intros w w0 h0 Hw Hw0 Hh0.
  unfold resolve_height_from_ratio.
  destruct (w0 <=? 0) eqn:E; [lia |].
  apply Z.le_ge.
  apply Z.div_pos; [nia | lia].
Qed.

Theorem resolve_width_nonneg : forall h w0 h0,
  h >= 0 ->
  w0 >= 0 ->
  h0 > 0 ->
  resolve_width_from_ratio h w0 h0 >= 0.
Proof.
  intros h w0 h0 Hh Hw0 Hh0.
  unfold resolve_width_from_ratio.
  destruct (h0 <=? 0) eqn:E; [lia |].
  apply Z.le_ge.
  apply Z.div_pos; [nia | lia].
Qed.

Theorem exact_aspect_ratio_scaled : forall k w0 h0,
  k >= 0 ->
  w0 > 0 ->
  h0 >= 0 ->
  resolve_height_from_ratio (k * w0) w0 h0 = k * h0.
Proof.
  intros k w0 h0 Hk Hw0 Hh0.
  unfold resolve_height_from_ratio.
  destruct (w0 <=? 0) eqn:E; [lia |].
  assert (k * w0 * h0 = (k * h0) * w0) by ring.
  rewrite H.
  apply Z.div_mul.
  lia.
Qed.
