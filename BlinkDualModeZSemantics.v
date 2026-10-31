From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(** * Blink Dual-Mode Coordinate Semantics: Spec Mode vs Chromium Mode
    This theory formalizes coordinate arithmetic under two execution semantics:
    1. SpecMode: Pure mathematical integers (Z, scale = 1), representing
       the idealized W3C CSS specification standard.
    2. ChromiumMode: 26.6 fixed-point LayoutUnits (Z, scale = 64), representing
       Blink's internal layout coordinate engine.
*)

Inductive ZLayoutMode : Type :=
  | SpecMode : ZLayoutMode
  | ChromiumMode : ZLayoutMode.

Definition z_scale (mode : ZLayoutMode) : Z :=
  match mode with
  | SpecMode => 1
  | ChromiumMode => 64
  end.

Lemma z_scale_pos : forall m : ZLayoutMode, z_scale m > 0.
Proof.
  destruct m; simpl; lia.
Qed.

(** Conversion from integer CSS pixels to internal representation *)
Definition z_from_pixel (mode : ZLayoutMode) (px : Z) : Z :=
  px * z_scale mode.

(** Conversion from internal representation back to device pixels (snapping) *)
Definition z_to_device_pixel (mode : ZLayoutMode) (val : Z) : Z :=
  match mode with
  | SpecMode => val
  | ChromiumMode => (val + 32) / 64  (* Blink LayoutUnit::Round() *)
  end.

Definition z_floor_device_pixel (mode : ZLayoutMode) (val : Z) : Z :=
  match mode with
  | SpecMode => val
  | ChromiumMode => val / 64          (* Blink LayoutUnit::Floor() *)
  end.

Definition z_ceil_device_pixel (mode : ZLayoutMode) (val : Z) : Z :=
  match mode with
  | SpecMode => val
  | ChromiumMode => (val + 63) / 64  (* Blink LayoutUnit::Ceil() *)
  end.

(** Mode-parameterized addition & subtraction *)
Definition z_add (mode : ZLayoutMode) (a b : Z) : Z := a + b.
Definition z_sub (mode : ZLayoutMode) (a b : Z) : Z := a - b.

(** Mode-parameterized percentage resolution *)
Definition z_mul_pct (mode : ZLayoutMode) (avail : Z) (pct : Z) : Z :=
  (avail * pct) / 100.

(** Mode-parameterized cumulative partition boundary for column allocation *)
Definition z_partition_boundary (mode : ZLayoutMode) (total_w : Z) (total_cols : Z) (col_idx : Z) : Z :=
  match mode with
  | SpecMode => (total_w * col_idx) / total_cols
  | ChromiumMode =>
      let raw_total := total_w * 64 in
      let raw_col := (raw_total * col_idx) / total_cols in
      (raw_col + 32) / 64
  end.

(** THEOREM 1: Spec Mode Identity *)
Theorem spec_mode_from_to_pixel_id :
  forall p : Z, z_to_device_pixel SpecMode (z_from_pixel SpecMode p) = p.
Proof.
  intro p.
  unfold z_to_device_pixel, z_from_pixel, z_scale.
  lia.
Qed.

(** THEOREM 2: Chromium Mode Identity *)
Theorem chromium_mode_from_to_pixel_id :
  forall p : Z, z_to_device_pixel ChromiumMode (z_from_pixel ChromiumMode p) = p.
Proof.
  intro p.
  unfold z_to_device_pixel, z_from_pixel, z_scale.
  rewrite Z.mul_comm.
  symmetry.
  apply Z.div_unique with (r := 32); [lia | ring].
Qed.

(** THEOREM 3: Floor and Ceil Identities in Chromium Mode *)
Theorem chromium_mode_floor_ceil_id :
  forall p : Z,
    z_floor_device_pixel ChromiumMode (z_from_pixel ChromiumMode p) = p /\
    z_ceil_device_pixel ChromiumMode (z_from_pixel ChromiumMode p) = p.
Proof.
  intro p.
  unfold z_floor_device_pixel, z_ceil_device_pixel, z_from_pixel, z_scale.
  rewrite Z.mul_comm.
  split.
  - symmetry. apply Z.div_unique with (r := 0); [lia | ring].
  - symmetry. apply Z.div_unique with (r := 63); [lia | ring].
Qed.

(** THEOREM 4: Additive Homomorphism for Integer Pixels *)
Theorem dual_mode_add_homomorphism :
  forall (m : ZLayoutMode) (p1 p2 : Z),
    z_to_device_pixel m (z_add m (z_from_pixel m p1) (z_from_pixel m p2)) = p1 + p2.
Proof.
  intros m p1 p2.
  destruct m.
  - unfold z_to_device_pixel, z_add, z_from_pixel, z_scale. lia.
  - unfold z_to_device_pixel, z_add, z_from_pixel, z_scale.
    assert (Hdist: p1 * 64 + p2 * 64 = (p1 + p2) * 64) by ring.
    rewrite Hdist.
    symmetry.
    apply Z.div_unique with (r := 32); [lia | ring].
Qed.

(** THEOREM 5: Subpixel Refinement Bound (Floor vs Ceil Snapping) *)
Theorem chromium_snap_floor_ceil_bound :
  forall val : Z,
    0 <= z_ceil_device_pixel ChromiumMode val - z_floor_device_pixel ChromiumMode val <= 1.
Proof.
  intro val.
  unfold z_ceil_device_pixel, z_floor_device_pixel.
  set (q := val / 64).
  set (r := val mod 64).
  assert (Hmod: val = 64 * q + r) by (apply Z.div_mod; lia).
  assert (Hrem: 0 <= r < 64) by (apply Z.mod_pos_bound; lia).
  assert (Hval: val + 63 = 64 * q + (r + 63)) by lia.
  rewrite Hval.
  assert (Hdiv1: (64 * q + (r + 63)) / 64 = q + (r + 63) / 64).
  {
    rewrite Z.add_comm with (n := 64 * q).
    rewrite Z.mul_comm with (n := 64) (m := q).
    rewrite Z.div_add by lia.
    lia.
  }
  rewrite Hdiv1.
  assert (Hdelta: q + (r + 63) / 64 - q = (r + 63) / 64) by ring.
  rewrite Hdelta.
  assert (Hr63: (r + 63) / 64 = 0 \/ (r + 63) / 64 = 1).
  {
    destruct (Z_le_gt_dec (r + 63) 63).
    - left. apply Z.div_small; lia.
    - right. symmetry. apply Z.div_unique with (r := r - 1); [lia | ring].
  }
  destruct Hr63 as [H0 | H1]; rewrite H0 || rewrite H1; lia.
Qed.

(** THEOREM 6: Partition Totality Conservation (No gaps/overlaps at endpoints) *)
Theorem chromium_partition_totality :
  forall (w : Z) (cols : Z),
    cols > 0 ->
    w >= 0 ->
    z_partition_boundary ChromiumMode w cols 0 = 0 /\
    z_partition_boundary ChromiumMode w cols cols = w.
Proof.
  intros w cols Hcols Hw.
  unfold z_partition_boundary.
  split.
  - assert (Hzero: (w * 64 * 0) / cols = 0).
    {
      rewrite Z.mul_0_r.
      apply Z.div_0_l.
      lia.
    }
    rewrite Hzero.
    symmetry.
    apply Z.div_unique with (r := 32); [lia | ring].
  - assert (Hself: (w * 64 * cols) / cols = w * 64).
    {
      apply Z.div_mul; lia.
    }
    rewrite Hself.
    symmetry.
    apply Z.div_unique with (r := 32); [lia | ring].
Qed.

(** THEOREM 7: Snapping Monotonicity *)
Theorem chromium_snap_monotonic :
  forall a b : Z,
    a <= b ->
    z_to_device_pixel ChromiumMode a <= z_to_device_pixel ChromiumMode b.
Proof.
  intros a b Hab.
  unfold z_to_device_pixel.
  apply Z.div_le_mono; lia.
Qed.

(** THEOREM 8: Dual Mode Percentage Difference is Bounded by 1px *)
Theorem dual_mode_percentage_resolution_bound :
  forall (w : Z) (pct : Z),
    w >= 0 ->
    0 <= pct <= 100 ->
    -1 <= z_to_device_pixel ChromiumMode (z_mul_pct ChromiumMode (z_from_pixel ChromiumMode w) pct) -
          z_mul_pct SpecMode w pct <= 1.
Proof.
  intros w pct Hw Hpct.
  unfold z_to_device_pixel, z_mul_pct, z_from_pixel, z_scale.
  assert (Hw64: w * 64 * pct = (w * pct) * 64) by ring.
  rewrite Hw64.
  set (X := w * pct).
  assert (HX: X >= 0) by lia.
  set (Q := X / 100).
  set (R := X mod 100).
  assert (HEq: X = 100 * Q + R) by (apply Z.div_mod; lia).
  assert (HRem: 0 <= R < 100) by (apply Z.mod_pos_bound; lia).
  assert (Hmul: X * 64 = 100 * (64 * Q) + 64 * R) by (rewrite HEq; ring).
  rewrite Hmul.
  assert (Hdiv100: (100 * (64 * Q) + 64 * R) / 100 = 64 * Q + (64 * R) / 100).
  {
    rewrite Z.add_comm with (n := 100 * (64 * Q)).
    rewrite Z.mul_comm with (n := 100) (m := 64 * Q).
    rewrite Z.div_add by lia.
    lia.
  }
  rewrite Hdiv100.
  assert (Hadd32: 64 * Q + (64 * R) / 100 + 32 = 64 * Q + ((64 * R) / 100 + 32)) by ring.
  rewrite Hadd32.
  assert (Hdiv64: (64 * Q + ((64 * R) / 100 + 32)) / 64 = Q + ((64 * R) / 100 + 32) / 64).
  {
    rewrite Z.add_comm with (n := 64 * Q).
    rewrite Z.mul_comm with (n := 64) (m := Q).
    rewrite Z.div_add by lia.
    lia.
  }
  rewrite Hdiv64.
  assert (Hdelta: Q + ((64 * R) / 100 + 32) / 64 - Q = ((64 * R) / 100 + 32) / 64) by ring.
  rewrite Hdelta.
  assert (HRbound: 0 <= (64 * R) / 100 <= 63).
  {
    split.
    - apply Z.div_pos; lia.
    - assert (Hle: 64 * R <= 64 * 99) by lia.
      assert (H6336: 64 * 99 = 6336) by reflexivity.
      assert (Hdiv63: 6336 / 100 = 63) by reflexivity.
      rewrite H6336 in Hle.
      apply Z.div_le_mono with (c := 100) in Hle; [| lia].
      rewrite Hdiv63 in Hle.
      exact Hle.
  }
  assert (Htot: 32 <= (64 * R) / 100 + 32 <= 95) by lia.
  assert (Hfinal: ((64 * R) / 100 + 32) / 64 = 0 \/ ((64 * R) / 100 + 32) / 64 = 1).
  {
    destruct (Z_le_gt_dec ((64 * R) / 100 + 32) 63).
    - left. apply Z.div_small; lia.
    - right. symmetry. apply Z.div_unique with (r := ((64 * R) / 100 + 32) - 64); [lia | ring].
  }
  destruct Hfinal as [H0 | H1]; rewrite H0 || rewrite H1; lia.
Qed.
