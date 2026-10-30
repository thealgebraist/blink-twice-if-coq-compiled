Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Operator Vertical Stretching Semantics *)
(** MathML Core §3.2.4: stretchy operator coverage *)

Definition stretch_operator_height (intrinsic_height target_height : Z) : Z :=
  Z.max (Z.max 0 intrinsic_height) (Z.max 0 target_height).

Theorem stretched_operator_covers_target : forall ih th,
  0 <= th ->
  th <= stretch_operator_height ih th.
Proof.
  intros ih th Hth.
  unfold stretch_operator_height; lia.
Qed.
