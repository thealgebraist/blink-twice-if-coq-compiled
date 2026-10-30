Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Reporting API Credential Filter Semantics *)
(** Reporting API §3: Report URL credential sanitization *)

Record reporting_url : Type := mk_rep_url {
  has_userinfo : bool;
  has_fragment : bool
}.

Definition sanitize_reporting_url (u : reporting_url) : reporting_url :=
  {| has_userinfo := false; has_fragment := false |}.

Theorem reporting_url_sanitized : forall u,
  has_userinfo (sanitize_reporting_url u) = false /\
  has_fragment (sanitize_reporting_url u) = false.
Proof.
  intros u.
  unfold sanitize_reporting_url.
  split; reflexivity.
Qed.
