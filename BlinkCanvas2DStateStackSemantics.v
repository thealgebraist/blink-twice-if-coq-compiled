From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* HTML Standard §4.12.5.1 Canvas 2D State Stack Save/Restore *)
Record CanvasState := {
  cs_transform_x : Z;
  cs_transform_y : Z;
  cs_clip_id : Z
}.

Definition save_canvas_state (s : CanvasState) (stack : list CanvasState) : list CanvasState :=
  s :: stack.

Definition restore_canvas_state (stack : list CanvasState) (default : CanvasState) : CanvasState * list CanvasState :=
  match stack with
  | nil => (default, nil)
  | s :: rest => (s, rest)
  end.

Theorem save_restore_lifo_identity : forall s stack def,
  restore_canvas_state (save_canvas_state s stack) def = (s, stack).
Proof.
  intros. unfold save_canvas_state, restore_canvas_state. reflexivity.
Qed.
