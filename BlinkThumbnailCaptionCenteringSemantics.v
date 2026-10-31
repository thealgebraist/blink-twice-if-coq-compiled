(* BlinkThumbnailCaptionCenteringSemantics.v *)
(* Formal semantics of Blink text-align: center inside a thumbnail figure container *)
(* Modeled after Chromium third_party/blink/renderer/core/layout/ng/inline/ng_inline_layout_algorithm.cc *)

Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Record BlinkCaptionBox := mkCaptionBox {
  container_left : Z;
  container_width : Z;
  text_advance_width : Z
}.

Definition compute_centered_text_x (b : BlinkCaptionBox) : Z :=
  container_left b + (container_width b - text_advance_width b) / 2.

Theorem centering_symmetric_bounds :
  forall (b : BlinkCaptionBox),
    0 <= text_advance_width b <= container_width b ->
    container_left b <= compute_centered_text_x b /\
    compute_centered_text_x b + text_advance_width b <= container_left b + container_width b.
Proof.
  intros b [Hw0 Hw1].
  unfold compute_centered_text_x.
  assert (Hrem: 0 <= (container_width b - text_advance_width b) / 2).
  { apply Z.div_pos; lia. }
  split.
  - lia.
  - assert (Hdiv: 2 * ((container_width b - text_advance_width b) / 2) <= container_width b - text_advance_width b).
    { apply Z.mul_div_le. lia. }
    lia.
Qed.

(* Exact Page 2 Diagram Caption parameters:
   Container left = 512, Container width = 256, Text advance = 202
   512 + (256 - 202) / 2 = 512 + 54 / 2 = 512 + 27 = 539 *)
Definition p2_diagram_caption_box : BlinkCaptionBox := mkCaptionBox 512 256 202.

Theorem p2_diagram_caption_x_exact :
  compute_centered_text_x p2_diagram_caption_box = 539.
Proof.
  unfold compute_centered_text_x, p2_diagram_caption_box.
  reflexivity.
Qed.
