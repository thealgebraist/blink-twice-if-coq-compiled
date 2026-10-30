Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Operator Horizontal Stretching Semantics *)
(** MathML Core §3.2.4: stretchy horizontal operator coverage *)

Definition stretch_operator_width (intrinsic_width target_width : Z) : Z :=
  Z.max (Z.max 0 intrinsic_width) (Z.max 0 target_width).

Theorem stretched_operator_covers_target_width : forall iw tw,
  0 <= tw ->
  tw <= stretch_operator_width iw tw.
Proof.
  intros iw tw Htw.
  unfold stretch_operator_width; lia.
Qed.
