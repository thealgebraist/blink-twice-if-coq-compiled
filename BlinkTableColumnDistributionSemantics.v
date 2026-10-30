(* =========================================================================
   BlinkTableColumnDistributionSemantics.v
   Formalization of Chromium Blink Table Column Width Distribution
   Source: third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc
           third_party/blink/renderer/core/layout/table/table_column_tracker.cc
   Specification: W3C CSS 2.1 §17.5.2 (Fixed) & §17.5.3 (Auto) Column Sizing
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Arith.Arith.
From Coq Require Import Lia.
Open Scope Z_scope.

Inductive ColumnKind : Type :=
  | ColFixed (specified_width : Z)
  | ColAuto.

Record TableColumnSpec : Type := mkTableColumnSpec {
  tcs_kind : ColumnKind;
  tcs_min_content : Z
}.

Definition resolve_2col_fixed_table
    (avail_inline : Z) (c1_fixed : Z) : Z * Z :=
  let w1 := c1_fixed in
  let rem := Z.max 0 (avail_inline - c1_fixed) in
  (w1, rem).

Definition distribute_equal_remaining_space
    (remaining_space : Z) (num_auto_cols : nat) : Z :=
  if (num_auto_cols =? 0)%nat then 0
  else remaining_space / (Z.of_nat num_auto_cols).

Theorem resolve_2col_space_conservation :
  forall avail_inline c1_fixed,
    0 <= c1_fixed ->
    c1_fixed <= avail_inline ->
    let (w1, w2) := resolve_2col_fixed_table avail_inline c1_fixed in
    w1 + w2 = avail_inline.
Proof.
  intros avail_inline c1_fixed Hc1pos Hc1le.
  unfold resolve_2col_fixed_table.
  simpl.
  lia.
Qed.

Theorem resolve_2col_widths_nonneg :
  forall avail_inline c1_fixed,
    0 <= c1_fixed ->
    0 <= avail_inline ->
    let (w1, w2) := resolve_2col_fixed_table avail_inline c1_fixed in
    0 <= w1 /\ 0 <= w2.
Proof.
  intros avail_inline c1_fixed Hc1pos Havail.
  unfold resolve_2col_fixed_table.
  simpl.
  split; [exact Hc1pos |].
  apply Z.le_max_l.
Qed.

Theorem distribute_equal_space_conservation :
  forall rem (n : nat),
    (0 < n)%nat ->
    (distribute_equal_remaining_space rem n) * (Z.of_nat n) + (rem mod (Z.of_nat n)) = rem.
Proof.
  intros rem n Hnpos.
  unfold distribute_equal_remaining_space.
  assert (Hneq : (n =? 0)%nat = false).
  { apply Nat.eqb_neq. lia. }
  rewrite Hneq.
  rewrite Z.mul_comm.
  symmetry.
  apply Z.div_mod.
  lia.
Qed.

Theorem resolve_2col_deterministic :
  forall avail c1 r1 r2,
    r1 = resolve_2col_fixed_table avail c1 ->
    r2 = resolve_2col_fixed_table avail c1 ->
    r1 = r2.
Proof.
  intros avail c1 r1 r2 H1 H2.
  subst. reflexivity.
Qed.
