(* ========================================================================= *)
(*               BlinkCSSFontWeightStyleSemantics.v                          *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS Font Weight & Style Resolution     *)
(* per W3C CSS Fonts Module Level 4 §2 & §5.                                 *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Definition clamp_font_weight (w : Z) : Z :=
  Z.max 100 (Z.min 900 w).

Theorem clamp_font_weight_bounds : forall w,
  100 <= clamp_font_weight w <= 900.
Proof.
  intros w. unfold clamp_font_weight.
  split; [apply Z.le_max_l |].
  apply Z.max_lub_iff.
  split; [lia | apply Z.le_min_l].
Qed.

Definition resolve_bolder_weight (inherited_w : Z) : Z :=
  let w := clamp_font_weight inherited_w in
  if w <? 350 then 400
  else if w <? 550 then 700
  else 900.

Definition resolve_lighter_weight (inherited_w : Z) : Z :=
  let w := clamp_font_weight inherited_w in
  if w <? 550 then 100
  else if w <? 750 then 400
  else 700.

Theorem bolder_weight_bounds : forall w,
  100 <= resolve_bolder_weight w <= 900.
Proof.
  intros w. unfold resolve_bolder_weight.
  destruct (clamp_font_weight w <? 350); [lia |].
  destruct (clamp_font_weight w <? 550); lia.
Qed.

Theorem lighter_weight_bounds : forall w,
  100 <= resolve_lighter_weight w <= 900.
Proof.
  intros w. unfold resolve_lighter_weight.
  destruct (clamp_font_weight w <? 550); [lia |].
  destruct (clamp_font_weight w <? 750); lia.
Qed.

Theorem bolder_ge_original_low : forall w,
  100 <= w <= 500 ->
  w <= resolve_bolder_weight w.
Proof.
  intros w Hw.
  unfold resolve_bolder_weight, clamp_font_weight.
  assert (Hclamp: Z.max 100 (Z.min 900 w) = w) by lia.
  rewrite Hclamp.
  destruct (w <? 350) eqn:E1; [apply Z.ltb_lt in E1; lia |].
  destruct (w <? 550) eqn:E2; [apply Z.ltb_lt in E2; lia |].
  apply Z.ltb_ge in E2; lia.
Qed.

Theorem lighter_le_original_high : forall w,
  550 <= w <= 900 ->
  resolve_lighter_weight w <= w.
Proof.
  intros w Hw.
  unfold resolve_lighter_weight, clamp_font_weight.
  assert (Hclamp: Z.max 100 (Z.min 900 w) = w) by lia.
  rewrite Hclamp.
  destruct (w <? 550) eqn:E1; [apply Z.ltb_lt in E1; lia |].
  destruct (w <? 750) eqn:E2; [apply Z.ltb_lt in E2; lia |].
  apply Z.ltb_ge in E2; lia.
Qed.
