Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink SVG Path Parser and Bounding Box Semantics *)
(** SVG 2 §9: Path bounding box enclosure *)

Record BoundingBox := {
  bb_min_x : Z;
  bb_max_x : Z
}.

Definition update_bbox_x (bb : BoundingBox) (x : Z) : BoundingBox :=
  {| bb_min_x := Z.min (bb_min_x bb) x;
     bb_max_x := Z.max (bb_max_x bb) x |}.

Theorem update_bbox_encloses_point : forall bb x,
  bb_min_x (update_bbox_x bb x) <= x <= bb_max_x (update_bbox_x bb x).
Proof.
  intros bb x.
  unfold update_bbox_x; simpl.
  split; lia.
Qed.

Theorem update_bbox_preserves_prior_bounds : forall bb x,
  bb_min_x (update_bbox_x bb x) <= bb_min_x bb /\
  bb_max_x bb <= bb_max_x (update_bbox_x bb x).
Proof.
  intros bb x.
  unfold update_bbox_x; simpl.
  split; lia.
Qed.
