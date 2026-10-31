(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record LineBoxStrut := mkLineBoxStrut {
  lineboxstrut_ascent : Z;
  lineboxstrut_descent : Z
}.

Definition union_ascent (a1 : Z) (a2 : Z) : Z :=
  Z.max a1 a2.

Theorem union_ascent_idempotent :
  forall (a : Z), union_ascent a a = a.
Proof.
  intros a. unfold union_ascent. apply Z.max_id.
Qed.
