Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Autofill Field Classification Semantics *)
(** HTML Spec §4.10.18.7: Autofill field categories *)

Inductive autofill_category : Type :=
| CatContact
| CatAddress
| CatCreditCard
| CatCredential.

Definition category_to_int (c : autofill_category) : Z :=
  match c with
  | CatContact    => 0
  | CatAddress    => 1
  | CatCreditCard => 2
  | CatCredential => 3
  end.

Theorem category_distinctness : forall c1 c2,
  category_to_int c1 = category_to_int c2 -> c1 = c2.
Proof.
  intros c1 c2 H; destruct c1; destruct c2; simpl in H; try reflexivity; discriminate.
Qed.
