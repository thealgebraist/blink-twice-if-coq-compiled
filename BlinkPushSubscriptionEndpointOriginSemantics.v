Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Push Subscription Endpoint Origin Semantics *)
(** Push API §7: PushSubscription.endpoint must be absolute HTTPS URL *)

Definition is_valid_push_endpoint (is_https : bool) (has_host : bool) : bool :=
  is_https && has_host.

Theorem push_endpoint_sound : forall is_https has_host,
  is_valid_push_endpoint is_https has_host = true <->
  is_https = true /\ has_host = true.
Proof.
  intros is_https has_host.
  unfold is_valid_push_endpoint.
  apply andb_true_iff.
Qed.
