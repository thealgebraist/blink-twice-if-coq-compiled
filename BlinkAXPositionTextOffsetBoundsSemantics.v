Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink AXPosition Text Offset Bounds Semantics *)
(** Blink Accessibility §2: text offset within [0, text.length] *)

Definition clamp_ax_text_offset (offset text_len : Z) : Z :=
  Z.max 0 (Z.min text_len offset).

Theorem ax_text_offset_bounded : forall o l,
  0 <= l ->
  0 <= clamp_ax_text_offset o l <= l.
Proof.
  intros o l Hl.
  unfold clamp_ax_text_offset; lia.
Qed.
