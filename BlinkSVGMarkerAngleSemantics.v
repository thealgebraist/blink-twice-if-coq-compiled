(* ========================================================================= *)
(*               BlinkSVGMarkerAngleSemantics.v                              *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink SVG Marker Orientation (auto &         *)
(* auto-start-reverse) per W3C SVG 2 §13.                                   *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Definition normalize_angle (a : Z) : Z :=
  a mod 3600.

Definition auto_start_reverse_angle (is_start_marker : bool) (tangent_angle : Z) : Z :=
  if is_start_marker then
    normalize_angle (tangent_angle + 1800)
  else
    normalize_angle tangent_angle.

Definition mid_marker_bisector_angle (a_in a_out : Z) : Z :=
  normalize_angle ((a_in + a_out) / 2).

Theorem normalize_angle_bounds : forall a,
  0 <= normalize_angle a < 3600.
Proof.
  intros a.
  unfold normalize_angle.
  apply Z.mod_pos_bound.
  lia.
Qed.

Theorem normalize_angle_idempotent : forall a,
  normalize_angle (normalize_angle a) = normalize_angle a.
Proof.
  intros a.
  unfold normalize_angle.
  apply Z.mod_mod.
  lia.
Qed.

Theorem normalize_angle_period : forall a,
  normalize_angle (a + 3600) = normalize_angle a.
Proof.
  intros a.
  unfold normalize_angle.
  rewrite (Z.add_mod a 3600 3600); [| lia].
  assert (3600 mod 3600 = 0) by (apply Z_mod_same; lia).
  rewrite H.
  rewrite Z.add_0_r.
  apply Z.mod_mod.
  lia.
Qed.

Theorem auto_start_reverse_twice_involutive : forall a,
  normalize_angle ((a + 1800) + 1800) = normalize_angle a.
Proof.
  intros a.
  assert (Hsum: (a + 1800) + 1800 = a + 3600) by ring.
  rewrite Hsum.
  apply normalize_angle_period.
Qed.

Theorem auto_start_reverse_non_start_identity : forall a,
  auto_start_reverse_angle false a = normalize_angle a.
Proof.
  intros a.
  unfold auto_start_reverse_angle.
  reflexivity.
Qed.

Theorem auto_start_reverse_bounds : forall is_start a,
  0 <= auto_start_reverse_angle is_start a < 3600.
Proof.
  intros is_start a.
  unfold auto_start_reverse_angle.
  destruct is_start; apply normalize_angle_bounds.
Qed.

Theorem mid_marker_bisector_bounds : forall a_in a_out,
  0 <= mid_marker_bisector_angle a_in a_out < 3600.
Proof.
  intros a_in a_out.
  unfold mid_marker_bisector_angle.
  apply normalize_angle_bounds.
Qed.
