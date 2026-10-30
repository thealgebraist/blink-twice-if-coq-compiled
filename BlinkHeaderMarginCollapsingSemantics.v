(* ========================================================================= *)
(*               BlinkHeaderMarginCollapsingSemantics.v                      *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Header & Sibling Margin Collapsing      *)
(* per W3C CSS 2.1 §8.3.1.                                                   *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Definition collapse_margins (m1 m2 : Z) : Z :=
  if (0 <=? m1) && (0 <=? m2) then
    Z.max m1 m2
  else if (m1 <=? 0) && (m2 <=? 0) then
    - (Z.max (- m1) (- m2))
  else
    m1 + m2.

Definition advance_block_cursor (cursor_y : Z) (margin : Z) (block_height : Z) : Z :=
  cursor_y + margin + block_height.

Theorem collapse_margins_comm : forall m1 m2,
  collapse_margins m1 m2 = collapse_margins m2 m1.
Proof.
  intros m1 m2.
  unfold collapse_margins.
  destruct (0 <=? m1) eqn:Hpos1; destruct (0 <=? m2) eqn:Hpos2; cbn.
  - rewrite (Z.max_comm m1 m2). reflexivity.
  - destruct (m1 <=? 0) eqn:Hneg1; destruct (m2 <=? 0) eqn:Hneg2; cbn.
    + rewrite (Z.max_comm (- m1) (- m2)). reflexivity.
    + ring.
    + ring.
    + ring.
  - destruct (m1 <=? 0) eqn:Hneg1; destruct (m2 <=? 0) eqn:Hneg2; cbn.
    + rewrite (Z.max_comm (- m1) (- m2)). reflexivity.
    + ring.
    + ring.
    + ring.
  - destruct (m1 <=? 0) eqn:Hneg1; destruct (m2 <=? 0) eqn:Hneg2; cbn.
    + rewrite (Z.max_comm (- m1) (- m2)). reflexivity.
    + ring.
    + ring.
    + ring.
Qed.

Theorem collapse_margins_nonneg_idempotent : forall m,
  m >= 0 ->
  collapse_margins m m = m.
Proof.
  intros m Hm.
  unfold collapse_margins.
  assert (Hpos: 0 <=? m = true) by (apply Z.leb_le; lia).
  rewrite Hpos; cbn.
  apply Z.max_id.
Qed.

Theorem collapse_margins_nonneg_bounds : forall m1 m2,
  m1 >= 0 -> m2 >= 0 ->
  Z.min m1 m2 <= collapse_margins m1 m2 <= Z.max m1 m2.
Proof.
  intros m1 m2 Hm1 Hm2.
  unfold collapse_margins.
  assert (Hpos1: 0 <=? m1 = true) by (apply Z.leb_le; lia).
  assert (Hpos2: 0 <=? m2 = true) by (apply Z.leb_le; lia).
  rewrite Hpos1, Hpos2; cbn.
  pose proof (Z.le_min_l m1 m2).
  pose proof (Z.le_min_r m1 m2).
  pose proof (Z.le_max_l m1 m2).
  pose proof (Z.le_max_r m1 m2).
  lia.
Qed.

Theorem advance_block_cursor_monotonic : forall y m h,
  m >= 0 -> h >= 0 ->
  advance_block_cursor y m h >= y.
Proof.
  intros y m h Hm Hh.
  unfold advance_block_cursor.
  lia.
Qed.

Theorem advance_block_cursor_strictly_increasing : forall y m h,
  m >= 0 -> h > 0 ->
  advance_block_cursor y m h > y.
Proof.
  intros y m h Hm Hh.
  unfold advance_block_cursor.
  lia.
Qed.

