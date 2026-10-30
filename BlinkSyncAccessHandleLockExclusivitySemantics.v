Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink File System SyncAccessHandle Lock Exclusivity Semantics *)
(** File System Access API §7: createSyncAccessHandle exclusive lock *)

Definition acquire_sync_lock (currently_locked : bool) : option bool :=
  if currently_locked then None else Some true.

Theorem locked_file_cannot_acquire :
  acquire_sync_lock true = None.
Proof.
  reflexivity.
Qed.

Theorem unlocked_file_acquires_lock :
  acquire_sync_lock false = Some true.
Proof.
  reflexivity.
Qed.
