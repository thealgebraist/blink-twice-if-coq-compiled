Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Flexbox First/Last Baseline Alignment Semantics *)
(** CSS Flexbox 1 §8.3: baseline alignment offset *)

Definition baseline_offset (item_baseline max_baseline : Z) : Z :=
  max_baseline - item_baseline.

Theorem baseline_offset_nonneg : forall item_b max_b,
  item_b <= max_b ->
  baseline_offset item_b max_b >= 0.
Proof.
  intros item_b max_b Hle.
  unfold baseline_offset.
  lia.
Qed.
