Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Canvas Stroke Half-Width Semantics *)
(** HTML Canvas 2D §4: stroke half-width derivation *)

Definition stroke_half_width (line_width : Z) : Z :=
  line_width / 2.

Theorem stroke_half_width_nonneg : forall lw,
  0 <= lw ->
  0 <= stroke_half_width lw.
Proof.
  intros lw Hlw.
  unfold stroke_half_width.
  apply Z.div_pos; lia.
Qed.
