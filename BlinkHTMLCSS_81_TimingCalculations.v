(* Blink2Coq HTML/CSS Synthesis for TimingCalculations *)
(* Source: renderer/core/animation/timing_calculations.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition iteration_index (active_time duration : Z) : Z :=
  if duration <=? 0 then 0 else active_time / duration.
Theorem iteration_index_nonnegative : forall t d,
  0 <= t -> 0 < d -> 0 <= iteration_index t d.
Proof.
  intros t d Ht Hd. unfold iteration_index.
  assert (E: (d <=? 0) = false) by (apply Z.leb_gt; lia).
  rewrite E. apply Z.div_pos; lia.
Qed.
