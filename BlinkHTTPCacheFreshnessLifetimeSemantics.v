Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink HTTP Cache-Control Freshness Lifetime Semantics *)
(** RFC 9111 §4.2: freshness = max_age - current_age; is_fresh iff freshness > 0 *)

Definition freshness_lifetime (max_age current_age : Z) : Z :=
  max_age - current_age.

Definition is_cache_fresh (max_age current_age : Z) : bool :=
  0 <? freshness_lifetime max_age current_age.

Theorem fresh_when_under_max_age : forall m a,
  a < m ->
  is_cache_fresh m a = true.
Proof.
  intros m a Hlt.
  unfold is_cache_fresh, freshness_lifetime.
  apply Z.ltb_lt.
  lia.
Qed.

Theorem stale_when_at_or_above_max_age : forall m a,
  m <= a ->
  is_cache_fresh m a = false.
Proof.
  intros m a Hle.
  unfold is_cache_fresh, freshness_lifetime.
  apply Z.ltb_ge.
  lia.
Qed.
