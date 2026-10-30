(* Blink2Coq HTML/CSS Synthesis for ContainerQueryEvaluator *)
(* Source: renderer/core/css/container_query_evaluator.cc *)

From Stdlib Require Import ZArith Bool Lia. Open Scope Z_scope.
Definition eval_min_width_cq (container_w threshold : Z) : bool :=
  threshold <=? container_w.
Theorem container_query_monotonic : forall w1 w2 th,
  w1 <= w2 -> eval_min_width_cq w1 th = true -> eval_min_width_cq w2 th = true.
Proof.
  intros w1 w2 th Hle Hcq. unfold eval_min_width_cq in *.
  apply Z.leb_le in Hcq. apply Z.leb_le. lia.
Qed.
