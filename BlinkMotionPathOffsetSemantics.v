(* ========================================================================= *)
(*               BlinkMotionPathOffsetSemantics.v                            *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS Motion Path Offset & Direction     *)
(* per W3C Motion Path Module Level 1 §2.                                    *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Definition resolve_offset_distance (dist_val : Z) (is_pct : bool) (total_length : Z) : Z :=
  if is_pct then (dist_val * total_length) / 100
  else dist_val.

Definition clamp_path_distance (s total_length : Z) : Z :=
  Z.max 0 (Z.min total_length s).

Definition modulo_path_distance (s total_length : Z) : Z :=
  if total_length <=? 0 then 0
  else s mod total_length.

Theorem clamp_distance_bounds : forall s L,
  L >= 0 ->
  0 <= clamp_path_distance s L <= L.
Proof.
  intros s L HL.
  unfold clamp_path_distance.
  pose proof (Z.le_max_l 0 (Z.min L s)).
  pose proof (Z.le_min_l L s).
  pose proof (Z.le_max_r 0 (Z.min L s)).
  lia.
Qed.

Theorem clamp_distance_idempotent : forall s L,
  L >= 0 ->
  clamp_path_distance (clamp_path_distance s L) L = clamp_path_distance s L.
Proof.
  intros s L HL.
  pose proof (clamp_distance_bounds s L HL) as [H0 HL_bound].
  unfold clamp_path_distance at 1.
  assert (Hmin: Z.min L (clamp_path_distance s L) = clamp_path_distance s L) by lia.
  rewrite Hmin.
  assert (Hmax: Z.max 0 (clamp_path_distance s L) = clamp_path_distance s L) by lia.
  rewrite Hmax.
  reflexivity.
Qed.

Theorem clamp_distance_monotonic : forall s1 s2 L,
  s1 <= s2 ->
  clamp_path_distance s1 L <= clamp_path_distance s2 L.
Proof.
  intros s1 s2 L Hle.
  unfold clamp_path_distance.
  pose proof (Z.min_le_compat_l s1 s2 L Hle).
  pose proof (Z.max_le_compat_l (Z.min L s1) (Z.min L s2) 0 H).
  exact H0.
Qed.

Theorem modulo_distance_bounds : forall s L,
  L > 0 ->
  0 <= modulo_path_distance s L < L.
Proof.
  intros s L HL.
  unfold modulo_path_distance.
  assert (HL_pos: (L <=? 0) = false) by (apply Z.leb_gt; lia).
  rewrite HL_pos.
  apply Z.mod_pos_bound.
  lia.
Qed.

Theorem pct_distance_monotonic_in_length : forall pct L1 L2,
  pct >= 0 ->
  0 <= L1 <= L2 ->
  resolve_offset_distance pct true L1 <= resolve_offset_distance pct true L2.
Proof.
  intros pct L1 L2 Hpct [HL1_pos HL12].
  unfold resolve_offset_distance.
  apply Z.div_le_mono; [lia |].
  nia.
Qed.
