Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feSpecularLighting Phong Model Semantics *)
(** Filter Effects 1 §18: Phong reflection intensity *)

Definition clamp_specular_intensity (intensity : Z) : Z :=
  Z.max 0 (Z.min 255 intensity).

Theorem specular_intensity_bounded : forall i,
  0 <= clamp_specular_intensity i <= 255.
Proof.
  intros i.
  unfold clamp_specular_intensity.
  lia.
Qed.
