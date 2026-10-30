(* Blink2Coq Synthesis for BaselineUtils *)
(* Source: third_party/blink/renderer/core/layout/baseline_utils.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition compute_baseline_shift (max_ascent item_ascent : Z) : Z :=
  max_ascent - item_ascent.
Theorem baseline_shift_nonneg : forall ma ia,
  ia <= ma -> 0 <= compute_baseline_shift ma ia.
Proof. intros. unfold compute_baseline_shift. lia. Qed.
