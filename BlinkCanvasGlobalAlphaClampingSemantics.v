Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Canvas globalAlpha Clamping Semantics *)
(** HTML Canvas 2D §3: globalAlpha clamped within [0, 1000] *)

Definition clamp_global_alpha (a : Z) : Z :=
  Z.max 0 (Z.min 1000 a).

Theorem global_alpha_bounded : forall a,
  0 <= clamp_global_alpha a <= 1000.
Proof.
  intros a.
  unfold clamp_global_alpha; lia.
Qed.
