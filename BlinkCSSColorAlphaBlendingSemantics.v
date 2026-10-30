(* ========================================================================= *)
(*               BlinkCSSColorAlphaBlendingSemantics.v                       *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS Color & Alpha Blending             *)
(* per W3C CSS Color Module Level 4 §12 & Compositing 1 §3.                  *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Definition clamp_channel_255 (c : Z) : Z :=
  Z.max 0 (Z.min 255 c).

Theorem clamp_channel_bounds : forall c,
  0 <= clamp_channel_255 c <= 255.
Proof.
  intros c. unfold clamp_channel_255.
  split; [apply Z.le_max_l |].
  apply Z.max_lub_iff.
  split; [lia | apply Z.le_min_l].
Qed.

Definition blend_channel_u8 (alpha : Z) (src : Z) (dst : Z) : Z :=
  (alpha * src + (255 - alpha) * dst) / 255.

Theorem blend_channel_alpha_0 : forall src dst,
  0 <= dst <= 255 ->
  blend_channel_u8 0 src dst = dst.
Proof.
  intros src dst Hdst.
  unfold blend_channel_u8.
  assert (0 * src + (255 - 0) * dst = dst * 255) by ring.
  rewrite H.
  apply Z.div_mul.
  lia.
Qed.

Theorem blend_channel_alpha_255 : forall src dst,
  0 <= src <= 255 ->
  blend_channel_u8 255 src dst = src.
Proof.
  intros src dst Hsrc.
  unfold blend_channel_u8.
  assert (255 * src + (255 - 255) * dst = src * 255) by ring.
  rewrite H.
  apply Z.div_mul.
  lia.
Qed.

Theorem blend_channel_bounds : forall alpha src dst,
  0 <= alpha <= 255 ->
  0 <= src <= 255 ->
  0 <= dst <= 255 ->
  0 <= blend_channel_u8 alpha src dst <= 255.
Proof.
  intros alpha src dst Ha Hsrc Hdst.
  unfold blend_channel_u8.
  assert (Hterm: alpha * src + (255 - alpha) * dst >= 0) by nia.
  assert (Hupper: alpha * src + (255 - alpha) * dst <= 255 * 255) by nia.
  split.
  - apply Z.div_pos; [lia | lia].
  - apply Z.div_le_upper_bound; [lia | lia].
Qed.
