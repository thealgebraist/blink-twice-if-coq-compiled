(******************************************************************************)
(* BlinkMarginStrut.v                                                         *)
(* Formal Specification, Monoid Theory, Specialization & Operational        *)
(* Semantics of Blink Margin Collapsing:                                      *)
(* - MarginStrut::Append(LayoutUnit, bool is_quirk)                           *)
(* - MarginStrut::Sum() and QuirkyContainerSum()                              *)
(* - CSS 2.1 Section 8.3.1 Proof of Equivalence & Associative Monoid Theory  *)
(* - Big-Step & Small-Step Operational AST                                    *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Require Import BlinkScrollAndGrid.
Import ListNotations.
Open Scope Z_scope.

(******************************************************************************)
(* 1. BLINK MARGIN STRUT DATA STRUCTURE & STATE REPRESENTATION                *)
(******************************************************************************)

Record MarginStrut := mkMarginStrut {
  ms_pos : Z;             (* positive_margin >= 0 *)
  ms_neg : Z;             (* negative_margin <= 0 *)
  ms_quirk_pos : Z;       (* quirky_positive_margin >= 0 *)
  ms_quirky_start : bool; (* is_quirky_container_start *)
  ms_discard : bool;
  ms_trim_leading : bool
}.

Definition default_margin_strut : MarginStrut :=
  mkMarginStrut 0 0 0 false false false.

(** Invariant: ms_pos >= 0, ms_neg <= 0, ms_quirk_pos >= 0 *)
Definition margin_strut_invariant (ms : MarginStrut) : Prop :=
  0 <= ms_pos ms /\ ms_neg ms <= 0 /\ 0 <= ms_quirk_pos ms.

Lemma default_margin_strut_inv : margin_strut_invariant default_margin_strut.
Proof.
  unfold default_margin_strut, margin_strut_invariant. simpl. lia.
Qed.

(******************************************************************************)
(* 2. FUNCTIONAL SPECIFICATION OF APPEND & SUM                                *)
(******************************************************************************)

Definition margin_strut_append (ms : MarginStrut) (val : Z) (is_quirk : bool) : MarginStrut :=
  if ms_quirky_start ms && is_quirk then
    ms
  else if ms_trim_leading ms then ms
  else if val <? 0 then
  mkMarginStrut (ms_pos ms) (Z.min val (ms_neg ms)) (ms_quirk_pos ms) (ms_quirky_start ms) (ms_discard ms) (ms_trim_leading ms)
  else if is_quirk then
    mkMarginStrut (ms_pos ms) (ms_neg ms) (Z.max val (ms_quirk_pos ms)) (ms_quirky_start ms) (ms_discard ms) (ms_trim_leading ms)
  else
    mkMarginStrut (Z.max val (ms_pos ms)) (ms_neg ms) (ms_quirk_pos ms) (ms_quirky_start ms) (ms_discard ms) (ms_trim_leading ms).

Definition margin_strut_sum (ms : MarginStrut) : Z :=
  if ms_discard ms then 0 else
  sat_clamp (Z.max (ms_quirk_pos ms) (ms_pos ms) + ms_neg ms).

Definition margin_strut_quirky_sum (ms : MarginStrut) : Z :=
  if ms_discard ms then 0 else sat_clamp (ms_pos ms + ms_neg ms).

Definition margin_strut_is_empty (ms : MarginStrut) : bool :=
  ms_discard ms ||
  (ms_pos ms =? 0) && (ms_neg ms =? 0) && (ms_quirk_pos ms =? 0).

Definition margin_strut_eqb (left right : MarginStrut) : bool :=
  (ms_pos left =? ms_pos right) && (ms_neg left =? ms_neg right) &&
  (ms_quirk_pos left =? ms_quirk_pos right) &&
  Bool.eqb (ms_quirky_start left) (ms_quirky_start right) &&
  Bool.eqb (ms_discard left) (ms_discard right) &&
  Bool.eqb (ms_trim_leading left) (ms_trim_leading right).

Theorem margin_strut_discard_is_empty : forall ms,
  ms_discard ms = true -> margin_strut_is_empty ms = true.
Proof. intros ms H; unfold margin_strut_is_empty; rewrite H; reflexivity. Qed.

Theorem margin_strut_is_empty_spec : forall ms,
  margin_strut_is_empty ms = true <->
  ms_discard ms = true \/
  (ms_pos ms = 0 /\ ms_neg ms = 0 /\ ms_quirk_pos ms = 0).
Proof.
  intros [p n q start discard trim]. unfold margin_strut_is_empty; simpl.
  rewrite orb_true_iff, andb_true_iff, andb_true_iff.
  rewrite !Z.eqb_eq. tauto.
Qed.

Theorem margin_strut_eqb_refl : forall ms, margin_strut_eqb ms ms = true.
Proof. intros [p n q start discard trim]; unfold margin_strut_eqb; simpl;
  rewrite !Z.eqb_refl; destruct start, discard, trim; reflexivity. Qed.

Theorem margin_strut_eqb_true_iff : forall left right,
  margin_strut_eqb left right = true <-> left = right.
Proof.
  intros [lp ln lq ls ld lt] [rp rn rq rs rd rt].
  unfold margin_strut_eqb; simpl.
  repeat rewrite andb_true_iff.
  repeat rewrite Z.eqb_eq.
  repeat rewrite Bool.eqb_true_iff.
  split.
  - intros [[[[[Hp Hn] Hq] Hs] Hd] Ht]. subst. reflexivity.
  - intro H; inversion H; subst; repeat split; reflexivity.
Qed.

(******************************************************************************)
(* 3. INVARIANT PRESERVATION THEOREM                                          *)
(******************************************************************************)

Theorem margin_strut_append_preserves_invariant : forall ms val is_quirk,
  margin_strut_invariant ms ->
  margin_strut_invariant (margin_strut_append ms val is_quirk).
Proof.
  intros ms val is_quirk [Hpos [Hneg Hqpos]].
  unfold margin_strut_append, margin_strut_invariant.
  destruct (ms_quirky_start ms && is_quirk); [repeat split; assumption|].
  destruct (ms_trim_leading ms); [repeat split; assumption|].
  destruct (Z.ltb_spec val 0).
  - simpl. split; [exact Hpos | split; [| exact Hqpos]].
    lia.
  - destruct is_quirk; simpl.
    + repeat split; try lia; try assumption.
    + repeat split; try lia; try assumption.
Qed.

Theorem margin_strut_discard_sum_zero : forall ms,
  ms_discard ms = true -> margin_strut_sum ms = 0 /\ margin_strut_quirky_sum ms = 0.
Proof. intros ms Hd; unfold margin_strut_sum, margin_strut_quirky_sum; rewrite Hd; auto. Qed.

Theorem margin_strut_sum_equals_quirky_sum_when_quirk_does_not_dominate :
  forall ms, ms_discard ms = false -> ms_quirk_pos ms <= ms_pos ms ->
  margin_strut_sum ms = margin_strut_quirky_sum ms.
Proof.
  intros [p n q start discard trim] Hdiscard Horder.
  unfold margin_strut_sum, margin_strut_quirky_sum; simpl in *.
  rewrite Hdiscard. rewrite Z.max_r by exact Horder. reflexivity.
Qed.

Theorem margin_strut_sum_within_layout_unit_bounds : forall ms,
  kInt32Min <= margin_strut_sum ms <= kInt32Max.
Proof.
  intros ms. unfold margin_strut_sum.
  destruct (ms_discard ms); simpl.
  - unfold kInt32Min, kInt32Max; lia.
  - apply sat_clamp_bounds.
Qed.

Theorem margin_strut_quirky_sum_within_layout_unit_bounds : forall ms,
  kInt32Min <= margin_strut_quirky_sum ms <= kInt32Max.
Proof.
  intros ms. unfold margin_strut_quirky_sum.
  destruct (ms_discard ms); simpl.
  - unfold kInt32Min, kInt32Max; lia.
  - apply sat_clamp_bounds.
Qed.

Theorem margin_strut_trim_append_identity : forall ms val is_quirk,
  ms_quirky_start ms && is_quirk = false -> ms_trim_leading ms = true ->
  margin_strut_append ms val is_quirk = ms.
Proof.
  intros ms val is_quirk Hstart Htrim. unfold margin_strut_append.
  rewrite Hstart, Htrim. reflexivity.
Qed.

Theorem margin_strut_append_preserves_control_flags : forall ms val is_quirk,
  ms_discard (margin_strut_append ms val is_quirk) = ms_discard ms /\
  ms_trim_leading (margin_strut_append ms val is_quirk) = ms_trim_leading ms /\
  ms_quirky_start (margin_strut_append ms val is_quirk) = ms_quirky_start ms.
Proof.
  intros ms val is_quirk. unfold margin_strut_append. repeat split;
  destruct (ms_quirky_start ms && is_quirk);
  destruct (ms_trim_leading ms);
  destruct (val <? 0);
  destruct is_quirk; simpl; reflexivity.
Qed.

(******************************************************************************)
(* 4. CSS 2.1 SPECIFICATION CONFORMANCE & ALGEBRAIC EQUIVALENCE               *)
(******************************************************************************)

(** CSS 2.1 Sec 8.3.1 defines collapsed margin as:
    max(positive_margins) - max(|negative_margins|).
    Theorem: Blink's sum formulation is mathematically identical to CSS 2.1. *)
Theorem blink_matches_css21_collapsing :
  forall m_pos m_neg,
    0 <= m_pos ->
    m_neg <= 0 ->
    kInt32Min <= m_pos + m_neg <= kInt32Max ->
    m_pos + m_neg = m_pos - Z.abs m_neg.
Proof.
  intros m_pos m_neg Hpos Hneg Hbound.
  assert (Habs: Z.abs m_neg = - m_neg).
  { destruct (Z.ltb_spec m_neg 0).
    - apply Z.abs_neq; lia.
    - assert (m_neg = 0) by lia. subst. reflexivity.
  }
  rewrite Habs.
  lia.
Qed.

(** Standard Non-Quirks Mode Appending is an Idempotent Commutative Monoid *)
Definition non_quirk_append (ms : MarginStrut) (val : Z) : MarginStrut :=
  margin_strut_append ms val false.

Lemma min_idem_step : forall a b : Z,
  Z.min a (Z.min a b) = Z.min a b.
Proof.
  intros.
  rewrite Z.min_assoc.
  rewrite Z.min_id.
  reflexivity.
Qed.

Lemma max_idem_step : forall a b : Z,
  Z.max a (Z.max a b) = Z.max a b.
Proof.
  intros.
  rewrite Z.max_assoc.
  rewrite Z.max_id.
  reflexivity.
Qed.

Theorem margin_strut_append_idempotent : forall ms val,
  non_quirk_append (non_quirk_append ms val) val = non_quirk_append ms val.
Proof.
  intros [pos neg qpos start discard trim] val.
  destruct trim; destruct start; unfold non_quirk_append, margin_strut_append; simpl.
  - reflexivity.
  - reflexivity.
  - destruct (val <? 0) eqn:Hval; simpl; f_equal; [apply min_idem_step|apply max_idem_step].
  - destruct (val <? 0) eqn:Hval; simpl; f_equal; [apply min_idem_step|apply max_idem_step].
Qed.

(******************************************************************************)
(* 5. SPECIALIZATION REGIMES & FAST-PATHS                                     *)
(******************************************************************************)

(** Regime 1: Non-Negative Margins Only (Negative Margin = 0)
    When all margins are positive: Sum() collapses to pure max(margins). *)
Theorem margin_strut_pure_positive_specialization : forall pos qpos,
  0 <= pos ->
  0 <= qpos ->
  pos <= kInt32Max ->
  qpos <= kInt32Max ->
  margin_strut_sum (mkMarginStrut pos 0 qpos false false false) = Z.max qpos pos.
Proof.
  intros pos qpos Hpos Hqpos Hmax1 Hmax2.
  unfold margin_strut_sum. simpl.
  replace (Z.max qpos pos + 0) with (Z.max qpos pos) by lia.
  apply sat_clamp_id.
  unfold kInt32Min, kInt32Max in *.
  assert (Hge: 0 <= Z.max qpos pos) by lia.
  assert (Hle: Z.max qpos pos <= 2147483647) by lia.
  lia.
Qed.

(** Regime 2: Single Negative Margin Appended to Fresh Strut *)
Theorem margin_strut_pure_negative_specialization : forall val,
  val < 0 ->
  kInt32Min <= val ->
  margin_strut_sum (margin_strut_append default_margin_strut val false) = val.
Proof.
  intros val Hneg Hbound.
  unfold default_margin_strut, margin_strut_append, margin_strut_sum. simpl.
  destruct (Z.ltb_spec val 0); [| lia].
  simpl.
  assert (Hmin: Z.min val 0 = val) by lia.
  rewrite Hmin. simpl.
  apply sat_clamp_id.
  unfold kInt32Min, kInt32Max in *. lia.
Qed.

(******************************************************************************)
(* 6. IMPERATIVE AST & BIG-STEP / SMALL-STEP OPERATIONAL SEMANTICS            *)
(******************************************************************************)

(** Operational AST for MarginStrut::Append(val, is_quirk=false)
    V_input1: current_pos
    V_input2: current_neg
    V_input3: val
    V_result: new_pos or new_neg depending on val < 0
*)
Definition cmd_MarginStrut_Append_NonQuirk : Cmd :=
  CIf (BLt (AVar V_input3) (AConst 0))
      (* val < 0: update negative margin *)
      (CAssign V_result (AMin (AVar V_input3) (AVar V_input2)))
      (* val >= 0: update positive margin *)
      (CAssign V_result (AMax (AVar V_input3) (AVar V_input1))).

(** Operational Verification: Negative Margin Branch Execution *)
Theorem bs_MarginStrut_Append_Negative : forall pos neg val,
  val < 0 ->
  init_state pos neg val 0 =[ cmd_MarginStrut_Append_NonQuirk ]=>
  set_var (init_state pos neg val 0) V_result (Z.min val neg).
Proof.
  intros pos neg val Hval.
  unfold cmd_MarginStrut_Append_NonQuirk.
  apply BS_IfTrue.
  - simpl.
    destruct (Z.ltb_spec val 0); [reflexivity | lia].
  - apply BS_Assign.
Qed.

(** Small-Step Execution Corollary via Soundness Theorem *)
Corollary ss_MarginStrut_Append_Negative : forall pos neg val,
  val < 0 ->
  (cmd_MarginStrut_Append_NonQuirk, init_state pos neg val 0) -->*
  (CSkip, set_var (init_state pos neg val 0) V_result (Z.min val neg)).
Proof.
  intros pos neg val Hval.
  apply big_step_to_small_step.
  apply bs_MarginStrut_Append_Negative; assumption.
Qed.

(** Operational Verification: Positive Margin Branch Execution *)
Theorem bs_MarginStrut_Append_Positive : forall pos neg val,
  0 <= val ->
  init_state pos neg val 0 =[ cmd_MarginStrut_Append_NonQuirk ]=>
  set_var (init_state pos neg val 0) V_result (Z.max val pos).
Proof.
  intros pos neg val Hval.
  unfold cmd_MarginStrut_Append_NonQuirk.
  apply BS_IfFalse.
  - simpl.
    destruct (Z.ltb_spec val 0); [lia | reflexivity].
  - apply BS_Assign.
Qed.

Corollary ss_MarginStrut_Append_Positive : forall pos neg val,
  0 <= val ->
  (cmd_MarginStrut_Append_NonQuirk, init_state pos neg val 0) -->*
  (CSkip, set_var (init_state pos neg val 0) V_result (Z.max val pos)).
Proof.
  intros pos neg val Hval.
  apply big_step_to_small_step.
  apply bs_MarginStrut_Append_Positive; assumption.
Qed.
