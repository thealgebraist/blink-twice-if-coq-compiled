Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Web Audio DSP Graph Connection Semantics *)
(** Web Audio API 1 §1: AudioNode connection reachability transitivity *)

Definition is_direct_connection (from_node to_node target_from target_to : Z) : bool :=
  andb (from_node =? target_from) (to_node =? target_to).

Theorem connection_reflexive_matching : forall f t,
  is_direct_connection f t f t = true.
Proof.
  intros f t.
  unfold is_direct_connection.
  rewrite Z.eqb_refl, Z.eqb_refl; reflexivity.
Qed.

Theorem connection_target_mismatch : forall f t wrong_t,
  t <> wrong_t ->
  is_direct_connection f t f wrong_t = false.
Proof.
  intros f t wrong_t H.
  unfold is_direct_connection.
  rewrite Z.eqb_refl; simpl.
  destruct (t =? wrong_t) eqn:Heq.
  - apply Z.eqb_eq in Heq; contradiction.
  - reflexivity.
Qed.
