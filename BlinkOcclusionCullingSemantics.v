Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Occlusion Culling Invariance Semantics *)
(** Blink Paint Layer §4: occluded primitives contribute zero alpha *)

Definition effective_raster_alpha (layer_alpha : Z) (is_occluded : bool) : Z :=
  if is_occluded then 0 else layer_alpha.

Theorem occluded_layer_zero_alpha : forall a,
  effective_raster_alpha a true = 0.
Proof.
  intros a; reflexivity.
Qed.

Theorem unoccluded_layer_preserves_alpha : forall a,
  effective_raster_alpha a false = a.
Proof.
  intros a; reflexivity.
Qed.
