(* Blink2Coq Synthesis for CSSMathExpressionNode *)
(* Source: third_party/blink/renderer/core/css/css_math_expression_node.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem css_math_clamp_bounded : forall v lo hi,
  lo <= hi -> lo <= Z.max lo (Z.min v hi) <= hi.
Proof. intros. lia. Qed.
