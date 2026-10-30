Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Anchor Inset Clamping Semantics *)
(** CSS Anchor Positioning §3: inset-area clamping within containing block *)

Definition clamp_anchor_inset (pos min_pos max_pos : Z) : Z :=
  Z.max min_pos (Z.min max_pos pos).

Theorem anchor_inset_clamped_bounds : forall pos min_pos max_pos,
  min_pos <= max_pos ->
  min_pos <= clamp_anchor_inset pos min_pos max_pos <= max_pos.
Proof.
  intros pos min_pos max_pos H.
  unfold clamp_anchor_inset; lia.
Qed.

Theorem anchor_inset_clamped_idempotent : forall pos min_pos max_pos,
  clamp_anchor_inset (clamp_anchor_inset pos min_pos max_pos) min_pos max_pos =
  clamp_anchor_inset pos min_pos max_pos.
Proof.
  intros pos min_pos max_pos.
  unfold clamp_anchor_inset; lia.
Qed.
