Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink File System Directory Create Idempotence Semantics *)
(** File System Access API §6: getDirectoryHandle(create: true) idempotence *)

Definition get_or_create_dir (entry_exists : bool) : bool :=
  true.

Theorem get_or_create_always_succeeds : forall ent_exists,
  get_or_create_dir ent_exists = true.
Proof.
  intros ent_exists.
  reflexivity.
Qed.
