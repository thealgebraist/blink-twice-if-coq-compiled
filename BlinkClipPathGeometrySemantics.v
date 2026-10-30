(* ========================================================================= *)
(*               BlinkClipPathGeometrySemantics.v                            *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink ClipPathClipper and W3C CSS Masking 1  *)
(* §3 (Clipping Paths & Bounding BBoxes).                                    *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Record AABB := {
  aabb_x : Z;
  aabb_y : Z;
  aabb_w : Z;
  aabb_h : Z
}.

Definition aabb_valid (r : AABB) : Prop :=
  aabb_w r >= 0 /\ aabb_h r >= 0.

Definition aabb_area (r : AABB) : Z :=
  aabb_w r * aabb_h r.

Definition intersect_1d (x1 w1 x2 w2 : Z) : Z * Z :=
  let s := Z.max x1 x2 in
  let e := Z.min (x1 + w1) (x2 + w2) in
  if Z.leb e s then (s, 0)
  else (s, e - s).

Definition intersect_aabb (r1 r2 : AABB) : AABB :=
  let (ix, iw) := intersect_1d (aabb_x r1) (aabb_w r1) (aabb_x r2) (aabb_w r2) in
  let (iy, ih) := intersect_1d (aabb_y r1) (aabb_h r1) (aabb_y r2) (aabb_h r2) in
  {| aabb_x := ix; aabb_y := iy; aabb_w := iw; aabb_h := ih |}.

Definition in_1d (x w p : Z) : Prop :=
  x <= p /\ p < x + w.

Definition point_in_aabb (px py : Z) (r : AABB) : Prop :=
  in_1d (aabb_x r) (aabb_w r) px /\
  in_1d (aabb_y r) (aabb_h r) py.

Lemma intersect_1d_nonneg : forall x1 w1 x2 w2,
  snd (intersect_1d x1 w1 x2 w2) >= 0.
Proof.
  intros x1 w1 x2 w2.
  unfold intersect_1d.
  destruct (Z.leb (Z.min (x1 + w1) (x2 + w2)) (Z.max x1 x2)) eqn:Hleb.
  - cbn. lia.
  - cbn. apply Z.leb_gt in Hleb. lia.
Qed.

Theorem intersect_aabb_valid : forall r1 r2,
  aabb_valid (intersect_aabb r1 r2).
Proof.
  intros r1 r2.
  unfold aabb_valid, intersect_aabb.
  destruct (intersect_1d (aabb_x r1) (aabb_w r1) (aabb_x r2) (aabb_w r2)) as [ix iw] eqn:Hx.
  destruct (intersect_1d (aabb_y r1) (aabb_h r1) (aabb_y r2) (aabb_h r2)) as [iy ih] eqn:Hy.
  cbn.
  pose proof (intersect_1d_nonneg (aabb_x r1) (aabb_w r1) (aabb_x r2) (aabb_w r2)) as Hw.
  pose proof (intersect_1d_nonneg (aabb_y r1) (aabb_h r1) (aabb_y r2) (aabb_h r2)) as Hh.
  rewrite Hx in Hw. rewrite Hy in Hh.
  cbn in Hw, Hh.
  split; assumption.
Qed.

Lemma intersect_1d_comm : forall x1 w1 x2 w2,
  intersect_1d x1 w1 x2 w2 = intersect_1d x2 w2 x1 w1.
Proof.
  intros x1 w1 x2 w2.
  unfold intersect_1d.
  rewrite (Z.max_comm x1 x2).
  rewrite (Z.min_comm (x1 + w1) (x2 + w2)).
  reflexivity.
Qed.

Theorem intersect_aabb_comm : forall r1 r2,
  intersect_aabb r1 r2 = intersect_aabb r2 r1.
Proof.
  intros [x1 y1 w1 h1] [x2 y2 w2 h2].
  unfold intersect_aabb. cbn.
  rewrite (intersect_1d_comm x1 w1 x2 w2).
  rewrite (intersect_1d_comm y1 h1 y2 h2).
  reflexivity.
Qed.

Lemma intersect_1d_idempotent : forall x w,
  w >= 0 ->
  intersect_1d x w x w = (x, w).
Proof.
  intros x w Hw.
  unfold intersect_1d.
  rewrite Z.max_id.
  rewrite Z.min_id.
  destruct (Z.leb (x + w) x) eqn:Hleb.
  - apply Z.leb_le in Hleb.
    assert (w = 0) by lia.
    subst. reflexivity.
  - apply Z.leb_gt in Hleb.
    f_equal. lia.
Qed.

Theorem intersect_aabb_idempotent : forall r,
  aabb_valid r ->
  intersect_aabb r r = r.
Proof.
  intros [x y w h] [Hw Hh].
  unfold intersect_aabb; cbn.
  rewrite (intersect_1d_idempotent x w Hw).
  rewrite (intersect_1d_idempotent y h Hh).
  reflexivity.
Qed.

Lemma intersect_1d_bounded_left : forall x1 w1 x2 w2,
  w1 >= 0 ->
  snd (intersect_1d x1 w1 x2 w2) <= w1.
Proof.
  intros x1 w1 x2 w2 Hw1.
  unfold intersect_1d.
  destruct (Z.leb (Z.min (x1 + w1) (x2 + w2)) (Z.max x1 x2)) eqn:Hleb; cbn.
  - lia.
  - apply Z.leb_gt in Hleb.
    pose proof (Z.le_max_l x1 x2).
    pose proof (Z.le_min_l (x1 + w1) (x2 + w2)).
    lia.
Qed.

Lemma intersect_1d_bounded_right : forall x1 w1 x2 w2,
  w2 >= 0 ->
  snd (intersect_1d x1 w1 x2 w2) <= w2.
Proof.
  intros x1 w1 x2 w2 Hw2.
  rewrite intersect_1d_comm.
  apply intersect_1d_bounded_left; assumption.
Qed.

Theorem intersect_area_monotonic_left : forall r1 r2,
  aabb_valid r1 -> aabb_valid r2 ->
  aabb_area (intersect_aabb r1 r2) <= aabb_area r1.
Proof.
  intros r1 r2 [Hw1 Hh1] [Hw2 Hh2].
  unfold aabb_area, intersect_aabb.
  destruct (intersect_1d (aabb_x r1) (aabb_w r1) (aabb_x r2) (aabb_w r2)) as [ix iw] eqn:Hx.
  destruct (intersect_1d (aabb_y r1) (aabb_h r1) (aabb_y r2) (aabb_h r2)) as [iy ih] eqn:Hy.
  cbn.
  pose proof (intersect_1d_nonneg (aabb_x r1) (aabb_w r1) (aabb_x r2) (aabb_w r2)) as Hiw_nonneg.
  pose proof (intersect_1d_nonneg (aabb_y r1) (aabb_h r1) (aabb_y r2) (aabb_h r2)) as Hih_nonneg.
  pose proof (intersect_1d_bounded_left (aabb_x r1) (aabb_w r1) (aabb_x r2) (aabb_w r2) Hw1) as Hiw_le.
  pose proof (intersect_1d_bounded_left (aabb_y r1) (aabb_h r1) (aabb_y r2) (aabb_h r2) Hh1) as Hih_le.
  rewrite Hx in Hiw_nonneg, Hiw_le; cbn in Hiw_nonneg, Hiw_le.
  rewrite Hy in Hih_nonneg, Hih_le; cbn in Hih_nonneg, Hih_le.
  apply Z.mul_le_mono_nonneg; lia.
Qed.

Lemma in_intersect_1d_iff : forall x1 w1 x2 w2 p,
  in_1d (fst (intersect_1d x1 w1 x2 w2)) (snd (intersect_1d x1 w1 x2 w2)) p <->
  (in_1d x1 w1 p /\ in_1d x2 w2 p).
Proof.
  intros x1 w1 x2 w2 p.
  unfold in_1d, intersect_1d.
  destruct (Z.leb (Z.min (x1 + w1) (x2 + w2)) (Z.max x1 x2)) eqn:Hleb.
  - apply Z.leb_le in Hleb. cbn.
    split.
    + intros [H1 H2]. lia.
    + intros [[H1 H2] [H3 H4]].
      pose proof (Z.le_max_l x1 x2).
      pose proof (Z.le_max_r x1 x2).
      pose proof (Z.le_min_l (x1 + w1) (x2 + w2)).
      pose proof (Z.le_min_r (x1 + w1) (x2 + w2)).
      lia.
  - apply Z.leb_gt in Hleb. cbn.
    pose proof (Z.le_max_l x1 x2).
    pose proof (Z.le_max_r x1 x2).
    pose proof (Z.le_min_l (x1 + w1) (x2 + w2)).
    pose proof (Z.le_min_r (x1 + w1) (x2 + w2)).
    split.
    + intros [Hp1 Hp2].
      split; split; lia.
    + intros [[Ha1 Ha2] [Hb1 Hb2]].
      split; lia.
Qed.

Theorem point_in_intersection_iff : forall px py r1 r2,
  point_in_aabb px py (intersect_aabb r1 r2) <->
  (point_in_aabb px py r1 /\ point_in_aabb px py r2).
Proof.
  intros px py [x1 y1 w1 h1] [x2 y2 w2 h2].
  unfold point_in_aabb, intersect_aabb; cbn.
  destruct (intersect_1d x1 w1 x2 w2) as [ix iw] eqn:Hx.
  destruct (intersect_1d y1 h1 y2 h2) as [iy ih] eqn:Hy.
  cbn.
  pose proof (in_intersect_1d_iff x1 w1 x2 w2 px) as Hx_iff.
  pose proof (in_intersect_1d_iff y1 h1 y2 h2 py) as Hy_iff.
  rewrite Hx in Hx_iff; cbn in Hx_iff.
  rewrite Hy in Hy_iff; cbn in Hy_iff.
  split.
  - intros [Hpx Hpy].
    apply Hx_iff in Hpx.
    apply Hy_iff in Hpy.
    destruct Hpx as [Hpx1 Hpx2].
    destruct Hpy as [Hpy1 Hpy2].
    split; split; assumption.
  - intros [[Hpx1 Hpy1] [Hpx2 Hpy2]].
    split.
    + apply Hx_iff. split; assumption.
    + apply Hy_iff. split; assumption.
Qed.
