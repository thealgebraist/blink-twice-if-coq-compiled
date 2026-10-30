Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink File System Handle Kind Semantics *)
(** File System Access API §4: FileSystemHandle.kind enum *)

Inductive fs_handle_kind : Type :=
| FSKindFile
| FSKindDirectory.

Definition fs_kind_to_int (k : fs_handle_kind) : Z :=
  match k with
  | FSKindFile      => 0
  | FSKindDirectory => 1
  end.

Theorem fs_kind_distinct : forall k1 k2,
  fs_kind_to_int k1 = fs_kind_to_int k2 -> k1 = k2.
Proof.
  intros k1 k2 H; destruct k1; destruct k2; simpl in H; try reflexivity; discriminate.
Qed.
