Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Table Caption Side Positioning Semantics *)
(** CSS 2.1 §17.4: caption-side top and bottom offsets *)

Definition table_body_offset (is_caption_top : bool) (caption_h : Z) : Z :=
  if is_caption_top then caption_h else 0.

Theorem caption_top_adds_offset : forall caption_h,
  table_body_offset true caption_h = caption_h.
Proof.
  intros caption_h.
  unfold table_body_offset.
  reflexivity.
Qed.

Theorem caption_bottom_zero_offset : forall caption_h,
  table_body_offset false caption_h = 0.
Proof.
  intros caption_h.
  unfold table_body_offset.
  reflexivity.
Qed.
