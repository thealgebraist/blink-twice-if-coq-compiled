Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Bézier Curve Envelope Containment Semantics *)
(** HTML Canvas 2D §4: quadratic Bézier midpoint evaluation *)

Definition compute_bezier_midpoint (p0 p1 p2 : Z) : Z :=
  (p0 + 2 * p1 + p2) / 4.

Theorem bezier_midpoint_bounded_when_equal : forall p,
  compute_bezier_midpoint p p p = p.
Proof.
  intros p.
  unfold compute_bezier_midpoint.
  replace (p + 2 * p + p) with (p * 4) by ring.
  rewrite Z.div_mul by lia.
  reflexivity.
Qed.
