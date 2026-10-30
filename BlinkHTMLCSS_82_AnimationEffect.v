(* Blink2Coq HTML/CSS Synthesis for AnimationEffect *)
(* Source: renderer/core/animation/animation_effect.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition composite_accumulate (base delta : Z) : Z := base + delta.
Theorem composite_accumulate_comm : forall b d,
  composite_accumulate b d = composite_accumulate d b.
Proof. intros. unfold composite_accumulate. apply Z.add_comm. Qed.
