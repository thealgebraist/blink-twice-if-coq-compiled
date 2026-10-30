From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* Blink LayoutNG Constraint Space Cache Key Equivalence *)
Record ConstraintSpaceKey := {
  csk_avail_inline : Z;
  csk_avail_block : Z;
  csk_pct_inline : Z;
  csk_pct_block : Z
}.

Definition space_key_eq (k1 k2 : ConstraintSpaceKey) : Prop :=
  csk_avail_inline k1 = csk_avail_inline k2 /\
  csk_avail_block k1 = csk_avail_block k2 /\
  csk_pct_inline k1 = csk_pct_inline k2 /\
  csk_pct_block k1 = csk_pct_block k2.

Theorem space_key_eq_refl : forall k,
  space_key_eq k k.
Proof.
  intros [ai ab pi pb]; unfold space_key_eq; cbn. auto.
Qed.

Theorem space_key_eq_sym : forall k1 k2,
  space_key_eq k1 k2 ->
  space_key_eq k2 k1.
Proof.
  intros k1 k2 [H1 [H2 [H3 H4]]]; unfold space_key_eq; auto.
Qed.

Theorem space_key_eq_trans : forall k1 k2 k3,
  space_key_eq k1 k2 ->
  space_key_eq k2 k3 ->
  space_key_eq k1 k3.
Proof.
  intros k1 k2 k3 [H1a [H2a [H3a H4a]]] [H1b [H2b [H3b H4b]]].
  unfold space_key_eq.
  repeat split; etransitivity; eassumption.
Qed.
