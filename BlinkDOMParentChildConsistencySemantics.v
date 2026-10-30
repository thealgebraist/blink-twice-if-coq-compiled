Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink DOM Tree Bidirectional Consistency Semantics *)
(** DOM Standard §4.2: child.parentNode == parent consistency *)

Definition is_parent_of (p c : Z) (parent_map : Z -> Z) : bool :=
  parent_map c =? p.

Theorem parent_of_reflexive_check : forall p c m,
  m c = p ->
  is_parent_of p c m = true.
Proof.
  intros p c m H.
  unfold is_parent_of.
  rewrite H, Z.eqb_refl; reflexivity.
Qed.
