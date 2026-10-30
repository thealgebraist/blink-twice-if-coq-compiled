From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* Blink Paint Chunk State Deduplication Equivalence *)
Record PaintChunkState := {
  pcs_transform_id : Z;
  pcs_clip_id : Z;
  pcs_effect_id : Z
}.

Definition chunk_state_eq (s1 s2 : PaintChunkState) : Prop :=
  pcs_transform_id s1 = pcs_transform_id s2 /\
  pcs_clip_id s1 = pcs_clip_id s2 /\
  pcs_effect_id s1 = pcs_effect_id s2.

Theorem chunk_state_eq_refl : forall s,
  chunk_state_eq s s.
Proof.
  intros [t c e]; unfold chunk_state_eq; cbn. auto.
Qed.

Theorem chunk_state_eq_sym : forall s1 s2,
  chunk_state_eq s1 s2 ->
  chunk_state_eq s2 s1.
Proof.
  intros s1 s2 [Ht [Hc He]].
  unfold chunk_state_eq. auto.
Qed.

Theorem chunk_state_eq_trans : forall s1 s2 s3,
  chunk_state_eq s1 s2 ->
  chunk_state_eq s2 s3 ->
  chunk_state_eq s1 s3.
Proof.
  intros s1 s2 s3 [Ht1 [Hc1 He1]] [Ht2 [Hc2 He2]].
  unfold chunk_state_eq.
  repeat split; etransitivity; eassumption.
Qed.
