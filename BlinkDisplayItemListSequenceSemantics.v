From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* Blink Paint Pipeline Display Item List Order *)
Theorem display_item_append_length : forall {A : Type} (l : list A) (item : A),
  length (l ++ [item]) = S (length l).
Proof.
  intros A l item.
  rewrite app_length; cbn. lia.
Qed.

Theorem display_item_head_preserved : forall {A : Type} (h : A) (t : list A) (item : A),
  (h :: t) ++ [item] = h :: (t ++ [item]).
Proof.
  intros. reflexivity.
Qed.
