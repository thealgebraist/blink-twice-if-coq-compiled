Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MemoryCache LRU Monotonic Eviction Semantics *)
(** Blink Caching Architecture §3: eviction monotonically decreases total cache size *)

Definition evict_cache_entry (current_bytes entry_bytes : Z) : Z :=
  Z.max 0 (current_bytes - entry_bytes).

Theorem eviction_monotonically_reduces_size : forall c e,
  0 <= e ->
  0 <= c ->
  evict_cache_entry c e <= c.
Proof.
  intros c e He Hc.
  unfold evict_cache_entry.
  destruct (Z.max_spec 0 (c - e)) as [[H1 H2] | [H1 H2]]; rewrite H2; lia.
Qed.

Theorem eviction_exact_when_sufficient : forall c e,
  0 <= e <= c ->
  evict_cache_entry c e = c - e.
Proof.
  intros c e Hbounds.
  unfold evict_cache_entry.
  apply Z.max_r.
  lia.
Qed.
