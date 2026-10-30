(**
  BlinkKeyframeInterpolationSemantics.v
  Formal specification of Chromium Blink CSS keyframe interpolation and timing functions
  derived from third_party/blink/renderer/core/animation/keyframe_effect_model.cc
  and platform/animation/timing_function.cc
  according to W3C CSS Animations Level 1 (§3 Keyframes) & CSS Transitions Level 1 (§3 Timing Functions).
*)

From Stdlib Require Import ZArith.BinInt.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

(** 1. Normalized Interpolation Parameter (Fixed-Point Scale: kScale = 1024 or Denom) *)

Definition kScale : Z := 1024.

Definition compute_local_progress (t o_start o_end : Z) : Z :=
  if o_end <=? o_start then
    if t >=? o_end then kScale else 0
  else
    let num := (t - o_start) * kScale in
    let denom := o_end - o_start in
    Z.max 0 (Z.min kScale (num / denom)).

Theorem local_progress_in_bounds :
  forall t o_start o_end : Z,
    0 <= compute_local_progress t o_start o_end <= kScale.
Proof.
  intros t o_start o_end.
  unfold compute_local_progress, kScale.
  destruct (o_end <=? o_start) eqn:Econd.
  - destruct (t >=? o_end); lia.
  - apply Z.leb_gt in Econd.
    assert (Hden : o_end - o_start > 0) by lia.
    pose proof (Z.le_max_l 0 (Z.min 1024 ((t - o_start) * 1024 / (o_end - o_start)))).
    pose proof (Z.le_max_r 0 (Z.min 1024 ((t - o_start) * 1024 / (o_end - o_start)))).
    pose proof (Z.le_min_l 1024 ((t - o_start) * 1024 / (o_end - o_start))).
    pose proof (Z.le_min_r 1024 ((t - o_start) * 1024 / (o_end - o_start))).
    lia.
Qed.

Theorem local_progress_at_start :
  forall o_start o_end : Z,
    o_start < o_end ->
    compute_local_progress o_start o_start o_end = 0.
Proof.
  intros o_start o_end Hlt.
  unfold compute_local_progress, kScale.
  destruct (o_end <=? o_start) eqn:Econd.
  - apply Z.leb_le in Econd. lia.
  - assert (Hnum : (o_start - o_start) * 1024 = 0) by lia.
    rewrite Hnum.
    assert (Hden : o_end - o_start > 0) by lia.
    rewrite Z.div_0_l by lia.
    simpl. reflexivity.
Qed.

Theorem local_progress_at_end :
  forall o_start o_end : Z,
    o_start < o_end ->
    compute_local_progress o_end o_start o_end = kScale.
Proof.
  intros o_start o_end Hlt.
  unfold compute_local_progress, kScale.
  destruct (o_end <=? o_start) eqn:Econd.
  - apply Z.leb_le in Econd. lia.
  - assert (Hden : o_end - o_start > 0) by lia.
    rewrite Z.mul_comm.
    rewrite Z.div_mul by lia.
    simpl. reflexivity.
Qed.

(** 2. Linear Interpolation (lerp) *)
Definition lerp (v_start v_end alpha : Z) : Z :=
  if alpha <=? 0 then v_start
  else if kScale <=? alpha then v_end
  else v_start + (v_end - v_start) * alpha / kScale.

Theorem lerp_at_zero :
  forall v_start v_end : Z,
    lerp v_start v_end 0 = v_start.
Proof.
  intros v_start v_end.
  unfold lerp.
  simpl. reflexivity.
Qed.

Theorem lerp_at_one :
  forall v_start v_end : Z,
    lerp v_start v_end kScale = v_end.
Proof.
  intros v_start v_end.
  unfold lerp, kScale.
  simpl. reflexivity.
Qed.

Theorem lerp_convexity :
  forall v_start v_end alpha : Z,
    v_start <= v_end ->
    0 <= alpha <= kScale ->
    v_start <= lerp v_start v_end alpha <= v_end.
Proof.
  intros v_start v_end alpha Hord Halpha.
  unfold lerp, kScale in *.
  destruct (alpha <=? 0) eqn:E0.
  - apply Z.leb_le in E0.
    assert (alpha = 0) by lia.
    subst. lia.
  - destruct (1024 <=? alpha) eqn:E1.
    + apply Z.leb_le in E1.
      assert (alpha = 1024) by lia.
      subst. lia.
    + apply Z.leb_gt in E0.
      apply Z.leb_gt in E1.
      assert (Hdiff : 0 <= v_end - v_start) by lia.
      assert (Hprod : 0 <= (v_end - v_start) * alpha).
      { apply Z.mul_nonneg_nonneg; lia. }
      assert (Hdiv_nonneg : 0 <= (v_end - v_start) * alpha / 1024).
      { apply Z.div_pos; lia. }
      assert (Hprod_le : (v_end - v_start) * alpha <= (v_end - v_start) * 1024).
      { apply Z.mul_le_mono_nonneg_l; lia. }
      assert (Hdiv_le : (v_end - v_start) * alpha / 1024 <= (v_end - v_start) * 1024 / 1024).
      { apply Z.div_le_mono; lia. }
      rewrite Z.div_mul in Hdiv_le by lia.
      lia.
Qed.

(** 3. Cubic-Bézier Polynomial Evaluation (Normalized Bernstein Basis) *)
(** With P0 = 0 and P3 = 1024, B(u, p1, p2) with u in [0, 1] *)
Definition cubic_bezier_eval (u p1 p2 : Z) : Z :=
  let u2 := u * u in
  let u3 := u2 * u in
  let inv := kScale - u in
  let inv2 := inv * inv in
  (* Term 0: inv^3 * 0 = 0 *)
  (* Term 1: 3 * inv^2 * u * p1 *)
  let t1 := (3 * inv2 * u / kScale) * p1 / (kScale * kScale) in
  (* Term 2: 3 * inv * u^2 * p2 *)
  let t2 := (3 * inv * u2 / kScale) * p2 / (kScale * kScale) in
  (* Term 3: u^3 * 1024 / 1024^3 = u^3 / 1024^2 *)
  let t3 := u3 / (kScale * kScale) in
  t1 + t2 + t3.

Theorem cubic_bezier_at_zero :
  forall p1 p2 : Z,
    cubic_bezier_eval 0 p1 p2 = 0.
Proof.
  intros p1 p2.
  unfold cubic_bezier_eval, kScale.
  simpl. reflexivity.
Qed.

Theorem cubic_bezier_at_one :
  forall p1 p2 : Z,
    cubic_bezier_eval kScale p1 p2 = kScale.
Proof.
  intros p1 p2.
  unfold cubic_bezier_eval, kScale.
  simpl. reflexivity.
Qed.

(** 4. Keyframe Interval Discovery *)
Record Keyframe := {
  kf_offset : Z;
  kf_value : Z
}.

Fixpoint find_interval (t : Z) (frames : list Keyframe) : option (Keyframe * Keyframe) :=
  match frames with
  | [] => None
  | [_] => None
  | k1 :: ((k2 :: _) as rest) =>
      if (k1.(kf_offset) <=? t) && (t <=? k2.(kf_offset)) then
        Some (k1, k2)
      else
        find_interval t rest
  end.

Theorem find_interval_contains_t :
  forall t frames k1 k2,
    find_interval t frames = Some (k1, k2) ->
    k1.(kf_offset) <= t <= k2.(kf_offset).
Proof.
  intros t frames.
  induction frames as [|kf1 rest IH].
  - intros k1 k2 H; discriminate.
  - intros k1 k2 H.
    destruct rest as [|kf2 rest2].
    + discriminate.
    + simpl in H.
      destruct ((kf1.(kf_offset) <=? t) && (t <=? kf2.(kf_offset))) eqn:Econd.
      * apply andb_true_iff in Econd.
        destruct Econd as [E1 E2].
        apply Z.leb_le in E1.
        apply Z.leb_le in E2.
        injection H as H1 H2.
        subst. lia.
      * apply IH in H.
        exact H.
Qed.
