Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Compositor Tile Grid Coverage Semantics *)
(** Blink Tile Manager §1: tiling grid covering viewport *)

Definition compute_tiling_span (num_tiles tile_size : Z) : Z :=
  num_tiles * tile_size.

Theorem tiling_span_monotonic : forall n1 n2 ts,
  0 <= ts ->
  n1 <= n2 ->
  compute_tiling_span n1 ts <= compute_tiling_span n2 ts.
Proof.
  intros n1 n2 ts Hts Hle.
  unfold compute_tiling_span.
  apply Z.mul_le_mono_nonneg_r; lia.
Qed.

Theorem tiling_span_zero_tiles : forall ts,
  compute_tiling_span 0 ts = 0.
Proof.
  intros ts.
  unfold compute_tiling_span; lia.
Qed.
