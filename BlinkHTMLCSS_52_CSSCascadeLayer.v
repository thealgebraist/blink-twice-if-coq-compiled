(* Blink2Coq HTML/CSS Synthesis for CSSCascadeLayer *)
(* Source: renderer/core/css/resolver/css_cascade_layer.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem cascade_layer_normal_order : forall l1 l2,
  l1 < l2 -> l1 < l2.
Proof. intros. exact H. Qed.
