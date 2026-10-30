(* Blink2Coq HTML/CSS Synthesis for KeyframeEffect *)
(* Source: renderer/core/animation/keyframe_effect_model.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem keyframe_offset_monotonic : forall o1 o2,
  0 <= o1 -> o1 <= o2 -> o2 <= 1000 -> o1 <= o2.
Proof. intros. lia. Qed.
