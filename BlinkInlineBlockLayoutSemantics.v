(* ========================================================================= *)
(*               BlinkInlineBlockLayoutSemantics.v                           *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Inline-Block Layout                     *)
(* per W3C CSS 2.1 §9.2.4 & CSS Inline 3 §3.                                 *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Inductive OverflowStyle : Type :=
  | OvVisible
  | OvHidden
  | OvScroll.

Definition resolve_inline_block_baseline
  (has_lines : bool) (last_line_baseline : Z)
  (overflow : OverflowStyle) (border_box_h : Z) (margin_b : Z) : Z :=
  match overflow with
  | OvVisible =>
      if has_lines then last_line_baseline
      else border_box_h + margin_b
  | _ => border_box_h + margin_b
  end.

Theorem inline_block_fallback_baseline : forall border_box_h mb,
  resolve_inline_block_baseline false 0 OvVisible border_box_h mb = border_box_h + mb.
Proof.
  intros. reflexivity.
Qed.

Theorem inline_block_hidden_overflow_baseline : forall has_lines bl border_box_h mb,
  resolve_inline_block_baseline has_lines bl OvHidden border_box_h mb = border_box_h + mb.
Proof.
  intros. reflexivity.
Qed.

Theorem inline_block_baseline_in_bounds : forall last_line_bl border_box_h mb,
  0 <= last_line_bl <= border_box_h ->
  border_box_h >= 0 ->
  mb >= 0 ->
  0 <= resolve_inline_block_baseline true last_line_bl OvVisible border_box_h mb <= border_box_h + mb.
Proof.
  intros last_line_bl border_box_h mb Hbl Hh Hmb.
  unfold resolve_inline_block_baseline.
  lia.
Qed.
