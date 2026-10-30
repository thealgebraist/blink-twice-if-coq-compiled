(* ========================================================================= *)
(*               BlinkSVGFilterSubregionSemantics.v                          *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink SVG Filter Primitive Subregion         *)
(* Clipping per W3C Filter Effects Module Level 1 §7.                       *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Record FilterRect := {
  fr_x : Z;
  fr_y : Z;
  fr_w : Z;
  fr_h : Z
}.

Definition filter_rect_valid (r : FilterRect) : Prop :=
  fr_w r >= 0 /\ fr_h r >= 0.

Definition dim_contains (x w p : Z) : Prop :=
  x <= p /\ p < x + w.

Definition rect_contains_point (px py : Z) (r : FilterRect) : Prop :=
  dim_contains (fr_x r) (fr_w r) px /\
  dim_contains (fr_y r) (fr_h r) py.

Definition intersect_dim (x1 w1 x2 w2 : Z) : Z * Z :=
  let s := Z.max x1 x2 in
  let e := Z.min (x1 + w1) (x2 + w2) in
  if Z.leb e s then (s, 0)
  else (s, e - s).

Definition intersect_filter_rect (r1 r2 : FilterRect) : FilterRect :=
  let (ix, iw) := intersect_dim (fr_x r1) (fr_w r1) (fr_x r2) (fr_w r2) in
  let (iy, ih) := intersect_dim (fr_y r1) (fr_h r1) (fr_y r2) (fr_h r2) in
  {| fr_x := ix; fr_y := iy; fr_w := iw; fr_h := ih |}.

Definition resolve_primitive_subregion (filter_region : FilterRect) (primitive_spec : FilterRect) : FilterRect :=
  intersect_filter_rect filter_region primitive_spec.

Definition resolve_primitive_output (filter_region : FilterRect) (primitive_subregion : FilterRect) (natural_effect : FilterRect) : FilterRect :=
  let clipped_subregion := resolve_primitive_subregion filter_region primitive_subregion in
  intersect_filter_rect natural_effect clipped_subregion.

Lemma intersect_dim_nonneg : forall x1 w1 x2 w2,
  snd (intersect_dim x1 w1 x2 w2) >= 0.
Proof.
  intros x1 w1 x2 w2.
  unfold intersect_dim.
  destruct (Z.leb (Z.min (x1 + w1) (x2 + w2)) (Z.max x1 x2)) eqn:Hleb; cbn.
  - lia.
  - apply Z.leb_gt in Hleb. lia.
Qed.

Theorem intersect_filter_rect_valid : forall r1 r2,
  filter_rect_valid (intersect_filter_rect r1 r2).
Proof.
  intros r1 r2.
  unfold filter_rect_valid, intersect_filter_rect.
  destruct (intersect_dim (fr_x r1) (fr_w r1) (fr_x r2) (fr_w r2)) as [ix iw] eqn:Hx.
  destruct (intersect_dim (fr_y r1) (fr_h r1) (fr_y r2) (fr_h r2)) as [iy ih] eqn:Hy.
  cbn.
  pose proof (intersect_dim_nonneg (fr_x r1) (fr_w r1) (fr_x r2) (fr_w r2)) as Hw.
  pose proof (intersect_dim_nonneg (fr_y r1) (fr_h r1) (fr_y r2) (fr_h r2)) as Hh.
  rewrite Hx in Hw. rewrite Hy in Hh.
  cbn in Hw, Hh.
  split; assumption.
Qed.

Lemma intersect_dim_in_iff : forall x1 w1 x2 w2 p,
  dim_contains (fst (intersect_dim x1 w1 x2 w2)) (snd (intersect_dim x1 w1 x2 w2)) p <->
  (dim_contains x1 w1 p /\ dim_contains x2 w2 p).
Proof.
  intros x1 w1 x2 w2 p.
  unfold dim_contains, intersect_dim.
  destruct (Z.leb (Z.min (x1 + w1) (x2 + w2)) (Z.max x1 x2)) eqn:Hleb; cbn.
  - apply Z.leb_le in Hleb.
    split.
    + intros [H1 H2]. lia.
    + intros [[H1 H2] [H3 H4]].
      pose proof (Z.le_max_l x1 x2).
      pose proof (Z.le_max_r x1 x2).
      pose proof (Z.le_min_l (x1 + w1) (x2 + w2)).
      pose proof (Z.le_min_r (x1 + w1) (x2 + w2)).
      lia.
  - apply Z.leb_gt in Hleb.
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

Theorem point_in_intersect_iff : forall px py r1 r2,
  rect_contains_point px py (intersect_filter_rect r1 r2) <->
  (rect_contains_point px py r1 /\ rect_contains_point px py r2).
Proof.
  intros px py [x1 y1 w1 h1] [x2 y2 w2 h2].
  unfold rect_contains_point, intersect_filter_rect; cbn.
  destruct (intersect_dim x1 w1 x2 w2) as [ix iw] eqn:Hx.
  destruct (intersect_dim y1 h1 y2 h2) as [iy ih] eqn:Hy.
  cbn.
  pose proof (intersect_dim_in_iff x1 w1 x2 w2 px) as Hx_iff.
  pose proof (intersect_dim_in_iff y1 h1 y2 h2 py) as Hy_iff.
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

Theorem output_contained_in_filter_region : forall px py f_reg p_sub nat_eff,
  rect_contains_point px py (resolve_primitive_output f_reg p_sub nat_eff) ->
  rect_contains_point px py f_reg.
Proof.
  intros px py f_reg p_sub nat_eff Hpt.
  unfold resolve_primitive_output in Hpt.
  apply point_in_intersect_iff in Hpt.
  destruct Hpt as [Hnat Hsub].
  unfold resolve_primitive_subregion in Hsub.
  apply point_in_intersect_iff in Hsub.
  destruct Hsub as [Hfreg Hpsub].
  exact Hfreg.
Qed.

Theorem output_contained_in_primitive_subregion : forall px py f_reg p_sub nat_eff,
  rect_contains_point px py (resolve_primitive_output f_reg p_sub nat_eff) ->
  rect_contains_point px py p_sub.
Proof.
  intros px py f_reg p_sub nat_eff Hpt.
  unfold resolve_primitive_output in Hpt.
  apply point_in_intersect_iff in Hpt.
  destruct Hpt as [Hnat Hsub].
  unfold resolve_primitive_subregion in Hsub.
  apply point_in_intersect_iff in Hsub.
  destruct Hsub as [Hfreg Hpsub].
  exact Hpsub.
Qed.

Theorem output_contained_in_natural_effect : forall px py f_reg p_sub nat_eff,
  rect_contains_point px py (resolve_primitive_output f_reg p_sub nat_eff) ->
  rect_contains_point px py nat_eff.
Proof.
  intros px py f_reg p_sub nat_eff Hpt.
  unfold resolve_primitive_output in Hpt.
  apply point_in_intersect_iff in Hpt.
  destruct Hpt as [Hnat Hsub].
  exact Hnat.
Qed.
