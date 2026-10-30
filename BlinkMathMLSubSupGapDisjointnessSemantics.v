Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML SubSup Gap Clearance Semantics *)
(** MathML Core §3.4.1: gap clearance between scripts *)

Definition compute_subsup_gap (sup_bottom sub_top : Z) : Z :=
  sup_bottom - sub_top.

Theorem subsup_gap_positive_implies_disjoint : forall sup_b sub_t,
  0 < compute_subsup_gap sup_b sub_t ->
  sub_t < sup_b.
Proof.
  intros sup_b sub_t Hgap.
  unfold compute_subsup_gap in Hgap.
  lia.
Qed.
