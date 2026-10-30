From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §17.6.2.1 Border Width Conflict Resolution *)
Definition resolve_border_width (w1 w2 : Z) : Z :=
  Z.max w1 w2.

Theorem resolve_border_width_ge_left : forall w1 w2,
  resolve_border_width w1 w2 >= w1.
Proof.
  intros. unfold resolve_border_width. lia.
Qed.

Theorem resolve_border_width_ge_right : forall w1 w2,
  resolve_border_width w1 w2 >= w2.
Proof.
  intros. unfold resolve_border_width. lia.
Qed.

Theorem resolve_border_width_comm : forall w1 w2,
  resolve_border_width w1 w2 = resolve_border_width w2 w1.
Proof.
  intros. unfold resolve_border_width. lia.
Qed.
