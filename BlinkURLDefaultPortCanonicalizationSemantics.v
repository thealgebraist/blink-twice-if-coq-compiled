Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink URL Default Port Canonicalization Semantics *)
(** WHATWG URL Standard §4.2: default port elision during canonicalization *)

Definition SCHEME_HTTP  : Z := 1.
Definition SCHEME_HTTPS : Z := 2.

Definition canonicalize_port (scheme : Z) (port : Z) : option Z :=
  if (scheme =? SCHEME_HTTP) && (port =? 80) then None
  else if (scheme =? SCHEME_HTTPS) && (port =? 443) then None
  else Some port.

Theorem http_port_80_canonicalized_to_none :
  canonicalize_port SCHEME_HTTP 80 = None.
Proof.
  reflexivity.
Qed.

Theorem https_port_443_canonicalized_to_none :
  canonicalize_port SCHEME_HTTPS 443 = None.
Proof.
  reflexivity.
Qed.

Theorem custom_port_preserved : forall p,
  p <> 80 ->
  canonicalize_port SCHEME_HTTP p = Some p.
Proof.
  intros p Hneq.
  unfold canonicalize_port, SCHEME_HTTP, SCHEME_HTTPS.
  apply Z.eqb_neq in Hneq.
  rewrite Hneq.
  reflexivity.
Qed.
