(* =========================================================================
   BlinkTableMinMaxSizesSemantics.v
   Formalization of Chromium Blink Table Intrinsic Min/Max Size Contributions
   Source: third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc
   Specification: W3C CSS 2.1 §17.5.2.2 & CSS Box Sizing Module Level 3
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

Record TableIntrinsicInputs2Col : Type := mkTableIntrinsicInputs2Col {
  tii_col0_min : Z;
  tii_col0_max : Z;
  tii_col1_min : Z;
  tii_col1_max : Z;
  tii_h_spacing : Z;
  tii_border_padding : Z;
  tii_specified_table_width : Z
}.

Definition compute_grid_min_content (inp : TableIntrinsicInputs2Col) : Z :=
  inp.(tii_col0_min) + inp.(tii_col1_min) + 3 * inp.(tii_h_spacing) + inp.(tii_border_padding).

Definition compute_grid_max_content (inp : TableIntrinsicInputs2Col) : Z :=
  inp.(tii_col0_max) + inp.(tii_col1_max) + 3 * inp.(tii_h_spacing) + inp.(tii_border_padding).

Definition compute_final_table_min_max (inp : TableIntrinsicInputs2Col) : Z * Z :=
  let g_min := compute_grid_min_content inp in
  let g_max := compute_grid_max_content inp in
  let final_min := g_min in
  let final_max := Z.max final_min (Z.max g_max inp.(tii_specified_table_width)) in
  (final_min, final_max).

Theorem grid_min_le_max :
  forall inp,
    inp.(tii_col0_min) <= inp.(tii_col0_max) ->
    inp.(tii_col1_min) <= inp.(tii_col1_max) ->
    compute_grid_min_content inp <= compute_grid_max_content inp.
Proof.
  intros inp Hc0 Hc1.
  unfold compute_grid_min_content, compute_grid_max_content.
  lia.
Qed.

Theorem final_table_min_le_max :
  forall inp,
    let (t_min, t_max) := compute_final_table_min_max inp in
    t_min <= t_max.
Proof.
  intros inp.
  unfold compute_final_table_min_max.
  lia.
Qed.

Theorem table_min_ignores_smaller_specified_width :
  forall inp,
    let (t_min, _) := compute_final_table_min_max inp in
    t_min = compute_grid_min_content inp.
Proof.
  intros inp.
  unfold compute_final_table_min_max.
  reflexivity.
Qed.

Theorem compute_final_table_min_max_deterministic :
  forall inp r1 r2,
    r1 = compute_final_table_min_max inp ->
    r2 = compute_final_table_min_max inp ->
    r1 = r2.
Proof.
  intros inp r1 r2 H1 H2.
  subst. reflexivity.
Qed.

