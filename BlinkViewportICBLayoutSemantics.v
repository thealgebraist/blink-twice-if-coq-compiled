(* ========================================================================= *)
(*               BlinkViewportICBLayoutSemantics.v                           *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Viewport & Initial Containing Block     *)
(* Layout per W3C CSS 2.1 §10.1.                                             *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Definition body_inline_size (viewport_width body_margin : Z) : Z :=
  Z.max 0 (viewport_width - 2 * body_margin).

Definition body_start_offset (body_margin : Z) : Z :=
  body_margin.

Theorem body_inline_size_nonneg : forall vw mb,
  body_inline_size vw mb >= 0.
Proof.
  intros vw mb.
  unfold body_inline_size.
  apply Z.le_ge.
  apply Z.le_max_l.
Qed.

Theorem body_contained_in_viewport : forall vw mb,
  mb >= 0 ->
  vw >= 2 * mb ->
  body_start_offset mb + body_inline_size vw mb <= vw.
Proof.
  intros vw mb Hmb Hvw.
  unfold body_start_offset, body_inline_size.
  assert (Hsub: vw - 2 * mb >= 0) by lia.
  assert (Hmax: Z.max 0 (vw - 2 * mb) = vw - 2 * mb) by lia.
  rewrite Hmax.
  lia.
Qed.

Theorem body_space_conservation : forall vw mb,
  mb >= 0 ->
  vw >= 2 * mb ->
  body_start_offset mb + body_inline_size vw mb + mb = vw.
Proof.
  intros vw mb Hmb Hvw.
  unfold body_start_offset, body_inline_size.
  assert (Hmax: Z.max 0 (vw - 2 * mb) = vw - 2 * mb) by lia.
  rewrite Hmax.
  lia.
Qed.

Theorem body_width_monotonic_in_viewport : forall vw1 vw2 mb,
  vw1 <= vw2 ->
  body_inline_size vw1 mb <= body_inline_size vw2 mb.
Proof.
  intros vw1 vw2 mb Hvw.
  unfold body_inline_size.
  apply Z.max_le_compat_l.
  lia.
Qed.
