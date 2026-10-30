Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink :nth-child(An+B) Step Formula Semantics *)
(** CSS Selectors 4 §8.1: arithmetic progression index = A*k + B *)

Definition eval_nth_child (a b k : Z) : Z :=
  a * k + b.

Theorem nth_child_base_case : forall a b,
  eval_nth_child a b 0 = b.
Proof.
  intros a b.
  unfold eval_nth_child; lia.
Qed.

Theorem nth_child_step : forall a b k,
  eval_nth_child a b (k + 1) = eval_nth_child a b k + a.
Proof.
  intros a b k.
  unfold eval_nth_child; lia.
Qed.
