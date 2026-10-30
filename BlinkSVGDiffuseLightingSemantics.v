Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feDiffuseLighting Lambertian Model Semantics *)
(** Filter Effects 1 §19: Lambertian cosine reflection bounds *)

Definition lambertian_diffuse (kd dot_nl : Z) : Z :=
  let positive_dot := Z.max 0 dot_nl in
  let raw := (kd * positive_dot) / 255 in
  Z.max 0 (Z.min 255 raw).

Theorem lambertian_diffuse_bounded : forall kd dot_nl,
  0 <= kd <= 255 ->
  0 <= lambertian_diffuse kd dot_nl <= 255.
Proof.
  intros kd dot_nl Hkd.
  unfold lambertian_diffuse.
  lia.
Qed.
