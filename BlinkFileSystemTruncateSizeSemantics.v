Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink File System Truncate Size Semantics *)
(** File System Access API §5: truncate(size) must be non-negative *)

Definition is_valid_truncate (sz : Z) : bool :=
  0 <=? sz.

Theorem truncate_size_sound : forall sz,
  is_valid_truncate sz = true <-> sz >= 0.
Proof.
  intros sz.
  unfold is_valid_truncate.
  split; intro H.
  - apply Z.leb_le in H. lia.
  - apply Z.leb_le. lia.
Qed.
