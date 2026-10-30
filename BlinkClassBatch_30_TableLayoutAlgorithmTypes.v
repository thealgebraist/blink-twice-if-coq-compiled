(* Blink2Coq Synthesis for TableLayoutAlgorithmTypes *)
(* Source: third_party/blink/renderer/core/layout/table/table_layout_algorithm_types.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition clamp_colgroup_span (sp : Z) : Z :=
  if sp <? 1 then 1 else if 1000 <? sp then 1000 else sp.
Theorem colgroup_span_bounded : forall sp,
  1 <= clamp_colgroup_span sp <= 1000.
Proof.
  intros. unfold clamp_colgroup_span.
  destruct (sp <? 1) eqn:E1; [apply Z.ltb_lt in E1; lia | apply Z.ltb_ge in E1].
  destruct (1000 <? sp) eqn:E2; [apply Z.ltb_lt in E2; lia | apply Z.ltb_ge in E2; lia].
Qed.
