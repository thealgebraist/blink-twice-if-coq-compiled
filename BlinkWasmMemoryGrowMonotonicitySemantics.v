Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebAssembly memory.grow Monotonicity Semantics *)
(** WebAssembly Core Spec §5.4: memory.grow increases page allocation up to max_pages *)

Definition grow_memory (current_pages delta max_pages : Z) : Z :=
  if current_pages + delta <=? max_pages then current_pages + delta
  else current_pages.

Theorem grow_memory_monotonic : forall c d m,
  0 <= c ->
  0 <= d ->
  c <= grow_memory c d m.
Proof.
  intros c d m Hc Hd.
  unfold grow_memory.
  destruct (c + d <=? m) eqn:Heq; lia.
Qed.

Theorem grow_memory_bounded : forall c d m,
  0 <= c <= m ->
  grow_memory c d m <= m.
Proof.
  intros c d m Hbounds.
  unfold grow_memory.
  destruct (c + d <=? m) eqn:Heq.
  - apply Z.leb_le in Heq. lia.
  - lia.
Qed.
