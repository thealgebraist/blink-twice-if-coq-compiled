From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Selectors 4 §4.2 :is() Pseudo-Class Specificity Maximum *)
Definition spec_max_component (c1 c2 : Z) : Z :=
  Z.max c1 c2.

Theorem spec_max_ge_left : forall c1 c2,
  spec_max_component c1 c2 >= c1.
Proof.
  intros. unfold spec_max_component.
  apply Z.le_ge. apply Z.le_max_l.
Qed.

Theorem spec_max_ge_right : forall c1 c2,
  spec_max_component c1 c2 >= c2.
Proof.
  intros. unfold spec_max_component.
  apply Z.le_ge. apply Z.le_max_r.
Qed.

Theorem spec_max_comm : forall c1 c2,
  spec_max_component c1 c2 = spec_max_component c2 c1.
Proof.
  intros. unfold spec_max_component. lia.
Qed.
