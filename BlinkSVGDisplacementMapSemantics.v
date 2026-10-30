Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink feDisplacementMap Coordinate Mapping Semantics *)
(** Filter Effects 1 §14: displacement mapping identity under scale=0 *)

Record Point2D := {
  px : Z;
  py : Z
}.

Definition displace_coordinate (pos : Point2D) (scale x_channel y_channel : Z) : Point2D :=
  {| px := px pos + scale * (x_channel - 128) / 256;
     py := py pos + scale * (y_channel - 128) / 256 |}.

Theorem zero_scale_is_identity : forall pos xc yc,
  displace_coordinate pos 0 xc yc = pos.
Proof.
  intros [x y] xc yc.
  unfold displace_coordinate; simpl.
  change (0 / 256) with 0.
  f_equal; lia.
Qed.
