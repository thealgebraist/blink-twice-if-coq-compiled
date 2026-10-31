(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record TextRun := mkTextRun {
  textrun_advance : Z;
  textrun_num_spaces : Z
}.

Definition expand_justified_run (adv : Z) (spaces : Z) (extra_per_space : Z) : Z :=
  adv + spaces * extra_per_space.

Theorem expand_justified_run_monotonic :
  forall (adv spaces extra : Z), 0 <= spaces -> 0 <= extra -> adv <= expand_justified_run adv spaces extra.
Proof.
  intros adv spaces extra Hsp Hext.
  unfold expand_justified_run.
  assert (Hmul: 0 <= spaces * extra) by (apply Z.mul_nonneg_nonneg; lia).
  lia.
Qed.
