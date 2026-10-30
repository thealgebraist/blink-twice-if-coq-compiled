(* ========================================================================= *)
(*               BlinkMulticolRuleGeometrySemantics.v                        *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Multi-Column Column Rules & Gutter     *)
(* Geometry per W3C CSS Multi-column Layout Module Level 1 §4.               *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Record MulticolGeometry := {
  col_count : Z;
  col_width : Z;
  gutter_width : Z;
  rule_width : Z
}.

Definition multicol_valid (m : MulticolGeometry) : Prop :=
  col_count m >= 1 /\
  col_width m >= 0 /\
  gutter_width m >= 0 /\
  rule_width m >= 0.

Definition multicol_container_width (m : MulticolGeometry) : Z :=
  col_count m * col_width m + (col_count m - 1) * gutter_width m.

Definition column_start_x (m : MulticolGeometry) (idx : Z) : Z :=
  idx * (col_width m + gutter_width m).

Definition rule_gutter_left_offset (m : MulticolGeometry) : Z :=
  (gutter_width m - rule_width m) / 2.

Definition rule_gutter_right_offset (m : MulticolGeometry) : Z :=
  gutter_width m - rule_width m - rule_gutter_left_offset m.

Definition rule_start_x (m : MulticolGeometry) (idx : Z) : Z :=
  column_start_x m idx + col_width m + rule_gutter_left_offset m.

Theorem gutter_centering_symmetry : forall m,
  rule_gutter_left_offset m + rule_gutter_right_offset m = gutter_width m - rule_width m.
Proof.
  intros m.
  unfold rule_gutter_right_offset.
  lia.
Qed.

Theorem gutter_centering_parity_diff : forall m,
  Z.abs (rule_gutter_left_offset m - rule_gutter_right_offset m) <= 1.
Proof.
  intros m.
  unfold rule_gutter_right_offset, rule_gutter_left_offset.
  pose proof (Z.div_mod (gutter_width m - rule_width m) 2) as Hdiv.
  assert (Htwo: 2 <> 0) by lia.
  specialize (Hdiv Htwo).
  pose proof (Z.mod_pos_bound (gutter_width m - rule_width m) 2) as Hbound.
  assert (Hpos: 0 < 2) by lia.
  specialize (Hbound Hpos).
  assert (Hrem_bound: (gutter_width m - rule_width m) mod 2 = 0 \/ (gutter_width m - rule_width m) mod 2 = 1) by lia.
  destruct Hrem_bound as [H0 | H1]; lia.
Qed.

Theorem rule_does_not_overlap_preceding_col : forall m idx,
  rule_width m <= gutter_width m ->
  rule_start_x m idx >= column_start_x m idx + col_width m.
Proof.
  intros m idx Hle.
  unfold rule_start_x, rule_gutter_left_offset.
  assert (Hsub: gutter_width m - rule_width m >= 0) by lia.
  assert (Hdiv: (gutter_width m - rule_width m) / 2 >= 0) by (apply Z.le_ge; apply Z.div_pos; lia).
  lia.
Qed.

Theorem rule_does_not_overlap_succeeding_col : forall m idx,
  rule_width m <= gutter_width m ->
  rule_start_x m idx + rule_width m <= column_start_x m (idx + 1).
Proof.
  intros m idx Hle.
  unfold rule_start_x, column_start_x, rule_gutter_left_offset.
  assert (Hexpand: (idx + 1) * (col_width m + gutter_width m) =
                    idx * (col_width m + gutter_width m) + col_width m + gutter_width m) by ring.
  rewrite Hexpand.
  assert (Hsub: gutter_width m - rule_width m >= 0) by lia.
  pose proof (Z.div_le_upper_bound (gutter_width m - rule_width m) 2 (gutter_width m - rule_width m)) as Hup.
  assert ((gutter_width m - rule_width m) / 2 <= gutter_width m - rule_width m).
  { apply Hup; lia. }
  lia.
Qed.

Theorem rule_contained_in_container : forall m idx,
  multicol_valid m ->
  rule_width m <= gutter_width m ->
  0 <= idx ->
  idx < col_count m - 1 ->
  0 <= rule_start_x m idx /\
  rule_start_x m idx + rule_width m <= multicol_container_width m.
Proof.
  intros m idx [Hcnt [Hcol [Hgut Hrule]]] Hle Hidx_ge Hidx_lt.
  pose proof (rule_does_not_overlap_preceding_col m idx Hle) as Hleft.
  pose proof (rule_does_not_overlap_succeeding_col m idx Hle) as Hright.
  unfold column_start_x in *.
  assert (Hcol_pos: idx * (col_width m + gutter_width m) >= 0) by nia.
  split.
  - lia.
  - unfold multicol_container_width.
    assert (Hsucc_le: column_start_x m (idx + 1) <= column_start_x m (col_count m - 1)).
    { unfold column_start_x.
      apply Z.mul_le_mono_nonneg_r; lia. }
    unfold column_start_x in Hsucc_le.
    assert (Hlast: (col_count m - 1) * (col_width m + gutter_width m) =
                   (col_count m - 1) * col_width m + (col_count m - 1) * gutter_width m) by ring.
    assert (Hcont: col_count m * col_width m = (col_count m - 1) * col_width m + col_width m).
    { assert (col_count m = (col_count m - 1) + 1) by ring.
      rewrite H. rewrite Z.mul_add_distr_r. ring. }
    lia.
Qed.
