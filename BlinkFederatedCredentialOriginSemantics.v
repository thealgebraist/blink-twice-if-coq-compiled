Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink FederatedCredential Identity Provider Scheme Semantics *)
(** Credential Management Level 1 §5.2: IdP origin must use HTTPS *)

Definition SCHEME_HTTP  : Z := 1.
Definition SCHEME_HTTPS : Z := 2.

Definition is_valid_idp_scheme (scheme_id : Z) : bool :=
  scheme_id =? SCHEME_HTTPS.

Theorem https_idp_valid :
  is_valid_idp_scheme SCHEME_HTTPS = true.
Proof.
  reflexivity.
Qed.

Theorem http_idp_invalid :
  is_valid_idp_scheme SCHEME_HTTP = false.
Proof.
  reflexivity.
Qed.
