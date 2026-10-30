Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Variation Selector Branching Semantics *)
(** Unicode Standard §23.4: VS15 (text) vs VS16 (emoji) *)

Inductive GlyphPresentation :=
  | PresentationDefault
  | PresentationText
  | PresentationEmoji.

Definition select_glyph_presentation (vs_codepoint : Z) : GlyphPresentation :=
  if vs_codepoint =? 65038 then PresentationText
  else if vs_codepoint =? 65039 then PresentationEmoji
  else PresentationDefault.

Theorem vs15_selects_text :
  select_glyph_presentation 65038 = PresentationText.
Proof.
  unfold select_glyph_presentation; reflexivity.
Qed.

Theorem vs16_selects_emoji :
  select_glyph_presentation 65039 = PresentationEmoji.
Proof.
  unfold select_glyph_presentation; reflexivity.
Qed.
