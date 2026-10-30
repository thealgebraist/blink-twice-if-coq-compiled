Require Import ZArith.
Require Import List.
Import ListNotations.
Open Scope Z_scope.

(** * Blink WebUSB Interface Number Uniqueness Semantics *)
(** WebUSB API §3.4 / USB 2.0 §9.6.3 interface numbering *)

Fixpoint interface_exists (id : Z) (l : list Z) : bool :=
  match l with
  | [] => false
  | x :: xs => if id =? x then true else interface_exists id xs
  end.

Definition add_interface (id : Z) (l : list Z) : option (list Z) :=
  if interface_exists id l then None else Some (id :: l).

Theorem add_unique_preserves_not_present : forall id l,
  interface_exists id l = false ->
  add_interface id l = Some (id :: l).
Proof.
  intros id l H.
  unfold add_interface.
  rewrite H.
  reflexivity.
Qed.
