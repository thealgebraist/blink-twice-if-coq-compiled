Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink File System Writable Seek Clamping Semantics *)
(** File System Access API §5: seek(position) non-negative clamp *)

Definition clamp_seek_pos (pos : Z) : Z :=
  if pos <=? 0 then 0 else pos.

Theorem clamp_seek_pos_nonneg : forall pos,
  clamp_seek_pos pos >= 0.
Proof.
  intros pos.
  unfold clamp_seek_pos.
  destruct (pos <=? 0) eqn:E.
  - lia.
  - apply Z.leb_gt in E. lia.
Qed.
