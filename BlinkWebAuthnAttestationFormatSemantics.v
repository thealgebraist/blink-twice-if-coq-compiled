Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebAuthn Attestation Format Semantics *)
(** WebAuthn Level 3 §8: format discrimination *)

Definition ATTESTATION_NONE     : Z := 0.
Definition ATTESTATION_PACKED   : Z := 1.
Definition ATTESTATION_FIDO_U2F : Z := 2.

Theorem attestation_formats_distinct :
  ATTESTATION_NONE <> ATTESTATION_PACKED /\
  ATTESTATION_PACKED <> ATTESTATION_FIDO_U2F.
Proof.
  unfold ATTESTATION_NONE, ATTESTATION_PACKED, ATTESTATION_FIDO_U2F.
  lia.
Qed.
