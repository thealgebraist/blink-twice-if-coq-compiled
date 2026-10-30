(* ========================================================================= *)
(*               BlinkStickyConstraintSemantics.v                            *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Sticky Positioning Constraints         *)
(* per W3C CSS Positioned Layout Module Level 3 §6.                          *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Definition clamp_sticky_y
  (static_y : Z) (elem_h : Z) (cb_bottom : Z) (scroll_y : Z) (top_inset : Z) : Z :=
  let min_y := static_y in
  let max_y := Z.max static_y (cb_bottom - elem_h) in
  let target_y := scroll_y + top_inset in
  Z.max min_y (Z.min max_y target_y).

Theorem sticky_y_ge_static : forall static_y elem_h cb_bottom scroll_y top_inset,
  clamp_sticky_y static_y elem_h cb_bottom scroll_y top_inset >= static_y.
Proof.
  intros. unfold clamp_sticky_y.
  apply Z.le_ge, Z.le_max_l.
Qed.

Theorem sticky_y_bounded_above : forall static_y elem_h cb_bottom scroll_y top_inset,
  clamp_sticky_y static_y elem_h cb_bottom scroll_y top_inset <=
  Z.max static_y (cb_bottom - elem_h).
Proof.
  intros. unfold clamp_sticky_y.
  destruct (Z.max_spec static_y (cb_bottom - elem_h)) as [[_ Hmax] | [_ Hmax]];
  rewrite Hmax.
  - assert (Hmin: Z.min (cb_bottom - elem_h) (scroll_y + top_inset) <= cb_bottom - elem_h).
    { apply Z.le_min_l. }
    destruct (Z.max_spec static_y (Z.min (cb_bottom - elem_h) (scroll_y + top_inset))) as [[_ Hmax2] | [_ Hmax2]];
    rewrite Hmax2; lia.
  - assert (Hmin: Z.min static_y (scroll_y + top_inset) <= static_y).
    { apply Z.le_min_l. }
    destruct (Z.max_spec static_y (Z.min static_y (scroll_y + top_inset))) as [[_ Hmax2] | [_ Hmax2]];
    rewrite Hmax2; lia.
Qed.

Theorem sticky_does_not_exceed_cb : forall static_y elem_h cb_bottom scroll_y top_inset,
  static_y + elem_h <= cb_bottom ->
  clamp_sticky_y static_y elem_h cb_bottom scroll_y top_inset + elem_h <= cb_bottom.
Proof.
  intros static_y elem_h cb_bottom scroll_y top_inset Hfit.
  pose proof (sticky_y_bounded_above static_y elem_h cb_bottom scroll_y top_inset) as Hub.
  assert (Z.max static_y (cb_bottom - elem_h) = cb_bottom - elem_h).
  { apply Z.max_r; lia. }
  rewrite H in Hub.
  lia.
Qed.
