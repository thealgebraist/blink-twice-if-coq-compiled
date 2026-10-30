Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink ComputedStyle Equality Equivalence Relation Semantics *)
(** Blink ComputedStyle §1: ComputedStyle equality reflexivity and symmetry *)

Definition style_equal (s1 s2 : Z) : bool :=
  s1 =? s2.

Theorem style_equal_refl : forall s,
  style_equal s s = true.
Proof.
  intros s.
  unfold style_equal; apply Z.eqb_refl.
Qed.

Theorem style_equal_sym : forall s1 s2,
  style_equal s1 s2 = style_equal s2 s1.
Proof.
  intros s1 s2.
  unfold style_equal; apply Z.eqb_sym.
Qed.
