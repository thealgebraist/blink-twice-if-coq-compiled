(* ========================================================================= *)
(*               BlinkVerticalFlowLayoutSemantics.v                          *)
(* ========================================================================= *)
(* Formal Semantics of Chromium Blink Block Formatting Context (BFC)         *)
(* Vertical Flow Layout, Cumulative Offset Induction, and Margin Collapsing  *)
(* Conforming to W3C CSS 2.2 §8.3.1, §9.4.1 and Blink NGBlockLayoutAlgorithm *)
(* Strictly verified in Rocq/Coq 9.3.0 with ZERO admits and ZERO axioms.     *)
(* ========================================================================= *)

From Stdlib Require Import ZArith List Lia Bool.
Import ListNotations.
Open Scope Z_scope.

(******************************************************************************)
(* 1. DATA STRUCTURES & DEFINITIONS                                           *)
(******************************************************************************)

Record BoxMetrics := mkBoxMetrics {
  bm_content_h : Z;    (* Content block height >= 0 *)
  bm_m_top : Z;        (* Top margin (positive or negative) *)
  bm_m_bottom : Z;     (* Bottom margin (positive or negative) *)
  bm_p_top : Z;        (* Top padding >= 0 *)
  bm_p_bottom : Z;     (* Bottom padding >= 0 *)
  bm_b_top : Z;        (* Top border >= 0 *)
  bm_b_bottom : Z      (* Bottom border >= 0 *)
}.

(** Effective outer block height: border + padding + content *)
Definition box_total_height (b : BoxMetrics) : Z :=
  bm_b_top b + bm_p_top b + bm_content_h b + bm_p_bottom b + bm_b_bottom b.

Record LayoutFragment := mkLayoutFragment {
  frag_y : Z;                  (* Top outer border position *)
  frag_h : Z;                  (* Total outer box height *)
  frag_collapsed_margin : Z    (* Collapsed margin above this box *)
}.

Record FlowState := mkFlowState {
  fs_cursor_y : Z;       (* Current vertical cursor at previous box bottom *)
  fs_margin_pos : Z;     (* Accumulated positive margin >= 0 *)
  fs_margin_neg : Z      (* Accumulated negative margin <= 0 *)
}.

Definition valid_box_metrics (b : BoxMetrics) : Prop :=
  0 <= bm_content_h b /\
  0 <= bm_p_top b /\ 0 <= bm_p_bottom b /\
  0 <= bm_b_top b /\ 0 <= bm_b_bottom b.

Definition valid_flow_state (st : FlowState) : Prop :=
  0 <= fs_margin_pos st /\ fs_margin_neg st <= 0.

(******************************************************************************)
(* 2. W3C CSS 2.2 §8.3.1 & BLINK MARGIN STRUT COLLAPSING ALGEBRA               *)
(******************************************************************************)

Definition margin_pos_part (m : Z) : Z := Z.max 0 m.
Definition margin_neg_part (m : Z) : Z := Z.min 0 m.

Definition collapse_margin_step (prev_pos prev_neg child_m : Z) : (Z * Z) :=
  (Z.max prev_pos (margin_pos_part child_m),
   Z.min prev_neg (margin_neg_part child_m)).

Definition margin_strut_sum (pos neg : Z) : Z :=
  pos + neg.

Lemma collapse_margin_preserves_signs : forall p n m,
  0 <= p -> n <= 0 ->
  let (p', n') := collapse_margin_step p n m in
  0 <= p' /\ n' <= 0.
Proof.
  intros p n m Hp Hn.
  unfold collapse_margin_step, margin_pos_part, margin_neg_part.
  split; lia.
Qed.

(******************************************************************************)
(* 3. INDUCTIVE VERTICAL FLOW LAYOUT TRANSITIONS                              *)
(******************************************************************************)

(** Single child block layout transition (NGBlockLayoutAlgorithm::Layout) *)
Definition step_vertical_flow (st : FlowState) (b : BoxMetrics) : (FlowState * LayoutFragment) :=
  let (eff_pos, eff_neg) := collapse_margin_step (fs_margin_pos st) (fs_margin_neg st) (bm_m_top b) in
  let collapsed_margin := margin_strut_sum eff_pos eff_neg in
  let child_y := fs_cursor_y st + collapsed_margin in
  let child_h := box_total_height b in
  let next_cursor := child_y + child_h in
  let next_pos := margin_pos_part (bm_m_bottom b) in
  let next_neg := margin_neg_part (bm_m_bottom b) in
  (mkFlowState next_cursor next_pos next_neg,
   mkLayoutFragment child_y child_h collapsed_margin).

(** Fold over a list of block elements in a BFC *)
Fixpoint compute_vertical_flow_rec (st : FlowState) (boxes : list BoxMetrics) : list LayoutFragment :=
  match boxes with
  | [] => []
  | b :: rest =>
      let (st', frag) := step_vertical_flow st b in
      frag :: compute_vertical_flow_rec st' rest
  end.

(** Entry point for a Block Formatting Context (container top offset) *)
Definition compute_vertical_flow (initial_y : Z) (boxes : list BoxMetrics) : list LayoutFragment :=
  let init_st := mkFlowState initial_y 0 0 in
  compute_vertical_flow_rec init_st boxes.

(******************************************************************************)
(* 4. FORMAL THEOREMS: SOUNDNESS, MONOTONICITY & INVARIANTS                   *)
(******************************************************************************)

Theorem step_flow_preserves_valid_state : forall st b,
  valid_flow_state st ->
  valid_box_metrics b ->
  let (st', _) := step_vertical_flow st b in
  valid_flow_state st'.
Proof.
  intros [cy p n] b [Hp Hn] Hb.
  unfold step_vertical_flow, valid_flow_state. simpl.
  unfold margin_pos_part, margin_neg_part.
  split; [apply Z.le_max_l | apply Z.le_min_l].
Qed.

(** Box height is non-negative for valid box metrics *)
Theorem box_total_height_nonneg : forall b,
  valid_box_metrics b ->
  0 <= box_total_height b.
Proof.
  intros b [Hch [Hpt [Hpb [Hbt Hbb]]]].
  unfold box_total_height.
  lia.
Qed.

(** Exact conservation law: the next cursor position equals child_y + child_h *)
Theorem step_flow_cursor_exact : forall st b,
  let (st', frag) := step_vertical_flow st b in
  fs_cursor_y st' = frag_y frag + frag_h frag.
Proof.
  intros st b.
  unfold step_vertical_flow. simpl.
  destruct (collapse_margin_step (fs_margin_pos st) (fs_margin_neg st) (bm_m_top b)).
  simpl. reflexivity.
Qed.

(** Non-negative margin monotonic advancement *)
Theorem step_flow_cursor_advances_nonneg : forall st b,
  valid_flow_state st ->
  valid_box_metrics b ->
  fs_margin_neg st = 0 ->
  0 <= bm_m_top b ->
  let (st', frag) := step_vertical_flow st b in
  fs_cursor_y st <= frag_y frag /\
  frag_y frag <= fs_cursor_y st'.
Proof.
  intros [cy p n] b [Hp Hn] Hvalid Hn0 Htop.
  unfold step_vertical_flow, valid_flow_state. simpl in *.
  subst n.
  unfold collapse_margin_step, margin_strut_sum, margin_pos_part, margin_neg_part.
  assert (Htop_pos: Z.max 0 (bm_m_top b) = bm_m_top b) by (apply Z.max_r; lia).
  assert (Htop_neg: Z.min 0 (bm_m_top b) = 0) by (apply Z.min_l; lia).
  rewrite Htop_pos, Htop_neg.
  simpl.
  assert (Hmin0: Z.min 0 0 = 0) by reflexivity.
  rewrite Hmin0.
  assert (Hsum: Z.max p (bm_m_top b) + 0 = Z.max p (bm_m_top b)) by ring.
  rewrite Hsum.
  pose proof (Z.le_max_r p (bm_m_top b)).
  pose proof (box_total_height_nonneg b Hvalid).
  split; lia.
Qed.

(** Sibling vertical non-overlapping monotonicity for consecutive elements *)
Theorem consecutive_fragments_nonneg_margins : forall st b1 b2,
  valid_flow_state st ->
  valid_box_metrics b1 ->
  valid_box_metrics b2 ->
  fs_margin_neg st = 0 ->
  0 <= bm_m_top b1 ->
  0 <= bm_m_bottom b1 ->
  0 <= bm_m_top b2 ->
  let '(st1, frag1) := step_vertical_flow st b1 in
  let '(st2, frag2) := step_vertical_flow st1 b2 in
  frag_y frag1 + frag_h frag1 <= frag_y frag2.
Proof.
  intros st b1 b2 Hst Hb1 Hb2 Hn1 Htop1 Hbot1 Htop2.
  destruct (step_vertical_flow st b1) as [st1 frag1] eqn:E1.
  destruct (step_vertical_flow st1 b2) as [st2 frag2] eqn:E2.
  unfold step_vertical_flow in E1, E2.
  inversion E1; subst; clear E1.
  inversion E2; subst; clear E2.
  simpl.
  unfold collapse_margin_step, margin_strut_sum, margin_pos_part, margin_neg_part.
  assert (Hbot1_pos: Z.max 0 (bm_m_bottom b1) = bm_m_bottom b1) by (apply Z.max_r; lia).
  assert (Hbot1_neg: Z.min 0 (bm_m_bottom b1) = 0) by (apply Z.min_l; lia).
  rewrite Hbot1_pos, Hbot1_neg.
  assert (Htop2_pos: Z.max 0 (bm_m_top b2) = bm_m_top b2) by (apply Z.max_r; lia).
  assert (Htop2_neg: Z.min 0 (bm_m_top b2) = 0) by (apply Z.min_l; lia).
  rewrite Htop2_pos, Htop2_neg.
  assert (Hmin0: Z.min 0 0 = 0) by reflexivity.
  rewrite Hmin0.
  pose proof (Z.le_max_l (bm_m_bottom b1) (bm_m_top b2)).
  lia.
Qed.

(** CSS 2.2 §8.3.1 Equivalence: For two adjacent blocks with positive margins m1, m2,
    the collapsed margin equals max(m1, m2). *)
Theorem adjacent_positive_margins_collapse_to_max : forall initial_y b1 b2,
  0 <= bm_m_bottom b1 ->
  0 <= bm_m_top b2 ->
  let init_st := mkFlowState initial_y 0 0 in
  let '(st1, frag1) := step_vertical_flow init_st b1 in
  let '(st2, frag2) := step_vertical_flow st1 b2 in
  frag_y frag2 = frag_y frag1 + frag_h frag1 + Z.max (bm_m_bottom b1) (bm_m_top b2).
Proof.
  intros initial_y b1 b2 Hbot1 Htop2.
  unfold step_vertical_flow. simpl.
  unfold collapse_margin_step, margin_strut_sum, margin_pos_part, margin_neg_part.
  assert (Hbot1_pos: Z.max 0 (bm_m_bottom b1) = bm_m_bottom b1) by (apply Z.max_r; lia).
  assert (Hbot1_neg: Z.min 0 (bm_m_bottom b1) = 0) by (apply Z.min_l; lia).
  rewrite Hbot1_pos, Hbot1_neg.
  assert (Htop2_pos: Z.max 0 (bm_m_top b2) = bm_m_top b2) by (apply Z.max_r; lia).
  assert (Htop2_neg: Z.min 0 (bm_m_top b2) = 0) by (apply Z.min_l; lia).
  rewrite Htop2_pos, Htop2_neg.
  assert (Hmin0: Z.min 0 0 = 0) by reflexivity.
  rewrite Hmin0.
  ring.
Qed.

(** Empty document identity *)
Theorem flow_empty_nil : forall initial_y,
  compute_vertical_flow initial_y [] = [].
Proof.
  intros. reflexivity.
Qed.

(** Single element positioning: first child with positive top margin m_top
    starts at initial_y + m_top *)
Theorem flow_single_element_pos : forall initial_y b,
  0 <= bm_m_top b ->
  match compute_vertical_flow initial_y [b] with
  | [frag] => frag_y frag = initial_y + bm_m_top b /\
              frag_h frag = box_total_height b /\
              frag_collapsed_margin frag = bm_m_top b
  | _ => False
  end.
Proof.
  intros initial_y b Htop.
  unfold compute_vertical_flow, compute_vertical_flow_rec, step_vertical_flow. simpl.
  unfold collapse_margin_step, margin_strut_sum, margin_pos_part, margin_neg_part.
  assert (Htop_pos: Z.max 0 (bm_m_top b) = bm_m_top b) by (apply Z.max_r; lia).
  assert (Htop_neg: Z.min 0 (bm_m_top b) = 0) by (apply Z.min_l; lia).
  rewrite Htop_pos, Htop_neg.
  simpl.
  split; [lia | split; [reflexivity | lia]].
Qed.

(******************************************************************************)
(* 5. APPLICATION TO REAL-WORLD WIKIPEDIA ARTICLE FLOW LAYOUT                 *)
(******************************************************************************)

Definition b_h1 : BoxMetrics := mkBoxMetrics 34 0 4 0 0 0 0.
Definition b_sub : BoxMetrics := mkBoxMetrics 14 0 8 0 0 0 0.
Definition b_hatnote : BoxMetrics := mkBoxMetrics 16 0 12 0 0 0 0.
Definition b_lead : BoxMetrics := mkBoxMetrics 72 0 12 0 0 0 0.
Definition b_toc : BoxMetrics := mkBoxMetrics 99 0 12 0 0 0 0.
Definition b_sec : BoxMetrics := mkBoxMetrics 20 12 8 0 0 0 0.
Definition b_table : BoxMetrics := mkBoxMetrics 97 6 0 0 0 0 0.

Definition wikipedia_article_blocks : list BoxMetrics :=
  [b_h1; b_sub; b_hatnote; b_lead; b_toc; b_sec; b_table].

Theorem wikipedia_vertical_flow_exact :
  compute_vertical_flow 64 wikipedia_article_blocks =
  [
    mkLayoutFragment 64 34 0;
    mkLayoutFragment 102 14 4;
    mkLayoutFragment 124 16 8;
    mkLayoutFragment 152 72 12;
    mkLayoutFragment 236 99 12;
    mkLayoutFragment 347 20 12;
    mkLayoutFragment 375 97 8
  ].
Proof.
  vm_compute. reflexivity.
Qed.


(******************************************************************************)
(* 6. CHROMIUM BLINK LAYOUTUNIT (26.6 FIXED-POINT) & SUBPIXEL SNAPPING        *)
(******************************************************************************)

(** In Chromium Blink, internal geometry coordinates are represented using    *)
(** [LayoutUnit], an integer fixed-point number with a 6-bit fractional part: *)
(** 1 pixel = 64 LayoutUnits (kFixedPointDenominator = 64).                   *)

Definition LayoutUnit : Type := Z.
Definition kFixedPointDenominator : Z := 64.

Definition lu_from_pixel (p : Z) : LayoutUnit :=
  p * kFixedPointDenominator.

Definition lu_to_pixel_floor (x : LayoutUnit) : Z :=
  x / kFixedPointDenominator.

Definition lu_to_pixel_round (x : LayoutUnit) : Z :=
  (x + 32) / kFixedPointDenominator.

Definition lu_to_pixel_ceil (x : LayoutUnit) : Z :=
  (x + 63) / kFixedPointDenominator.

(** In Blink, snapping a LayoutUnit size starting at a LayoutUnit location:   *)
(** snap_size(size, loc) = round(loc + size) - round(loc)                     *)
(** ensuring that adjacent abutting intervals tile with ZERO pixel gaps.      *)
Definition lu_snap_size (size loc : LayoutUnit) : Z :=
  lu_to_pixel_round (loc + size) - lu_to_pixel_round loc.

Theorem lu_snap_size_nonneg : forall size loc,
  0 <= size ->
  0 <= lu_snap_size size loc.
Proof.
  intros size loc Hsz.
  unfold lu_snap_size, lu_to_pixel_round, kFixedPointDenominator.
  assert ((loc + 32) / 64 <= (loc + size + 32) / 64).
  { apply Z.div_le_mono; lia. }
  lia.
Qed.

Lemma div_64_exact : forall a,
  (a * 64 + 32) / 64 = a.
Proof.
  intros a.
  symmetry.
  apply Z.div_unique with (r := 32); lia.
Qed.

Theorem lu_snap_size_exact_pixels : forall p l,
  lu_snap_size (lu_from_pixel p) (lu_from_pixel l) = p.
Proof.
  intros p l.
  unfold lu_snap_size, lu_from_pixel, lu_to_pixel_round, kFixedPointDenominator.
  replace (l * 64 + p * 64 + 32) with ((l + p) * 64 + 32) by ring.
  rewrite (div_64_exact (l + p)).
  rewrite (div_64_exact l).
  lia.
Qed.

Theorem lu_snap_tiling_adjacent : forall size loc,
  lu_to_pixel_round loc + lu_snap_size size loc = lu_to_pixel_round (loc + size).
Proof.
  intros size loc.
  unfold lu_snap_size.
  lia.
Qed.

(******************************************************************************)
(* 7. BLINK NGBlockLayoutAlgorithm SELF-COLLAPSING MARGIN PASS-THROUGH        *)
(******************************************************************************)

(** W3C CSS 2.2 §8.3.1 & Blink NGBlockLayoutAlgorithm::IsSelfCollapsing:      *)
(** A box is self-collapsing if its content height, padding, and borders     *)
(** are all zero, meaning its top and bottom margins collapse together       *)
(** without advancing the vertical block cursor.                             *)

Definition is_self_collapsing (b : BoxMetrics) : bool :=
  (bm_content_h b =? 0) &&
  (bm_p_top b =? 0) && (bm_p_bottom b =? 0) &&
  (bm_b_top b =? 0) && (bm_b_bottom b =? 0).

Definition step_vertical_flow_ng (st : FlowState) (b : BoxMetrics) : (FlowState * LayoutFragment) :=
  let (eff_pos, eff_neg) := collapse_margin_step (fs_margin_pos st) (fs_margin_neg st) (bm_m_top b) in
  if is_self_collapsing b then
    let (next_pos, next_neg) := collapse_margin_step eff_pos eff_neg (bm_m_bottom b) in
    let collapsed_margin := margin_strut_sum eff_pos eff_neg in
    let child_y := fs_cursor_y st + collapsed_margin in
    (mkFlowState (fs_cursor_y st) next_pos next_neg,
     mkLayoutFragment child_y 0 collapsed_margin)
  else
    let collapsed_margin := margin_strut_sum eff_pos eff_neg in
    let child_y := fs_cursor_y st + collapsed_margin in
    let child_h := box_total_height b in
    let next_cursor := child_y + child_h in
    let next_pos := margin_pos_part (bm_m_bottom b) in
    let next_neg := margin_neg_part (bm_m_bottom b) in
    (mkFlowState next_cursor next_pos next_neg,
     mkLayoutFragment child_y child_h collapsed_margin).

Fixpoint compute_vertical_flow_ng_rec (st : FlowState) (boxes : list BoxMetrics) : list LayoutFragment :=
  match boxes with
  | [] => []
  | b :: rest =>
      let (st', frag) := step_vertical_flow_ng st b in
      frag :: compute_vertical_flow_ng_rec st' rest
  end.

Definition compute_vertical_flow_ng (initial_y : Z) (boxes : list BoxMetrics) : list LayoutFragment :=
  let init_st := mkFlowState initial_y 0 0 in
  compute_vertical_flow_ng_rec init_st boxes.

Theorem self_collapsing_cursor_stationary : forall st b,
  is_self_collapsing b = true ->
  let '(st', frag) := step_vertical_flow_ng st b in
  fs_cursor_y st' = fs_cursor_y st /\ frag_h frag = 0.
Proof.
  intros st b Hsc.
  unfold step_vertical_flow_ng.
  rewrite Hsc.
  destruct (collapse_margin_step (fs_margin_pos st) (fs_margin_neg st) (bm_m_top b)).
  destruct (collapse_margin_step z z0 (bm_m_bottom b)).
  simpl. split; reflexivity.
Qed.

Theorem non_self_collapsing_matches_step_vertical_flow : forall st b,
  is_self_collapsing b = false ->
  step_vertical_flow_ng st b = step_vertical_flow st b.
Proof.
  intros st b Hnsc.
  unfold step_vertical_flow_ng, step_vertical_flow.
  rewrite Hnsc.
  reflexivity.
Qed.

Theorem step_flow_ng_preserves_valid_state : forall st b,
  valid_flow_state st ->
  valid_box_metrics b ->
  let '(st', _) := step_vertical_flow_ng st b in
  valid_flow_state st'.
Proof.
  intros [cy p n] b [Hp Hn] Hb.
  unfold step_vertical_flow_ng.
  destruct (is_self_collapsing b) eqn:E.
  - unfold collapse_margin_step, valid_flow_state, margin_pos_part, margin_neg_part.
    simpl. split; lia.
  - unfold step_vertical_flow, valid_flow_state, margin_pos_part, margin_neg_part.
    destruct (collapse_margin_step p n (bm_m_top b)).
    simpl. split; [apply Z.le_max_l | apply Z.le_min_l].
Qed.

Theorem wikipedia_vertical_flow_ng_exact :
  compute_vertical_flow_ng 64 wikipedia_article_blocks =
  [
    mkLayoutFragment 64 34 0;
    mkLayoutFragment 102 14 4;
    mkLayoutFragment 124 16 8;
    mkLayoutFragment 152 72 12;
    mkLayoutFragment 236 99 12;
    mkLayoutFragment 347 20 12;
    mkLayoutFragment 375 97 8
  ].
Proof.
  vm_compute. reflexivity.
Qed.
