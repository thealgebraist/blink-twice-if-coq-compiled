Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Clip Path SVG Path Bounding Box Semantics *)
(** CSS Masking 1 §3: clip-path basic shapes and path() bounds *)

Record path_bounding_box : Type := mk_path_box {
  bbox_min_x : Z;
  bbox_max_x : Z;
  bbox_min_y : Z;
  bbox_max_y : Z
}.

Definition is_valid_path_box (b : path_bounding_box) : bool :=
  (bbox_min_x b <=? bbox_max_x b) && (bbox_min_y b <=? bbox_max_y b).

Theorem valid_path_box_sound : forall b,
  is_valid_path_box b = true ->
  bbox_min_x b <= bbox_max_x b /\ bbox_min_y b <= bbox_max_y b.
Proof.
  intros [minx maxx miny maxy] H.
  unfold is_valid_path_box in H; simpl in H.
  apply andb_prop in H.
  destruct H as [Hx Hy].
  apply Z.leb_le in Hx.
  apply Z.leb_le in Hy.
  split; assumption.
Qed.
