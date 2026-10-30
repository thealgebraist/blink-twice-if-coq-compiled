Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Raster Invalidation Damage Rect Semantics *)
(** Blink Paint Invalidation §2: damage rect bounded within layer *)

Definition clamp_damage_span (rm rM lm lM : Z) : (Z * Z) :=
  (Z.max rm lm, Z.min rM lM).

Theorem damage_span_within_layer : forall rm rM lm lM,
  lm <= fst (clamp_damage_span rm rM lm lM) /\
  snd (clamp_damage_span rm rM lm lM) <= lM.
Proof.
  intros rm rM lm lM.
  unfold clamp_damage_span; simpl; lia.
Qed.
