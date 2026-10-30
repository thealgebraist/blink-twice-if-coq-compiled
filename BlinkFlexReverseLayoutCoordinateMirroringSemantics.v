Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Flex Reverse Layout Coordinate Mirroring Semantics *)
(** CSS Flexbox 1 §5.1: reverse coordinate transformation *)

Definition mirror_offset (offset item_sz container_sz : Z) : Z :=
  container_sz - offset - item_sz.

Theorem mirror_offset_involutive : forall offset item_sz container_sz,
  mirror_offset (mirror_offset offset item_sz container_sz) item_sz container_sz = offset.
Proof.
  intros offset item_sz container_sz.
  unfold mirror_offset.
  lia.
Qed.
