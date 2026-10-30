(* Blink2Coq Synthesis for PositionTryEvaluator *)
(* Source: third_party/blink/renderer/core/layout/position_try_evaluator.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem anchor_option_fits_viewport : forall x w vw,
  0 <= x -> x + w <= vw -> x + w <= vw.
Proof. intros. lia. Qed.
