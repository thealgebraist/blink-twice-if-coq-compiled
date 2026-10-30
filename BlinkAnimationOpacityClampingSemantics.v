Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Opacity Animation Clamping Semantics *)
(** CSS Color 4 §4: opacity clamping in [0, 1000] *)

Definition clamp_animation_opacity (op : Z) : Z :=
  Z.max 0 (Z.min 1000 op).

Theorem animation_opacity_bounded : forall op,
  0 <= clamp_animation_opacity op <= 1000.
Proof.
  intros op.
  unfold clamp_animation_opacity.
  lia.
Qed.

Theorem animation_opacity_idempotent : forall op,
  clamp_animation_opacity (clamp_animation_opacity op) = clamp_animation_opacity op.
Proof.
  intros op.
  unfold clamp_animation_opacity.
  lia.
Qed.
