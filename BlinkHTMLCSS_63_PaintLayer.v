(* Blink2Coq HTML/CSS Synthesis for PaintLayer *)
(* Source: renderer/core/paint/paint_layer.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem stacking_context_z_order : forall z_neg z_pos,
  z_neg < 0 -> 0 < z_pos -> z_neg < z_pos.
Proof. intros. lia. Qed.
