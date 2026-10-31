(******************************************************************************)
(* BlinkInlineBoxAlignmentSemantics.v                                         *)
(* Formal Specification for CSS Inline Box Model Vertical Alignment          *)
(* & Strut Metrics (W3C CSS Inline Layout Module Level 3)                      *)
(*                                                                            *)
(* Fully constructive, verified in Rocq / Coq 9.3.0 with 0 admits.            *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Import ListNotations.
Open Scope Z_scope.

(** * 1. Data Types *)

(** Vertical alignment property values per W3C CSS Inline Layout 3 §5. *)
Inductive VerticalAlign : Type :=
  | AlignBaseline
  | AlignMiddle
  | AlignTop
  | AlignBottom
  | AlignSub
  | AlignSuper.

(** Font metrics governing inline layout (ascent, descent, x-height). *)
Record InlineFontMetrics : Type := {
  font_ascent : Z;
  font_descent : Z;
  font_x_height : Z
}.

(** Metrics and vertical alignment configuration of an inline box. *)
Record InlineBoxMetrics : Type := {
  box_valign : VerticalAlign;
  box_height : Z;
  box_font : InlineFontMetrics
}.

(** * 2. Alignment Offsets & Metric Helpers *)

(** Subscript baseline downward shift. *)
Definition sub_shift (f : InlineFontMetrics) : Z :=
  f.(font_descent) / 2.

(** Superscript baseline upward shift. *)
Definition super_shift (f : InlineFontMetrics) : Z :=
  f.(font_ascent) / 2.

(** Check whether an alignment mode participates in baseline alignment. *)
Definition is_baseline_aligned (v : VerticalAlign) : bool :=
  match v with
  | AlignBaseline
  | AlignMiddle
  | AlignSub
  | AlignSuper => true
  | AlignTop
  | AlignBottom => false
  end.

(** Effective distance above the baseline for a box. *)
Definition box_ascent (box : InlineBoxMetrics) : Z :=
  match box.(box_valign) with
  | AlignBaseline => box.(box_font).(font_ascent)
  | AlignMiddle   => (box.(box_font).(font_x_height) + box.(box_height)) / 2
  | AlignSub      => box.(box_font).(font_ascent) - sub_shift box.(box_font)
  | AlignSuper    => box.(box_font).(font_ascent) + super_shift box.(box_font)
  | AlignTop      => 0
  | AlignBottom   => 0
  end.

(** Effective distance below the baseline for a box. *)
Definition box_descent (box : InlineBoxMetrics) : Z :=
  box.(box_height) - box_ascent box.

(** Computes the y-coordinate offset of an inline box within the line box. *)
Definition compute_box_y_offset
  (box : InlineBoxMetrics) (baseline_y line_height : Z) : Z :=
  match box.(box_valign) with
  | AlignTop      => 0
  | AlignBottom   => line_height - box.(box_height)
  | AlignBaseline
  | AlignMiddle
  | AlignSub
  | AlignSuper    => baseline_y - box_ascent box
  end.

(** * 3. Line Box Bounds Computation *)

(** Accumulator record for folding line box children. *)
Record LineBoxAccum : Type := mkLineBoxAccum {
  acc_ascent : Z;
  acc_descent : Z;
  acc_max_height : Z
}.

(** Folds through line boxes to aggregate ascent, descent, and height. *)
Fixpoint compute_boxes_accum (boxes : list InlineBoxMetrics) : LineBoxAccum :=
  match boxes with
  | [] => mkLineBoxAccum 0 0 0
  | b :: rest =>
      let r := compute_boxes_accum rest in
      let a := if is_baseline_aligned b.(box_valign)
               then Z.max (box_ascent b) r.(acc_ascent)
               else r.(acc_ascent) in
      let d := if is_baseline_aligned b.(box_valign)
               then Z.max (box_descent b) r.(acc_descent)
               else r.(acc_descent) in
      let h := Z.max b.(box_height) r.(acc_max_height) in
      mkLineBoxAccum a d h
  end.

(** Computes the baseline position and total line height of a line box.
    Returns (baseline_y, total_line_height). *)
Definition compute_line_box_bounds
  (line_boxes : list InlineBoxMetrics) (strut : InlineFontMetrics) : (Z * Z) :=
  let acc := compute_boxes_accum line_boxes in
  let max_asc := Z.max strut.(font_ascent) acc.(acc_ascent) in
  let max_desc := Z.max strut.(font_descent) acc.(acc_descent) in
  let baseline_y := Z.max 0 max_asc in
  let baseline_height := baseline_y + Z.max 0 max_desc in
  let strut_height := strut.(font_ascent) + strut.(font_descent) in
  let total_line_height := Z.max (Z.max baseline_height strut_height) acc.(acc_max_height) in
  (baseline_y, total_line_height).

(** * 4. Verification and Soundness Theorems (0 admits) *)

(** Theorem 1: The strut enforces a minimum line height. *)
Theorem strut_enforces_min_line_height :
  forall (line_boxes : list InlineBoxMetrics) (strut : InlineFontMetrics),
    let '(_, total_line_height) := compute_line_box_bounds line_boxes strut in
    total_line_height >= strut.(font_ascent) + strut.(font_descent).
Proof.
  intros line_boxes strut.
  unfold compute_line_box_bounds.
  simpl.
  set (acc := compute_boxes_accum line_boxes).
  set (max_asc := Z.max (font_ascent strut) (acc_ascent acc)).
  set (max_desc := Z.max (font_descent strut) (acc_descent acc)).
  set (baseline_y := Z.max 0 max_asc).
  set (baseline_height := baseline_y + Z.max 0 max_desc).
  set (strut_height := font_ascent strut + font_descent strut).
  set (total_line_height := Z.max (Z.max baseline_height strut_height) (acc_max_height acc)).
  pose proof (Z.le_max_l (Z.max baseline_height strut_height) (acc_max_height acc)) as H1.
  pose proof (Z.le_max_r baseline_height strut_height) as H2.
  lia.
Qed.

Corollary strut_enforces_min_line_height_eq :
  forall (line_boxes : list InlineBoxMetrics) (strut : InlineFontMetrics) baseline_y total_line_height,
    compute_line_box_bounds line_boxes strut = (baseline_y, total_line_height) ->
    total_line_height >= strut.(font_ascent) + strut.(font_descent).
Proof.
  intros line_boxes strut baseline_y total_line_height Hres.
  pose proof (strut_enforces_min_line_height line_boxes strut) as Hmin.
  rewrite Hres in Hmin.
  exact Hmin.
Qed.

(** Theorem 2: The baseline y-coordinate is within [0, total_line_height]. *)
Theorem baseline_in_bounds :
  forall (line_boxes : list InlineBoxMetrics) (strut : InlineFontMetrics),
    let '(baseline_y, total_line_height) := compute_line_box_bounds line_boxes strut in
    0 <= baseline_y <= total_line_height.
Proof.
  intros line_boxes strut.
  unfold compute_line_box_bounds.
  simpl.
  set (acc := compute_boxes_accum line_boxes).
  set (max_asc := Z.max (font_ascent strut) (acc_ascent acc)).
  set (max_desc := Z.max (font_descent strut) (acc_descent acc)).
  set (baseline_y := Z.max 0 max_asc).
  set (baseline_height := baseline_y + Z.max 0 max_desc).
  set (strut_height := font_ascent strut + font_descent strut).
  set (total_line_height := Z.max (Z.max baseline_height strut_height) (acc_max_height acc)).
  pose proof (Z.le_max_l 0 max_asc) as Hby_pos.
  pose proof (Z.le_max_l 0 max_desc) as Hdesc_pos.
  pose proof (Z.le_max_l baseline_height strut_height) as Hbh_le.
  pose proof (Z.le_max_l (Z.max baseline_height strut_height) (acc_max_height acc)) as Htlh_le.
  split.
  - lia.
  - lia.
Qed.

Corollary baseline_in_bounds_eq :
  forall (line_boxes : list InlineBoxMetrics) (strut : InlineFontMetrics) baseline_y total_line_height,
    compute_line_box_bounds line_boxes strut = (baseline_y, total_line_height) ->
    0 <= baseline_y <= total_line_height.
Proof.
  intros line_boxes strut baseline_y total_line_height Hres.
  pose proof (baseline_in_bounds line_boxes strut) as Hbounds.
  rewrite Hres in Hbounds.
  exact Hbounds.
Qed.

(** Helper lemma: Membership in line_boxes implies bounds from accumulator. *)
Lemma compute_boxes_accum_in :
  forall line_boxes box,
    In box line_boxes ->
    (is_baseline_aligned box.(box_valign) = true ->
       box_ascent box <= (compute_boxes_accum line_boxes).(acc_ascent) /\
       box_descent box <= (compute_boxes_accum line_boxes).(acc_descent)) /\
    box.(box_height) <= (compute_boxes_accum line_boxes).(acc_max_height).
Proof.
  induction line_boxes as [| b rest IH]; intros box Hin.
  - simpl in Hin. contradiction.
  - simpl in Hin. destruct Hin as [Heq | Hin_rest].
    + subst b.
      simpl.
      split.
      * intros Haligned.
        rewrite Haligned.
        split; apply Z.le_max_l.
      * apply Z.le_max_l.
    + specialize (IH box Hin_rest).
      destruct IH as [IH_align IH_h].
      simpl.
      split.
      * intros Haligned.
        specialize (IH_align Haligned).
        destruct IH_align as [IHa IHd].
        destruct (is_baseline_aligned (box_valign b)).
        -- split.
           ++ eapply Z.le_trans; [exact IHa | apply Z.le_max_r].
           ++ eapply Z.le_trans; [exact IHd | apply Z.le_max_r].
        -- split; assumption.
      * eapply Z.le_trans; [exact IH_h | apply Z.le_max_r].
Qed.

(** Theorem 3: Every aligned box is placed within [0, total_line_height]. *)
Theorem box_within_line :
  forall (line_boxes : list InlineBoxMetrics) (strut : InlineFontMetrics) (box : InlineBoxMetrics),
    In box line_boxes ->
    let '(baseline_y, total_line_height) := compute_line_box_bounds line_boxes strut in
    let box_y := compute_box_y_offset box baseline_y total_line_height in
    0 <= box_y /\ box_y + box.(box_height) <= total_line_height.
Proof.
  intros line_boxes strut box Hin.
  pose proof (compute_boxes_accum_in line_boxes box Hin) as [Halign_bounds Hheight_bound].
  unfold compute_line_box_bounds.
  simpl.
  set (acc := compute_boxes_accum line_boxes).
  set (max_asc := Z.max (font_ascent strut) (acc_ascent acc)).
  set (max_desc := Z.max (font_descent strut) (acc_descent acc)).
  set (baseline_y := Z.max 0 max_asc).
  set (baseline_height := baseline_y + Z.max 0 max_desc).
  set (strut_height := font_ascent strut + font_descent strut).
  set (total_line_height := Z.max (Z.max baseline_height strut_height) (acc_max_height acc)).
  assert (Hh_le : box_height box <= total_line_height).
  { eapply Z.le_trans; [exact Hheight_bound |].
    unfold total_line_height.
    apply Z.le_max_r. }
  unfold compute_box_y_offset.
  destruct (box_valign box) eqn:Hvalign.
  - (* AlignBaseline *)
    assert (Hba : is_baseline_aligned AlignBaseline = true) by reflexivity.
    destruct (Halign_bounds Hba) as [Hasc_le Hdesc_le].
    unfold box_descent in Hdesc_le.
    assert (Hasc_bound : box_ascent box <= baseline_y).
    { eapply Z.le_trans; [exact Hasc_le |].
      eapply Z.le_trans; [apply Z.le_max_r |].
      apply Z.le_max_r. }
    assert (Hdesc_bound : box_height box - box_ascent box <= Z.max 0 max_desc).
    { eapply Z.le_trans; [exact Hdesc_le |].
      eapply Z.le_trans; [apply Z.le_max_r |].
      apply Z.le_max_r. }
    assert (Hline_ge : baseline_height <= total_line_height).
    { eapply Z.le_trans; [apply Z.le_max_l |].
      unfold total_line_height. apply Z.le_max_l. }
    split; lia.
  - (* AlignMiddle *)
    assert (Hba : is_baseline_aligned AlignMiddle = true) by reflexivity.
    destruct (Halign_bounds Hba) as [Hasc_le Hdesc_le].
    unfold box_descent in Hdesc_le.
    assert (Hasc_bound : box_ascent box <= baseline_y).
    { eapply Z.le_trans; [exact Hasc_le |].
      eapply Z.le_trans; [apply Z.le_max_r |].
      apply Z.le_max_r. }
    assert (Hdesc_bound : box_height box - box_ascent box <= Z.max 0 max_desc).
    { eapply Z.le_trans; [exact Hdesc_le |].
      eapply Z.le_trans; [apply Z.le_max_r |].
      apply Z.le_max_r. }
    assert (Hline_ge : baseline_height <= total_line_height).
    { eapply Z.le_trans; [apply Z.le_max_l |].
      unfold total_line_height. apply Z.le_max_l. }
    split; lia.
  - (* AlignTop *)
    split; lia.
  - (* AlignBottom *)
    split; lia.
  - (* AlignSub *)
    assert (Hba : is_baseline_aligned AlignSub = true) by reflexivity.
    destruct (Halign_bounds Hba) as [Hasc_le Hdesc_le].
    unfold box_descent in Hdesc_le.
    assert (Hasc_bound : box_ascent box <= baseline_y).
    { eapply Z.le_trans; [exact Hasc_le |].
      eapply Z.le_trans; [apply Z.le_max_r |].
      apply Z.le_max_r. }
    assert (Hdesc_bound : box_height box - box_ascent box <= Z.max 0 max_desc).
    { eapply Z.le_trans; [exact Hdesc_le |].
      eapply Z.le_trans; [apply Z.le_max_r |].
      apply Z.le_max_r. }
    assert (Hline_ge : baseline_height <= total_line_height).
    { eapply Z.le_trans; [apply Z.le_max_l |].
      unfold total_line_height. apply Z.le_max_l. }
    split; lia.
  - (* AlignSuper *)
    assert (Hba : is_baseline_aligned AlignSuper = true) by reflexivity.
    destruct (Halign_bounds Hba) as [Hasc_le Hdesc_le].
    unfold box_descent in Hdesc_le.
    assert (Hasc_bound : box_ascent box <= baseline_y).
    { eapply Z.le_trans; [exact Hasc_le |].
      eapply Z.le_trans; [apply Z.le_max_r |].
      apply Z.le_max_r. }
    assert (Hdesc_bound : box_height box - box_ascent box <= Z.max 0 max_desc).
    { eapply Z.le_trans; [exact Hdesc_le |].
      eapply Z.le_trans; [apply Z.le_max_r |].
      apply Z.le_max_r. }
    assert (Hline_ge : baseline_height <= total_line_height).
    { eapply Z.le_trans; [apply Z.le_max_l |].
      unfold total_line_height. apply Z.le_max_l. }
    split; lia.
Qed.

Corollary box_within_line_eq :
  forall (line_boxes : list InlineBoxMetrics) (strut : InlineFontMetrics)
         (baseline_y total_line_height : Z) (box : InlineBoxMetrics),
    compute_line_box_bounds line_boxes strut = (baseline_y, total_line_height) ->
    In box line_boxes ->
    let box_y := compute_box_y_offset box baseline_y total_line_height in
    0 <= box_y /\ box_y + box.(box_height) <= total_line_height.
Proof.
  intros line_boxes strut baseline_y total_line_height box Hres Hin.
  pose proof (box_within_line line_boxes strut box Hin) as Hwithin.
  rewrite Hres in Hwithin.
  exact Hwithin.
Qed.


(******************************************************************************)
(* 4. CHROMIUM BLINK HALF-LEADING & BASELINE METRICS ALIGNMENT                *)
(******************************************************************************)

(** W3C CSS Inline 3 §3 & Chromium Blink InlineLayoutAlgorithm:              *)
(** Leading L_delta = line_height - (ascent + descent).                       *)
(** Half-leading is distributed symmetrically above ascent and below descent. *)

Definition compute_half_leading (line_height font_box_h : Z) : Z :=
  Z.max 0 ((line_height - font_box_h) / 2).

Definition compute_line_box_half_leading (line_height ascent descent : Z) : (Z * Z) :=
  let leading := line_height - (ascent + descent) in
  let half := Z.max 0 (leading / 2) in
  (ascent + half, descent + (Z.max 0 (leading - half))).

Definition compute_first_line_baseline (box_top line_height ascent descent : Z) : Z :=
  box_top + compute_half_leading line_height (ascent + descent) + ascent.

Definition compute_snapped_baseline (box_top ascent : Z) : Z :=
  box_top + ascent.

Theorem half_leading_nonneg : forall L E,
  0 <= compute_half_leading L E.
Proof.
  intros L E.
  unfold compute_half_leading.
  apply Z.le_max_l.
Qed.

Theorem line_height_conserved : forall L A D,
  0 <= A -> 0 <= D ->
  A + D <= L ->
  let (asc, desc) := compute_line_box_half_leading L A D in
  asc + desc = L.
Proof.
  intros L A D Ha Hd Hle.
  unfold compute_line_box_half_leading.
  set (leading := L - (A + D)).
  assert (Hlead_ge_0 : 0 <= leading) by (unfold leading; lia).
  assert (Hhalf_ge_0 : 0 <= leading / 2).
  { apply Z.div_pos; lia. }
  pose proof (Z.div_le_upper_bound leading 2 leading).
  assert (Hrem_ge_0 : 0 <= leading - leading / 2) by lia.
  rewrite (Z.max_r 0 (leading / 2)) by lia.
  rewrite (Z.max_r 0 (leading - leading / 2)) by lia.
  unfold leading.
  lia.
Qed.

Theorem baseline_within_line : forall box_top L A D,
  0 <= box_top ->
  0 <= A -> 0 <= D ->
  A + D <= L ->
  box_top <= compute_first_line_baseline box_top L A D <= box_top + L.
Proof.
  intros box_top L A D Htop Ha Hd Hle.
  unfold compute_first_line_baseline, compute_half_leading.
  pose proof (Z.div_le_upper_bound (L - (A + D)) 2 (L - (A + D))).
  assert (Hhalf_ge_0 : 0 <= (L - (A + D)) / 2).
  { apply Z.div_pos; lia. }
  rewrite (Z.max_r 0 ((L - (A + D)) / 2)) by lia.
  split; lia.
Qed.

Theorem snapped_baseline_matches_integer_ascent : forall box_top A,
  compute_snapped_baseline box_top A = box_top + A.
Proof.
  intros. reflexivity.
Qed.
