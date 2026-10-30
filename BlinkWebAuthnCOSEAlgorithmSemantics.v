Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebAuthn COSE Algorithm Identifier Semantics *)
(** RFC 9053 §2.1: COSE algorithm identifiers *)

Definition COSE_ES256 : Z := -7.
Definition COSE_RS256 : Z := -257.
Definition COSE_EDDSA : Z := -8.

Theorem cose_algs_distinct :
  COSE_ES256 <> COSE_RS256 /\
  COSE_ES256 <> COSE_EDDSA.
Proof.
  unfold COSE_ES256, COSE_RS256, COSE_EDDSA.
  lia.
Qed.
