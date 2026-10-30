(* ========================================================================= *)
(*               BlinkCSSBorderBoxSemantics.v                                *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS Border Box Geometry and Border     *)
(* Styles per W3C CSS Backgrounds and Borders Module Level 3 §4.             *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Inductive BorderStyle : Type :=
  | BorderNone
  | BorderHidden
  | BorderSolid
  | BorderDashed
  | BorderDotted
  | BorderDouble.

Definition effective_border_width (style : BorderStyle) (specified_w : Z) : Z :=
  match style with
  | BorderNone   => 0
  | BorderHidden => 0
  | _            => Z.max 0 specified_w
  end.

Theorem effective_border_width_nonneg : forall style w,
  effective_border_width style w >= 0.
Proof.
  intros style w.
  destruct style; simpl; [lia | lia | | | |]; apply Z.le_ge, Z.le_max_l.
Qed.

Theorem border_none_zero_width : forall w,
  effective_border_width BorderNone w = 0.
Proof.
  reflexivity.
Qed.

Definition outer_border_box_dim (inner_dim b_start b_end : Z) : Z :=
  inner_dim + b_start + b_end.

Theorem outer_border_box_ge_inner : forall inner_dim b_start b_end,
  inner_dim >= 0 ->
  b_start >= 0 ->
  b_end >= 0 ->
  outer_border_box_dim inner_dim b_start b_end >= inner_dim.
Proof.
  intros. unfold outer_border_box_dim. lia.
Qed.

Theorem border_box_area_monotonic : forall w h b_l b_r b_t b_b,
  w >= 0 ->
  h >= 0 ->
  b_l >= 0 ->
  b_r >= 0 ->
  b_t >= 0 ->
  b_b >= 0 ->
  (outer_border_box_dim w b_l b_r) * (outer_border_box_dim h b_t b_b) >= w * h.
Proof.
  intros w h b_l b_r b_t b_b Hw Hh Hbl Hbr Hbt Hbb.
  unfold outer_border_box_dim.
  assert (Hw_le: w <= w + b_l + b_r) by lia.
  assert (Hh_le: h <= h + b_t + b_b) by lia.
  nia.
Qed.
