(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record InlineSpanBox := mkInlineSpanBox {
  inlinespanbox_glyph_w : Z;
  inlinespanbox_pad_l : Z;
  inlinespanbox_pad_r : Z;
  inlinespanbox_border_w : Z
}.

Definition inline_span_outer_advance (glyph_w : Z) (pad_l : Z) (pad_r : Z) (border_w : Z) : Z :=
  glyph_w + Z.max 0 pad_l + Z.max 0 pad_r + 2 * Z.max 0 border_w.

Theorem inline_span_outer_advance_ge_glyph_w :
  forall (glyph_w pad_l pad_r border_w : Z), glyph_w <= inline_span_outer_advance glyph_w pad_l pad_r border_w.
Proof.
  intros. unfold inline_span_outer_advance. lia.
Qed.
