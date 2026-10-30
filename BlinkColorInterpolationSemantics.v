(* ========================================================================= *)
(*               BlinkColorInterpolationSemantics.v                          *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS Color Gamut Clamping &             *)
(* Interpolation per W3C CSS Color Module Level 4 §12 & §13.                 *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Definition clamp_channel (v : Z) : Z :=
  Z.max 0 (Z.min 255 v).

Definition lerp_channel (c0 c1 t : Z) : Z :=
  (c0 * (1000 - t) + c1 * t) / 1000.

Record ColorRGBA := {
  rgba_r : Z;
  rgba_g : Z;
  rgba_b : Z;
  rgba_a : Z
}.

Definition valid_color (c : ColorRGBA) : Prop :=
  0 <= rgba_r c <= 255 /\
  0 <= rgba_g c <= 255 /\
  0 <= rgba_b c <= 255 /\
  0 <= rgba_a c <= 255.

Definition lerp_color (c0 c1 : ColorRGBA) (t : Z) : ColorRGBA :=
  {| rgba_r := clamp_channel (lerp_channel (rgba_r c0) (rgba_r c1) t);
     rgba_g := clamp_channel (lerp_channel (rgba_g c0) (rgba_g c1) t);
     rgba_b := clamp_channel (lerp_channel (rgba_b c0) (rgba_b c1) t);
     rgba_a := clamp_channel (lerp_channel (rgba_a c0) (rgba_a c1) t) |}.

Theorem clamp_channel_bounds : forall v,
  0 <= clamp_channel v <= 255.
Proof.
  intros v.
  unfold clamp_channel.
  pose proof (Z.le_max_l 0 (Z.min 255 v)).
  pose proof (Z.le_min_l 255 v).
  pose proof (Z.le_max_r 0 (Z.min 255 v)).
  lia.
Qed.

Theorem clamp_channel_idempotent : forall v,
  clamp_channel (clamp_channel v) = clamp_channel v.
Proof.
  intros v.
  pose proof (clamp_channel_bounds v) as [H0 H255].
  unfold clamp_channel at 1.
  assert (Hmin: Z.min 255 (clamp_channel v) = clamp_channel v) by lia.
  rewrite Hmin.
  assert (Hmax: Z.max 0 (clamp_channel v) = clamp_channel v) by lia.
  rewrite Hmax.
  reflexivity.
Qed.

Theorem lerp_channel_t0 : forall c0 c1,
  lerp_channel c0 c1 0 = c0.
Proof.
  intros c0 c1.
  unfold lerp_channel.
  assert (H: c0 * (1000 - 0) + c1 * 0 = c0 * 1000) by ring.
  rewrite H.
  apply Z.div_mul.
  lia.
Qed.

Theorem lerp_channel_t1000 : forall c0 c1,
  lerp_channel c0 c1 1000 = c1.
Proof.
  intros c0 c1.
  unfold lerp_channel.
  assert (H: c0 * (1000 - 1000) + c1 * 1000 = c1 * 1000) by ring.
  rewrite H.
  apply Z.div_mul.
  lia.
Qed.

Theorem lerp_channel_convex_bounds : forall c0 c1 t,
  0 <= c0 <= 255 ->
  0 <= c1 <= 255 ->
  0 <= t <= 1000 ->
  0 <= lerp_channel c0 c1 t <= 255.
Proof.
  intros c0 c1 t [Hc0_min Hc0_max] [Hc1_min Hc1_max] [Ht_min Ht_max].
  unfold lerp_channel.
  assert (Hnum_pos: c0 * (1000 - t) + c1 * t >= 0) by nia.
  assert (Hnum_max: c0 * (1000 - t) + c1 * t <= 255 * 1000).
  { assert (c0 * (1000 - t) <= 255 * (1000 - t)) by nia.
    assert (c1 * t <= 255 * t) by nia.
    assert (255 * (1000 - t) + 255 * t = 255 * 1000) by ring.
    lia. }
  split.
  - apply Z.div_pos; lia.
  - apply Z.div_le_upper_bound; lia.
Qed.

Theorem lerp_color_valid : forall c0 c1 t,
  valid_color (lerp_color c0 c1 t).
Proof.
  intros c0 c1 t.
  unfold valid_color, lerp_color; cbn.
  repeat split; apply clamp_channel_bounds.
Qed.

Theorem lerp_channel_monotonic : forall c0 c1 t1 t2,
  c0 <= c1 ->
  0 <= t1 <= t2 ->
  t2 <= 1000 ->
  lerp_channel c0 c1 t1 <= lerp_channel c0 c1 t2.
Proof.
  intros c0 c1 t1 t2 Hc Ht1 Ht2.
  unfold lerp_channel.
  apply Z.div_le_mono; [lia |].
  assert (c0 * (1000 - t2) + c1 * t2 - (c0 * (1000 - t1) + c1 * t1) = (c1 - c0) * (t2 - t1)) by ring.
  assert ((c1 - c0) * (t2 - t1) >= 0) by nia.
  lia.
Qed.

