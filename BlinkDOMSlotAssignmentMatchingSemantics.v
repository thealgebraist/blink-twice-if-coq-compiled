Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink HTMLSlotElement Name Matching Semantics *)
(** DOM Standard §4.2.2: slotted child name matching *)

Definition match_slot_name (child_slot default_slot slot_name : Z) : bool :=
  orb (child_slot =? slot_name)
      (andb (child_slot =? 0) (slot_name =? default_slot)).

Theorem named_slot_matches_child : forall s def,
  match_slot_name s def s = true.
Proof.
  intros s def.
  unfold match_slot_name.
  rewrite Z.eqb_refl; reflexivity.
Qed.
