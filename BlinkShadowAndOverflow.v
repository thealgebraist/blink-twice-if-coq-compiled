(******************************************************************************)
(* BlinkShadowAndOverflow.v                                                   *)
(* Formal Specification, Specialization & Operational Semantics of            *)
(* Visual Overflow Geometry & Shadow Outset Calculations in Blink:            *)
(* - ShadowData::RectOutsets / Single Shadow Outset Expansion                 *)
(* - Multi-Shadow Bounding-Box Union Accumulation                             *)
(* - Saturated LayoutUnit Outset Application to PhysicalRect                 *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Import ListNotations.
Open Scope Z_scope.

(******************************************************************************)
(* 1. SHADOW OUTSETS DATA STRUCTURE & SATURATING ARITHMETIC                   *)
(******************************************************************************)

Record Outsets := mkOutsets {
  out_top : Z;
  out_right : Z;
  out_bottom : Z;
  out_left : Z
}.

Record Rect := mkRect {
  r_x : Z;
  r_y : Z;
  r_w : Z;
  r_h : Z
}.

(** Compute 1-directional shadow expansion:
    spread + blur (+/-) offset, bounded below by 0 *)
Definition compute_shadow_outset_1d (spread blur offset : Z) (is_positive_edge : bool) : Z :=
  let extent := sat_clamp (spread + blur) in
  let delta := if is_positive_edge then sat_clamp (extent + offset)
               else sat_clamp (extent - offset) in
  Z.max 0 delta.

(** Single shadow outsets (Normal vs Inset) *)
Definition shadow_outsets (style : Z) (spread blur off_x off_y : Z) : Outsets :=
  if style =? 1 then (* Inset = 1: contained inside the box, visual outset = 0 *)
    mkOutsets 0 0 0 0
  else
    mkOutsets
      (compute_shadow_outset_1d spread blur off_y false) (* top: extent - off_y *)
      (compute_shadow_outset_1d spread blur off_x true)  (* right: extent + off_x *)
      (compute_shadow_outset_1d spread blur off_y true)  (* bottom: extent + off_y *)
      (compute_shadow_outset_1d spread blur off_x false) (* left: extent - off_x *).

(** Component-wise maximum union of two outsets *)
Definition union_outsets (o1 o2 : Outsets) : Outsets :=
  mkOutsets
    (Z.max (out_top o1) (out_top o2))
    (Z.max (out_right o1) (out_right o2))
    (Z.max (out_bottom o1) (out_bottom o2))
    (Z.max (out_left o1) (out_left o2)).

(** Apply outsets to a PhysicalRect with exact saturating arithmetic *)
Definition apply_outsets_to_rect (r : Rect) (o : Outsets) : Rect :=
  mkRect
    (sat_clamp (r_x r - out_left o))
    (sat_clamp (r_y r - out_top o))
    (sat_clamp (r_w r + out_left o + out_right o))
    (sat_clamp (r_h r + out_top o + out_bottom o)).

(******************************************************************************)
(* 2. SPECIALIZATION THEOREMS: ZERO-OFFSET & SYMMETRIC SHADOWS               *)
(******************************************************************************)

(** Regime 1: Inset shadow produces zero visual expansion unconditionally *)
Theorem shadow_inset_zero_expansion : forall spread blur off_x off_y,
  shadow_outsets 1 spread blur off_x off_y = mkOutsets 0 0 0 0.
Proof.
  intros. unfold shadow_outsets. simpl. reflexivity.
Qed.

(** Regime 2: Symmetric Zero-Offset Outset Shadow *)
Theorem shadow_zero_offset_symmetric : forall spread blur,
  0 <= spread ->
  0 <= blur ->
  spread + blur <= kInt32Max ->
  shadow_outsets 0 spread blur 0 0 =
    mkOutsets (spread + blur) (spread + blur) (spread + blur) (spread + blur).
Proof.
  intros spread blur Hsp Hbl Hbound.
  unfold shadow_outsets, compute_shadow_outset_1d.
  assert (Hext: sat_clamp (spread + blur) = spread + blur).
  { apply sat_clamp_id. unfold kInt32Min. lia. }
  rewrite Hext.
  assert (Hadd0: sat_clamp (spread + blur + 0) = spread + blur).
  { replace (spread + blur + 0) with (spread + blur) by lia. exact Hext. }
  assert (Hsub0: sat_clamp (spread + blur - 0) = spread + blur).
  { replace (spread + blur - 0) with (spread + blur) by lia. exact Hext. }
  rewrite Hadd0, Hsub0.
  assert (Hmax: Z.max 0 (spread + blur) = spread + blur) by lia.
  rewrite !Hmax.
  reflexivity.
Qed.

(******************************************************************************)
(* 3. MONOTONICITY & GEOMETRIC INVARIANTS                                     *)
(******************************************************************************)

(** Shadow expansion never shrinks the original bounding box *)
Theorem shadow_outset_nonnegative : forall style spread blur off_x off_y,
  let o := shadow_outsets style spread blur off_x off_y in
  0 <= out_top o /\ 0 <= out_right o /\ 0 <= out_bottom o /\ 0 <= out_left o.
Proof.
  intros style spread blur off_x off_y o.
  unfold o, shadow_outsets.
  destruct (style =? 1); simpl; [lia |].
  unfold compute_shadow_outset_1d.
  repeat split; apply Z.le_max_l.
Qed.

(** Outset union is commutative and idempotent *)
Theorem union_outsets_comm : forall o1 o2,
  union_outsets o1 o2 = union_outsets o2 o1.
Proof.
  intros [t1 r1 b1 l1] [t2 r2 b2 l2].
  unfold union_outsets. simpl.
  f_equal; apply Z.max_comm.
Qed.

Theorem union_outsets_idem : forall o,
  union_outsets o o = o.
Proof.
  intros [t r b l].
  unfold union_outsets. simpl.
  f_equal; apply Z.max_id.
Qed.

(******************************************************************************)
(* 4. IMPERATIVE AST EMBEDDING & OPERATIONAL SEMANTICS                        *)
(******************************************************************************)

(** AST for single shadow horizontal expansion:
    V_input1: spread
    V_input2: blur
    V_input3: offset_x
    V_result: max(0, sat_clamp(sat_clamp(spread + blur) + offset_x))
*)
Definition cmd_ShadowHorizontalOutset : Cmd :=
  CSeq (CAssign V_tmp1 (ASatAdd (AVar V_input1) (AVar V_input2))) (* extent = spread + blur *)
  (CSeq (CAssign V_tmp2 (ASatAdd (AVar V_tmp1) (AVar V_input3))) (* delta = extent + offset_x *)
        (CAssign V_result (AMax (AConst 0) (AVar V_tmp2)))).

(** Big-Step Operational Execution for Shadow Horizontal Outset *)
Theorem bs_ShadowHorizontal_Exec : forall spread blur off_x,
  init_state spread blur off_x 0 =[ cmd_ShadowHorizontalOutset ]=>
  set_var
    (set_var
       (set_var (init_state spread blur off_x 0) V_tmp1 (sat_clamp (spread + blur)))
       V_tmp2 (sat_clamp (sat_clamp (spread + blur) + off_x)))
    V_result (Z.max 0 (sat_clamp (sat_clamp (spread + blur) + off_x))).
Proof.
  intros spread blur off_x.
  unfold cmd_ShadowHorizontalOutset.
  eapply BS_Seq.
  - apply BS_Assign.
  - eapply BS_Seq.
    + apply BS_Assign.
    + apply BS_Assign.
Qed.

(** Small-Step Execution Corollary via Soundness Theorem *)
Corollary ss_ShadowHorizontal_Exec : forall spread blur off_x,
  (cmd_ShadowHorizontalOutset, init_state spread blur off_x 0) -->*
  (CSkip,
   set_var
     (set_var
        (set_var (init_state spread blur off_x 0) V_tmp1 (sat_clamp (spread + blur)))
        V_tmp2 (sat_clamp (sat_clamp (spread + blur) + off_x)))
     V_result (Z.max 0 (sat_clamp (sat_clamp (spread + blur) + off_x)))).
Proof.
  intros spread blur off_x.
  apply big_step_to_small_step.
  apply bs_ShadowHorizontal_Exec.
Qed.

(** Specialized Result Value Equality under In-Bounds Zero-Offset *)
Theorem bs_ShadowHorizontal_ZeroOffset_Result : forall spread blur,
  0 <= spread ->
  0 <= blur ->
  spread + blur <= kInt32Max ->
  Z.max 0 (sat_clamp (sat_clamp (spread + blur) + 0)) = spread + blur.
Proof.
  intros spread blur Hsp Hbl Hbound.
  assert (Hext: sat_clamp (spread + blur) = spread + blur).
  { apply sat_clamp_id. unfold kInt32Min. lia. }
  rewrite Hext.
  assert (Hdelta: sat_clamp (spread + blur + 0) = spread + blur).
  { replace (spread + blur + 0) with (spread + blur) by lia. exact Hext. }
  rewrite Hdelta.
  lia.
Qed.
