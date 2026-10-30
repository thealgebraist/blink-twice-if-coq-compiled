Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CSP Host Source Wildcard Matching Semantics *)
(** CSP Level 3 §6: *.example.com matches subdomains with depth >= 1 *)

Definition csp_wildcard_host_match (subdomain_depth : Z) : bool :=
  0 <? subdomain_depth.

Theorem csp_wildcard_allows_subdomain : forall d,
  0 < d ->
  csp_wildcard_host_match d = true.
Proof.
  intros d Hd.
  unfold csp_wildcard_host_match.
  apply Z.ltb_lt.
  exact Hd.
Qed.

Theorem csp_wildcard_rejects_apex :
  csp_wildcard_host_match 0 = false.
Proof.
  reflexivity.
Qed.
