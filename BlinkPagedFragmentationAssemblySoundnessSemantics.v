Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Paged Fragmentation Assembly Soundness Semantics *)
(** CSS Paged Media 3 §6: conservation of total block size *)

Definition paged_assembly_step (consumed_so_far fragment_height total_content : Z) : Z :=
  Z.min total_content (consumed_so_far + Z.max 0 fragment_height).

Theorem assembly_step_bounded_by_total : forall consumed h total,
  consumed <= total ->
  paged_assembly_step consumed h total <= total.
Proof.
  intros consumed h total Hle.
  unfold paged_assembly_step.
  lia.
Qed.

Theorem assembly_step_monotonic : forall consumed h total,
  consumed <= total ->
  consumed <= paged_assembly_step consumed h total.
Proof.
  intros consumed h total Hle.
  unfold paged_assembly_step.
  lia.
Qed.
