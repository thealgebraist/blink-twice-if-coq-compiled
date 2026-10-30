Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Canvas Radial Gradient Radii Clamping Semantics *)
(** HTML Canvas 2D §3: radial gradient radius non-negativity *)

Definition clamp_radius (r : Z) : Z :=
  Z.max 0 r.

Theorem radius_nonneg : forall r,
  0 <= clamp_radius r.
Proof.
  intros r.
  unfold clamp_radius; lia.
Qed.
