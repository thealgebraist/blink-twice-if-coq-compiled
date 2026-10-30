Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Subgrid Margin Padding Passthrough Semantics *)
(** CSS Grid Layout 2 §3: subgrid margin passthrough *)

Definition subgrid_start_offset (parent_track_start margin_start : Z) : Z :=
  parent_track_start + margin_start.

Theorem subgrid_offset_monotonic : forall parent margin,
  margin >= 0 ->
  subgrid_start_offset parent margin >= parent.
Proof.
  intros parent margin Hge.
  unfold subgrid_start_offset.
  lia.
Qed.
