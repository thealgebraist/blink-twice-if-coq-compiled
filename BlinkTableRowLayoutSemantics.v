(* =========================================================================
   BlinkTableRowLayoutSemantics.v
   Formalization of Chromium Blink Table Row Height & Baseline Alignment
   Source: third_party/blink/renderer/core/layout/table/table_row_layout_algorithm.cc
   Specification: W3C CSS 2.1 §17.5.3 Row Height & Baseline Computation
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

Record RowLayoutInputs : Type := mkRowLayoutInputs {
  rli_specified_height : Z;
  rli_max_cell_height : Z;
  rli_max_cell_ascent : Z;
  rli_max_cell_descent : Z
}.

Definition compute_row_block_size (inp : RowLayoutInputs) : Z :=
  let h_content := Z.max inp.(rli_specified_height) inp.(rli_max_cell_height) in
  let h_baseline := inp.(rli_max_cell_ascent) + inp.(rli_max_cell_descent) in
  Z.max h_content h_baseline.

Definition compute_row_baseline (max_ascent : Z) (fallback_height : Z) : Z :=
  if max_ascent >? 0 then max_ascent else fallback_height.

Theorem row_height_bounds_specified :
  forall inp,
    inp.(rli_specified_height) <= compute_row_block_size inp.
Proof.
  intros inp.
  unfold compute_row_block_size.
  lia.
Qed.

Theorem row_height_bounds_cells :
  forall inp,
    inp.(rli_max_cell_height) <= compute_row_block_size inp.
Proof.
  intros inp.
  unfold compute_row_block_size.
  lia.
Qed.

Theorem row_height_bounds_baseline_sum :
  forall inp,
    inp.(rli_max_cell_ascent) + inp.(rli_max_cell_descent) <= compute_row_block_size inp.
Proof.
  intros inp.
  unfold compute_row_block_size.
  lia.
Qed.

Theorem row_height_nonneg :
  forall inp,
    0 <= inp.(rli_specified_height) ->
    0 <= inp.(rli_max_cell_height) ->
    0 <= inp.(rli_max_cell_ascent) ->
    0 <= inp.(rli_max_cell_descent) ->
    0 <= compute_row_block_size inp.
Proof.
  intros inp Hspec Hcell Hasc Hdesc.
  unfold compute_row_block_size.
  lia.
Qed.

Theorem compute_row_block_size_deterministic :
  forall inp h1 h2,
    h1 = compute_row_block_size inp ->
    h2 = compute_row_block_size inp ->
    h1 = h2.
Proof.
  intros inp h1 h2 H1 H2.
  subst. reflexivity.
Qed.

