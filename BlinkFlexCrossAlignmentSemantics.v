(** * BlinkFlexCrossAlignmentSemantics.v
    Formal Audit of Chromium Blink Flex Cross Alignment vs. W3C CSS Flexbox §9.4 & §9.6 *)

From Stdlib Require Import ZArith.ZArith.
From Stdlib Require Import micromega.Lia.
Open Scope Z_scope.

(** ** 1. Core Data Structures *)

Inductive ItemPosition : Type :=
  | Stretch
  | FlexStart
  | FlexEnd
  | Center
  | Baseline.

Record FlexItem : Type := mkFlexItem {
  align_self : ItemPosition;
  cross_axis_is_auto : bool;      (* true iff cross-size is 'auto' and no auto cross margins *)
  hypothetical_cross_size : Z;    (* intrinsic / unstretched border-box cross size *)
  min_cross_size : Z;             (* resolved min-width / min-height *)
  max_cross_size : Z;             (* resolved max-width / max-height *)
  margin_cross_start : Z;
  margin_cross_end : Z;
  baseline_ascent : Z             (* distance from margin-start edge to baseline *)
}.

Record FlexLine : Type := mkFlexLine {
  line_cross_offset : Z;          (* offset of line from container cross-start *)
  line_cross_size : Z;            (* computed cross size of the flex line *)
  line_max_ascent : Z             (* max baseline_ascent among Baseline items in line *)
}.

(** ** 2. Cross Size Determination & Stretch Alignment (§9.4) *)

Definition clamp (val min_val max_val : Z) : Z :=
  Z.min max_val (Z.max min_val val).

Definition item_margins (item : FlexItem) : Z :=
  margin_cross_start item + margin_cross_end item.

(** Resolves the used border-box cross size of a FlexItem (W3C §9.4 Step 11). *)
Definition resolve_used_cross_size (item : FlexItem) (line : FlexLine) : Z :=
  let margins := item_margins item in
  match align_self item, cross_axis_is_auto item with
  | Stretch, true =>
      let stretched_target := Z.max 0 (line_cross_size line - margins) in
      clamp stretched_target (min_cross_size item) (max_cross_size item)
  | _, _ =>
      clamp (hypothetical_cross_size item) (min_cross_size item) (max_cross_size item)
  end.

(** Total outer (margin-box) cross size of the item. *)
Definition resolve_outer_cross_size (item : FlexItem) (line : FlexLine) : Z :=
  resolve_used_cross_size item line + item_margins item.

(** ** 3. Cross Offset Calculation (§9.6) *)

(** Computes the offset of the item's cross-start margin edge relative to the line's cross-start edge. *)
Definition compute_cross_offset (item : FlexItem) (line : FlexLine) : Z :=
  let outer_size := resolve_outer_cross_size item line in
  let free_space := line_cross_size line - outer_size in
  match align_self item with
  | Stretch => 0
  | FlexStart => 0
  | FlexEnd => free_space
  | Center => free_space / 2
  | Baseline => line_max_ascent line - baseline_ascent item
  end.

(** Final border-box cross position relative to the flex container. *)
Definition compute_border_box_cross_pos (item : FlexItem) (line : FlexLine) : Z :=
  line_cross_offset line + compute_cross_offset item line + margin_cross_start item.

(** ** 4. Well-Formedness Predicates & Mathematical Invariants *)

Definition WellFormedLineItem (item : FlexItem) (line : FlexLine) : Prop :=
  0 <= min_cross_size item /\
  min_cross_size item <= max_cross_size item /\
  0 <= item_margins item /\
  min_cross_size item + item_margins item <= line_cross_size line /\
  clamp (hypothetical_cross_size item) (min_cross_size item) (max_cross_size item) + item_margins item <= line_cross_size line /\
  (align_self item = Baseline ->
    0 <= baseline_ascent item /\
    baseline_ascent item <= line_max_ascent line /\
    line_max_ascent line + (resolve_outer_cross_size item line - baseline_ascent item) <= line_cross_size line).

Lemma clamp_bounds : forall v min max,
  min <= max ->
  min <= clamp v min max <= max.
Proof.
  intros v min max Hle.
  unfold clamp.
  split.
  - apply Z.min_glb_iff. split.
    + exact Hle.
    + apply Z.le_max_l.
  - apply Z.le_min_l.
Qed.

Lemma clamp_stretch_le : forall line margins min max,
  0 <= min ->
  0 <= margins ->
  min + margins <= line ->
  min <= max ->
  clamp (Z.max 0 (line - margins)) min max + margins <= line.
Proof.
  intros line margins min max Hmin0 Hmarg Hmin Hle.
  unfold clamp.
  rewrite (Z.max_r 0 (line - margins)) by lia.
  destruct (Z.le_gt_cases max (line - margins)) as [H1 | H1].
  - assert (Hmin_le : Z.min max (Z.max min (line - margins)) <= max).
    { apply Z.le_min_l. }
    lia.
  - rewrite (Z.max_r min (line - margins)) by lia.
    assert (Hmin_le : Z.min max (line - margins) <= line - margins).
    { apply Z.le_min_r. }
    lia.
Qed.

(** *** Invariant 1: Item Outer Cross Size is Bounded by Line Cross Size *)
Theorem item_outer_cross_size_bounded :
  forall (item : FlexItem) (line : FlexLine),
    WellFormedLineItem item line ->
    0 <= resolve_outer_cross_size item line <= line_cross_size line.
Proof.
  intros item line Hwf.
  destruct Hwf as [Hmin0 [Hminmax [Hmarg0 [Hmin_line [Hhyp_line _]]]]].
  unfold resolve_outer_cross_size, resolve_used_cross_size.
  destruct (align_self item); destruct (cross_axis_is_auto item).
  - (* Stretch, auto *)
    pose proof (clamp_bounds (Z.max 0 (line_cross_size line - item_margins item))
                             (min_cross_size item) (max_cross_size item) Hminmax) as [Hb1 Hb2].
    pose proof (clamp_stretch_le (line_cross_size line) (item_margins item)
                                 (min_cross_size item) (max_cross_size item)
                                 Hmin0 Hmarg0 Hmin_line Hminmax) as Hstr.
    lia.
  - (* Stretch, false *)
    pose proof (clamp_bounds (hypothetical_cross_size item)
                             (min_cross_size item) (max_cross_size item) Hminmax) as [Hb1 Hb2].
    lia.
  - (* FlexStart, true *)
    pose proof (clamp_bounds (hypothetical_cross_size item)
                             (min_cross_size item) (max_cross_size item) Hminmax) as [Hb1 Hb2].
    lia.
  - (* FlexStart, false *)
    pose proof (clamp_bounds (hypothetical_cross_size item)
                             (min_cross_size item) (max_cross_size item) Hminmax) as [Hb1 Hb2].
    lia.
  - (* FlexEnd, true *)
    pose proof (clamp_bounds (hypothetical_cross_size item)
                             (min_cross_size item) (max_cross_size item) Hminmax) as [Hb1 Hb2].
    lia.
  - (* FlexEnd, false *)
    pose proof (clamp_bounds (hypothetical_cross_size item)
                             (min_cross_size item) (max_cross_size item) Hminmax) as [Hb1 Hb2].
    lia.
  - (* Center, true *)
    pose proof (clamp_bounds (hypothetical_cross_size item)
                             (min_cross_size item) (max_cross_size item) Hminmax) as [Hb1 Hb2].
    lia.
  - (* Center, false *)
    pose proof (clamp_bounds (hypothetical_cross_size item)
                             (min_cross_size item) (max_cross_size item) Hminmax) as [Hb1 Hb2].
    lia.
  - (* Baseline, true *)
    pose proof (clamp_bounds (hypothetical_cross_size item)
                             (min_cross_size item) (max_cross_size item) Hminmax) as [Hb1 Hb2].
    lia.
  - (* Baseline, false *)
    pose proof (clamp_bounds (hypothetical_cross_size item)
                             (min_cross_size item) (max_cross_size item) Hminmax) as [Hb1 Hb2].
    lia.
Qed.

(** *** Invariant 2: Cross Alignment Offset is Non-Negative *)
Theorem cross_offset_non_negative :
  forall (item : FlexItem) (line : FlexLine),
    WellFormedLineItem item line ->
    0 <= compute_cross_offset item line.
Proof.
  intros item line Hwf.
  pose proof (item_outer_cross_size_bounded item line Hwf) as Hbound.
  destruct Hwf as [_ [_ [_ [_ [_ Hbase]]]]].
  unfold compute_cross_offset.
  destruct (align_self item) eqn:Halign.
  - (* Stretch *) lia.
  - (* FlexStart *) lia.
  - (* FlexEnd *) lia.
  - (* Center *)
    assert (Hfree : 0 <= line_cross_size line - resolve_outer_cross_size item line) by lia.
    apply Z.div_pos; lia.
  - (* Baseline *)
    destruct (Hbase eq_refl) as [Hbase0 [Hbasemax _]].
    lia.
Qed.

(** *** Invariant 3: Line Containment (Margin Box Fits Completely Inside Line) *)
Theorem cross_item_contained_in_line :
  forall (item : FlexItem) (line : FlexLine),
    WellFormedLineItem item line ->
    compute_cross_offset item line + resolve_outer_cross_size item line <= line_cross_size line.
Proof.
  intros item line Hwf.
  pose proof (item_outer_cross_size_bounded item line Hwf) as Hbound.
  destruct Hwf as [_ [_ [_ [_ [_ Hbase]]]]].
  unfold compute_cross_offset.
  destruct (align_self item) eqn:Halign.
  - (* Stretch *) lia.
  - (* FlexStart *) lia.
  - (* FlexEnd *) lia.
  - (* Center *)
    assert (Hdiv : (line_cross_size line - resolve_outer_cross_size item line) / 2 <=
                   line_cross_size line - resolve_outer_cross_size item line).
    { apply Z.div_le_upper_bound; lia. }
    lia.
  - (* Baseline *)
    destruct (Hbase eq_refl) as [_ [_ Hlinebase]].
    lia.
Qed.

(** *** Invariant 4: Stretch Maximality when Unconstrained by Max Size *)
Theorem stretch_fills_available_space :
  forall (item : FlexItem) (line : FlexLine),
    align_self item = Stretch ->
    cross_axis_is_auto item = true ->
    0 <= item_margins item ->
    min_cross_size item + item_margins item <= line_cross_size line ->
    line_cross_size line - item_margins item <= max_cross_size item ->
    min_cross_size item <= max_cross_size item ->
    0 <= min_cross_size item ->
    resolve_outer_cross_size item line = line_cross_size line.
Proof.
  intros item line Hal Hauto Hmarg Hmin Hmax Hminmax Hmin0.
  unfold resolve_outer_cross_size, resolve_used_cross_size, clamp.
  rewrite Hal, Hauto.
  rewrite (Z.max_r 0 (line_cross_size line - item_margins item)) by lia.
  rewrite (Z.max_r (min_cross_size item) (line_cross_size line - item_margins item)) by lia.
  rewrite (Z.min_r (max_cross_size item) (line_cross_size line - item_margins item)) by lia.
  lia.
Qed.
