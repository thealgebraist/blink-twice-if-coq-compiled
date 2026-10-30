Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Token Element Font Style Semantics *)
(** MathML Core §3.2: single-char mi italic vs multi-char normal *)

Inductive FontStyle :=
  | StyleItalic
  | StyleNormal.

Definition resolve_mi_font_style (char_count : Z) : FontStyle :=
  if char_count =? 1 then StyleItalic
  else StyleNormal.

Theorem single_char_mi_is_italic :
  resolve_mi_font_style 1 = StyleItalic.
Proof.
  unfold resolve_mi_font_style; reflexivity.
Qed.

Theorem multi_char_mi_is_normal : forall n,
  1 < n ->
  resolve_mi_font_style n = StyleNormal.
Proof.
  intros n Hgt.
  unfold resolve_mi_font_style.
  assert (n =? 1 = false) by (apply Z.eqb_neq; lia).
  rewrite H; reflexivity.
Qed.
