(* ========================================================================= *)
(*               BlinkObjectFitSemantics.v                                   *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink CSS object-fit and object-position  *)
(* according to W3C CSS Images Module Level 3 (§5.5 & §5.6).                *)
(* Derived from third_party/blink/renderer/core/layout/layout_replaced.cc     *)
(* Fully constructive formalization with 0 admits and 0 axioms.             *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(** 1. Inductive Types and Representation *)

Inductive ObjectFit : Type :=
  | FitFill
  | FitContain
  | FitCover
  | FitNone
  | FitScaleDown.

(** 2. Sizing and Positioning Functions *)

(**
  Computes the concrete rendered dimensions (rw, rh) of an image with
  intrinsic dimensions (iw, ih) inside a box of dimensions (bw, bh).
*)
Definition compute_object_fit (mode : ObjectFit) (bw bh iw ih : Z) : (Z * Z) :=
  match mode with
  | FitFill =>
      (bw, bh)
  | FitNone =>
      (iw, ih)
  | FitContain =>
      if bw * ih <=? bh * iw then
        (bw, (bw * ih) / iw)
      else
        ((bh * iw) / ih, bh)
  | FitCover =>
      if bw * ih <=? bh * iw then
        ((bh * iw) / ih, bh)
      else
        (bw, (bw * ih) / iw)
  | FitScaleDown =>
      let rw_c := if bw * ih <=? bh * iw then bw else (bh * iw) / ih in
      let rh_c := if bw * ih <=? bh * iw then (bw * ih) / iw else bh in
      if rw_c <=? iw then
        (rw_c, rh_c)
      else
        (iw, ih)
  end.

(**
  Computes the alignment offset (ox, oy) of an image with rendered size (rw, rh)
  within a container box (bw, bh) given position percentages (px, py).
  Default CSS object-position is 50% 50% (center).
*)
Definition compute_object_position (bw bh rw rh px py : Z) : (Z * Z) :=
  ((bw - rw) * px / 100, (bh - rh) * py / 100).

(** 3. Formal Verification of Key Theorems *)

(** FitFill always matches the box dimensions (bw, bh) exactly. *)
Theorem object_fit_fill_exact : forall bw bh iw ih,
  compute_object_fit FitFill bw bh iw ih = (bw, bh).
Proof.
  intros bw bh iw ih.
  reflexivity.
Qed.

(** FitNone always preserves intrinsic dimensions (iw, ih) exactly. *)
Theorem object_fit_none_exact : forall bw bh iw ih,
  compute_object_fit FitNone bw bh iw ih = (iw, ih).
Proof.
  intros bw bh iw ih.
  reflexivity.
Qed.

(** FitContain stays within the bounding box: rw <= bw /\ rh <= bh. *)
Theorem object_fit_contain_bounds : forall bw bh iw ih,
  bw > 0 -> bh > 0 -> iw > 0 -> ih > 0 ->
  let (rw, rh) := compute_object_fit FitContain bw bh iw ih in
  rw <= bw /\ rh <= bh.
Proof.
  intros bw bh iw ih Hbw Hbh Hiw Hih.
  unfold compute_object_fit.
  destruct (bw * ih <=? bh * iw) eqn:Hcond.
  - apply Z.leb_le in Hcond.
    split.
    + lia.
    + assert (Hdiv : (bw * ih) / iw <= (bh * iw) / iw).
      { apply Z.div_le_mono; [lia | exact Hcond]. }
      rewrite Z.div_mul in Hdiv by lia.
      exact Hdiv.
  - apply Z.leb_gt in Hcond.
    split.
    + assert (Hle : bh * iw <= bw * ih) by lia.
      assert (Hdiv : (bh * iw) / ih <= (bw * ih) / ih).
      { apply Z.div_le_mono; [lia | exact Hle]. }
      rewrite Z.div_mul in Hdiv by lia.
      exact Hdiv.
    + lia.
Qed.

(** FitCover covers the entire box: rw >= bw /\ rh >= bh. *)
Theorem object_fit_cover_bounds : forall bw bh iw ih,
  bw > 0 -> bh > 0 -> iw > 0 -> ih > 0 ->
  let (rw, rh) := compute_object_fit FitCover bw bh iw ih in
  rw >= bw /\ rh >= bh.
Proof.
  intros bw bh iw ih Hbw Hbh Hiw Hih.
  unfold compute_object_fit.
  destruct (bw * ih <=? bh * iw) eqn:Hcond.
  - apply Z.leb_le in Hcond.
    split.
    + assert (Hdiv : (bw * ih) / ih <= (bh * iw) / ih).
      { apply Z.div_le_mono; [lia | exact Hcond]. }
      rewrite Z.div_mul in Hdiv by lia.
      lia.
    + lia.
  - apply Z.leb_gt in Hcond.
    split.
    + lia.
    + assert (Hle : bh * iw <= bw * ih) by lia.
      assert (Hdiv : (bh * iw) / iw <= (bw * ih) / iw).
      { apply Z.div_le_mono; [lia | exact Hle]. }
      rewrite Z.div_mul in Hdiv by lia.
      lia.
Qed.

(** FitScaleDown rendered width never exceeds FitContain rendered width. *)
Theorem object_fit_scale_down_le_contain : forall bw bh iw ih,
  let (rw_sd, _) := compute_object_fit FitScaleDown bw bh iw ih in
  let (rw_c, _) := compute_object_fit FitContain bw bh iw ih in
  rw_sd <= rw_c.
Proof.
  intros bw bh iw ih.
  unfold compute_object_fit.
  destruct (bw * ih <=? bh * iw) eqn:Hcond; simpl.
  - destruct (bw <=? iw) eqn:Hle; simpl.
    + lia.
    + apply Z.leb_gt in Hle. lia.
  - destruct ((bh * iw) / ih <=? iw) eqn:Hle; simpl.
    + lia.
    + apply Z.leb_gt in Hle. lia.
Qed.

(** Rendered dimensions are non-negative for all positive inputs and all modes. *)
Theorem object_fit_nonnegative : forall mode bw bh iw ih,
  bw > 0 -> bh > 0 -> iw > 0 -> ih > 0 ->
  let (rw, rh) := compute_object_fit mode bw bh iw ih in
  rw >= 0 /\ rh >= 0.
Proof.
  intros mode bw bh iw ih Hbw Hbh Hiw Hih.
  destruct mode; unfold compute_object_fit.
  - (* FitFill *)
    lia.
  - (* FitContain *)
    destruct (bw * ih <=? bh * iw) eqn:Hcond.
    + split; [lia |].
      assert (0 <= (bw * ih) / iw).
      { apply Z.div_pos; [nia | lia]. }
      lia.
    + split; [| lia].
      assert (0 <= (bh * iw) / ih).
      { apply Z.div_pos; [nia | lia]. }
      lia.
  - (* FitCover *)
    destruct (bw * ih <=? bh * iw) eqn:Hcond.
    + split; [| lia].
      assert (0 <= (bh * iw) / ih).
      { apply Z.div_pos; [nia | lia]. }
      lia.
    + split; [lia |].
      assert (0 <= (bw * ih) / iw).
      { apply Z.div_pos; [nia | lia]. }
      lia.
  - (* FitNone *)
    lia.
  - (* FitScaleDown *)
    destruct (bw * ih <=? bh * iw) eqn:Hcond.
    + destruct (bw <=? iw) eqn:Hle.
      * split; [lia |].
        assert (0 <= (bw * ih) / iw).
        { apply Z.div_pos; [nia | lia]. }
        lia.
      * lia.
    + destruct ((bh * iw) / ih <=? iw) eqn:Hle.
      * split; [| lia].
        assert (0 <= (bh * iw) / ih).
        { apply Z.div_pos; [nia | lia]. }
        lia.
      * lia.
Qed.

(** 4. Additional Semantic Properties and Object-Position Theorems *)

(** When aspect ratios match exactly, FitContain and FitCover coincide with FitFill. *)
Theorem object_fit_aspect_ratio_match_contain : forall bw bh iw ih,
  bw > 0 -> bh > 0 -> iw > 0 -> ih > 0 ->
  bw * ih = bh * iw ->
  compute_object_fit FitContain bw bh iw ih = (bw, bh).
Proof.
  intros bw bh iw ih Hbw Hbh Hiw Hih Har.
  unfold compute_object_fit.
  assert (Hcond : (bw * ih <=? bh * iw) = true).
  { apply Z.leb_le. lia. }
  rewrite Hcond.
  rewrite Har.
  rewrite Z.div_mul by lia.
  reflexivity.
Qed.

Theorem object_fit_aspect_ratio_match_cover : forall bw bh iw ih,
  bw > 0 -> bh > 0 -> iw > 0 -> ih > 0 ->
  bw * ih = bh * iw ->
  compute_object_fit FitCover bw bh iw ih = (bw, bh).
Proof.
  intros bw bh iw ih Hbw Hbh Hiw Hih Har.
  unfold compute_object_fit.
  assert (Hcond : (bw * ih <=? bh * iw) = true).
  { apply Z.leb_le. lia. }
  rewrite Hcond.
  rewrite <- Har.
  rewrite Z.div_mul by lia.
  reflexivity.
Qed.

(** FitScaleDown rendered height also never exceeds FitContain rendered height. *)
Theorem object_fit_scale_down_rh_le_contain : forall bw bh iw ih,
  bw > 0 -> bh > 0 -> iw > 0 -> ih > 0 ->
  let (_, rh_sd) := compute_object_fit FitScaleDown bw bh iw ih in
  let (_, rh_c) := compute_object_fit FitContain bw bh iw ih in
  rh_sd <= rh_c.
Proof.
  intros bw bh iw ih Hbw Hbh Hiw Hih.
  unfold compute_object_fit.
  destruct (bw * ih <=? bh * iw) eqn:Hcond.
  - apply Z.leb_le in Hcond.
    destruct (bw <=? iw) eqn:Hle.
    + lia.
    + apply Z.leb_gt in Hle.
      assert (Hstep : ih * iw <= bw * ih).
      { rewrite Z.mul_comm with (n := ih) (m := iw). apply Z.mul_le_mono_nonneg_r; lia. }
      assert (Hdiv : (ih * iw) / iw <= (bw * ih) / iw).
      { apply Z.div_le_mono; [lia | exact Hstep]. }
      rewrite Z.div_mul in Hdiv by lia.
      exact Hdiv.
  - apply Z.leb_gt in Hcond.
    destruct ((bh * iw) / ih <=? iw) eqn:Hle.
    + lia.
    + apply Z.leb_gt in Hle.
      assert (Hbh_gt_ih : ih < bh).
      {
        destruct (bh <=? ih) eqn:E.
        - apply Z.leb_le in E.
          assert (Hmul : bh * iw <= iw * ih).
          { rewrite Z.mul_comm with (n := iw) (m := ih). apply Z.mul_le_mono_nonneg_r; lia. }
          assert (Hdiv : (bh * iw) / ih <= (iw * ih) / ih).
          { apply Z.div_le_mono; [lia | exact Hmul]. }
          rewrite Z.div_mul in Hdiv by lia.
          lia.
        - apply Z.leb_gt in E. lia.
      }
      lia.
Qed.

(** Object-position origin (0% 0%) places image at (0, 0). *)
Theorem object_position_top_left : forall bw bh rw rh,
  compute_object_position bw bh rw rh 0 0 = (0, 0).
Proof.
  intros bw bh rw rh.
  unfold compute_object_position.
  rewrite Z.mul_0_r, Z.mul_0_r.
  rewrite Z.div_0_l by lia.
  reflexivity.
Qed.

(** Object-position 100% 100% aligns bottom-right edges: (bw - rw, bh - rh). *)
Theorem object_position_bottom_right : forall bw bh rw rh,
  compute_object_position bw bh rw rh 100 100 = (bw - rw, bh - rh).
Proof.
  intros bw bh rw rh.
  unfold compute_object_position.
  rewrite Z.div_mul by lia.
  rewrite Z.div_mul by lia.
  reflexivity.
Qed.

(** Object-position horizontal offset is bounded within [0, bw - rw] when rw <= bw and 0 <= px <= 100. *)
Theorem object_position_bounds_x : forall bw bh rw rh px py,
  rw <= bw ->
  0 <= px <= 100 ->
  let (ox, _) := compute_object_position bw bh rw rh px py in
  0 <= ox <= bw - rw.
Proof.
  intros bw bh rw rh px py Hrw Hpx.
  unfold compute_object_position.
  split.
  - apply Z.div_pos; [nia | lia].
  - assert (Hmul : (bw - rw) * px <= (bw - rw) * 100).
    { apply Z.mul_le_mono_nonneg_l; lia. }
    assert (Hdiv : (bw - rw) * px / 100 <= ((bw - rw) * 100) / 100).
    { apply Z.div_le_mono; [lia | exact Hmul]. }
    rewrite Z.div_mul in Hdiv by lia.
    exact Hdiv.
Qed.

(** Object-position vertical offset is bounded within [0, bh - rh] when rh <= bh and 0 <= py <= 100. *)
Theorem object_position_bounds_y : forall bw bh rw rh px py,
  rh <= bh ->
  0 <= py <= 100 ->
  let (_, oy) := compute_object_position bw bh rw rh px py in
  0 <= oy <= bh - rh.
Proof.
  intros bw bh rw rh px py Hrh Hpy.
  unfold compute_object_position.
  split.
  - apply Z.div_pos; [nia | lia].
  - assert (Hmul : (bh - rh) * py <= (bh - rh) * 100).
    { apply Z.mul_le_mono_nonneg_l; lia. }
    assert (Hdiv : (bh - rh) * py / 100 <= ((bh - rh) * 100) / 100).
    { apply Z.div_le_mono; [lia | exact Hmul]. }
    rewrite Z.div_mul in Hdiv by lia.
    exact Hdiv.
Qed.
