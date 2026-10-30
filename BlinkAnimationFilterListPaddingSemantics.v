Require Import ZArith.
Require Import Lia.
Require Import List.
Import ListNotations.
Open Scope Z_scope.

(** * Blink Filter List Padding Semantics *)
(** Filter Effects 1 §7: neutral element list padding *)

Fixpoint pad_filter_list (l : list Z) (target_len : nat) : list Z :=
  match target_len with
  | O => l
  | S n =>
      match l with
      | [] => 0 :: pad_filter_list [] n
      | x :: xs => x :: pad_filter_list xs n
      end
  end.

Theorem pad_filter_list_length : forall target_len,
  length (pad_filter_list [] target_len) = target_len.
Proof.
  induction target_len as [| n IHn].
  - reflexivity.
  - simpl. f_equal. apply IHn.
Qed.
