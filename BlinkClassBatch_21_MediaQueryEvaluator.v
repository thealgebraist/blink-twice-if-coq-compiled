(* Blink2Coq Synthesis for MediaQueryEvaluator *)
(* Source: third_party/blink/renderer/core/css/media_query_evaluator.cc *)

Require Import Bool.
Theorem media_query_neg_involution : forall b : bool,
  negb (negb b) = b.
Proof. intros [|]; reflexivity. Qed.
