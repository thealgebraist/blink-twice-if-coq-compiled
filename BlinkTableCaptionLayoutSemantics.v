(* ========================================================================= *)
(*               BlinkTableCaptionLayoutSemantics.v                          *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Table Caption Placement                *)
(* per W3C CSS 2.1 §17.4.                                                    *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Inductive CaptionSide : Type :=
  | CaptionTop
  | CaptionBottom.

Definition table_caption_y (side : CaptionSide) (table_y grid_h cap_h : Z) : Z :=
  match side with
  | CaptionTop    => table_y
  | CaptionBottom => table_y + grid_h
  end.

Definition table_grid_y (side : CaptionSide) (table_y grid_h cap_h : Z) : Z :=
  match side with
  | CaptionTop    => table_y + cap_h
  | CaptionBottom => table_y
  end.

Definition table_wrapper_total_height (grid_h cap_h : Z) : Z :=
  grid_h + cap_h.

Theorem top_caption_precedes_grid : forall table_y grid_h cap_h,
  cap_h >= 0 ->
  table_caption_y CaptionTop table_y grid_h cap_h + cap_h =
  table_grid_y CaptionTop table_y grid_h cap_h.
Proof.
  intros. unfold table_caption_y, table_grid_y. ring.
Qed.

Theorem bottom_caption_follows_grid : forall table_y grid_h cap_h,
  grid_h >= 0 ->
  table_grid_y CaptionBottom table_y grid_h cap_h + grid_h =
  table_caption_y CaptionBottom table_y grid_h cap_h.
Proof.
  intros. unfold table_grid_y, table_caption_y. ring.
Qed.

Theorem table_wrapper_height_comm : forall grid_h cap_h,
  table_wrapper_total_height grid_h cap_h = table_wrapper_total_height cap_h grid_h.
Proof.
  intros. unfold table_wrapper_total_height. ring.
Qed.
