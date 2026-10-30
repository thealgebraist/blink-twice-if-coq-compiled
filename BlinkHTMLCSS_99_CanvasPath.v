(* Blink2Coq HTML/CSS Synthesis for CanvasPath *)
(* Source: renderer/modules/canvas/canvas2d/canvas_path.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition expand_bbox_x (x_min x_max x : Z) : Z * Z :=
  (Z.min x_min x, Z.max x_max x).
Theorem bbox_contains_new_point : forall x_min x_max x,
  let (n_min, n_max) := expand_bbox_x x_min x_max x in
  n_min <= x <= n_max.
Proof.
  intros x_min x_max x. simpl. split.
  - apply Z.le_min_r.
  - apply Z.le_max_r.
Qed.
