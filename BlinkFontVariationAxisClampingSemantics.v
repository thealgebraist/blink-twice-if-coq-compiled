Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Font Variation Axis Clamping Semantics *)
(** OpenType fvar §2: axis coordinate clamping *)

Definition clamp_variation_axis (val min_val max_val : Z) : Z :=
  Z.max min_val (Z.min max_val val).

Theorem variation_axis_clamped_bounds : forall val min_val max_val,
  min_val <= max_val ->
  min_val <= clamp_variation_axis val min_val max_val <= max_val.
Proof.
  intros val min_val max_val Hle.
  unfold clamp_variation_axis.
  lia.
Qed.
