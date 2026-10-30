Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Shape Margin Expansion Geometry Semantics *)
(** CSS Shapes 1 §3.2: shape-margin expansion *)

Definition expand_shape_radius (r margin : Z) : Z :=
  r + Z.max 0 margin.

Theorem expanded_radius_ge_original : forall r margin,
  expand_shape_radius r margin >= r.
Proof.
  intros r margin.
  unfold expand_shape_radius.
  pose proof (Z.le_max_l 0 margin).
  lia.
Qed.
