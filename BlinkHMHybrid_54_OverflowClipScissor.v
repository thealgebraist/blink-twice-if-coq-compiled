(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record OverflowClipScissor := mkOverflowClipScissor {
  overflowclipscissor_parent_x0 : Z;
  overflowclipscissor_parent_x1 : Z;
  overflowclipscissor_child_x0 : Z;
  overflowclipscissor_child_x1 : Z
}.

Definition scissor_intersect_span (px0 : Z) (px1 : Z) (cx0 : Z) (cx1 : Z) : Z :=
  Z.max 0 (Z.min px1 cx1 - Z.max px0 cx0).

Theorem scissor_intersect_span_within_parent :
  forall (px0 px1 cx0 cx1 : Z), px0 <= px1 -> 0 <= scissor_intersect_span px0 px1 cx0 cx1 <= px1 - px0.
Proof.
  intros px0 px1 cx0 cx1 Hp. unfold scissor_intersect_span. lia.
Qed.
