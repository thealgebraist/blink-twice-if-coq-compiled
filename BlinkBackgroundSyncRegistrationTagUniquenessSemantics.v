Require Import ZArith.
Require Import List.
Import ListNotations.
Open Scope Z_scope.

(** * Blink Background Sync Registration Tag Uniqueness Semantics *)
(** Web Background Sync §5.1: register(tag) uniqueness within scope *)

Fixpoint tag_exists (tag : Z) (tags : list Z) : bool :=
  match tags with
  | [] => false
  | x :: xs => if tag =? x then true else tag_exists tag xs
  end.

Definition register_sync_tag (tag : Z) (tags : list Z) : list Z :=
  if tag_exists tag tags then tags else tag :: tags.

Theorem register_existing_tag_idempotent : forall tag tags,
  tag_exists tag tags = true ->
  register_sync_tag tag tags = tags.
Proof.
  intros tag tags H.
  unfold register_sync_tag.
  rewrite H.
  reflexivity.
Qed.
