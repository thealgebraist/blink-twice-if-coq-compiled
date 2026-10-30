(* Blink2Coq HTML/CSS Synthesis for CullRect *)
(* Source: renderer/core/paint/cull_rect.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition intersect_cull_x (x1 x2 : Z) : Z := Z.max x1 x2.
Theorem cull_rect_intersection_bounds : forall x1 x2,
  x1 <= intersect_cull_x x1 x2.
Proof. intros. unfold intersect_cull_x. apply Z.le_max_l. Qed.
