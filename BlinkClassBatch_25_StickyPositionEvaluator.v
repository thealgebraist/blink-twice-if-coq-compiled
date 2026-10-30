(* Blink2Coq Synthesis for StickyPositionEvaluator *)
(* Source: third_party/blink/renderer/core/layout/sticky_position_evaluator.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition compute_sticky_offset (off min_off max_off : Z) : Z :=
  if off <? min_off then min_off else if max_off <? off then max_off else off.
Theorem sticky_offset_bounded : forall off mi ma,
  mi <= ma -> mi <= compute_sticky_offset off mi ma <= ma.
Proof.
  intros off mi ma Hle. unfold compute_sticky_offset.
  destruct (off <? mi) eqn:E1; [apply Z.ltb_lt in E1; lia | apply Z.ltb_ge in E1].
  destruct (ma <? off) eqn:E2; [apply Z.ltb_lt in E2; lia | apply Z.ltb_ge in E2; lia].
Qed.
