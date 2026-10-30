(* Blink2Coq HTML/CSS Synthesis for AnchorQueryEvaluator *)
(* Source: renderer/core/layout/anchor_query_evaluator.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition eval_anchor (val lo hi : Z) : Z :=
  if val <? lo then lo else if hi <? val then hi else val.
Theorem anchor_enclosure : forall val lo hi,
  lo <= hi -> lo <= eval_anchor val lo hi <= hi.
Proof.
  intros val lo hi Hle. unfold eval_anchor.
  destruct (val <? lo) eqn:E1.
  - apply Z.ltb_lt in E1. lia.
  - apply Z.ltb_ge in E1. destruct (hi <? val) eqn:E2.
    + apply Z.ltb_lt in E2. lia.
    + apply Z.ltb_ge in E2. lia.
Qed.
