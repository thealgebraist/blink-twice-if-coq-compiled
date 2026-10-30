Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Table Grid Baseline Alignment Semantics *)
(** MathML Core §3.7: row baseline from max cell ascent *)

Definition compute_row_baseline (cell_ascent1 cell_ascent2 : Z) : Z :=
  Z.max (Z.max 0 cell_ascent1) (Z.max 0 cell_ascent2).

Theorem row_baseline_covers_cell1 : forall ca1 ca2,
  0 <= ca1 ->
  ca1 <= compute_row_baseline ca1 ca2.
Proof.
  intros ca1 ca2 Hca1.
  unfold compute_row_baseline; lia.
Qed.

Theorem row_baseline_covers_cell2 : forall ca1 ca2,
  0 <= ca2 ->
  ca2 <= compute_row_baseline ca1 ca2.
Proof.
  intros ca1 ca2 Hca2.
  unfold compute_row_baseline; lia.
Qed.
