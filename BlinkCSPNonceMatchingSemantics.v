Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CSP Nonce Matching Semantics *)
(** CSP Level 3 §5: script-src nonce constant-time matching *)

Definition csp_nonce_matches (header_nonce script_nonce : Z) : bool :=
  header_nonce =? script_nonce.

Theorem csp_nonce_sound : forall h s,
  csp_nonce_matches h s = true <-> h = s.
Proof.
  intros h s.
  unfold csp_nonce_matches.
  apply Z.eqb_eq.
Qed.
