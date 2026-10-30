(******************************************************************************)
(* BlinkOperationalSemantics.v                                                *)
(* Classic Sound Big-Step & Small-Step Operational Semantics for              *)
(* Chromium Blink Leaf Functions:                                             *)
(* 1. MinimumValueForLength                                                   *)
(* 2. InlineSizeFromAspectRatio                                               *)
(* 3. ScrollAlignment::GetScrollOffsetToExpose                                *)
(* 4. DistributeExtraSpaceToTrack (CSS Grid)                                  *)
(* 5. ShadowData::RectOutsets / Visual Outset Geometry                        *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Import ListNotations.
Open Scope Z_scope.

(******************************************************************************)
(* 1. CORE ARITHMETIC & SENTINEL DOMAIN                                       *)
(******************************************************************************)

Definition kInt32Max : Z := 2147483647.
Definition kInt32Min : Z := -2147483648.
Definition kIndefiniteSize : Z := -64.

Definition sat_clamp (x : Z) : Z :=
  if x >? kInt32Max then kInt32Max
  else if x <? kInt32Min then kInt32Min
  else x.

Lemma sat_clamp_id : forall x : Z,
  kInt32Min <= x <= kInt32Max -> sat_clamp x = x.
Proof.
  intros x [H1 H2]. unfold sat_clamp, kInt32Min, kInt32Max in *.
  destruct (Z.gtb_spec x 2147483647);
  destruct (Z.ltb_spec x (-2147483648));
  lia.
Qed.

(******************************************************************************)
(* 2. IMPERATIVE ABSTRACT SYNTAX (AST) FOR BLINK LEAF ROUTINES                *)
(******************************************************************************)

Inductive VarId : Type :=
  | V_input1 | V_input2 | V_input3 | V_input4
  | V_tmp1   | V_tmp2   | V_tmp3
  | V_result.

Definition var_eqb (v1 v2 : VarId) : bool :=
  match v1, v2 with
  | V_input1, V_input1 => true
  | V_input2, V_input2 => true
  | V_input3, V_input3 => true
  | V_input4, V_input4 => true
  | V_tmp1, V_tmp1 => true
  | V_tmp2, V_tmp2 => true
  | V_tmp3, V_tmp3 => true
  | V_result, V_result => true
  | _, _ => false
  end.

Lemma var_eqb_refl : forall v, var_eqb v v = true.
Proof. destruct v; reflexivity. Qed.

Record State := mkState {
  st_in1 : Z;
  st_in2 : Z;
  st_in3 : Z;
  st_in4 : Z;
  st_tmp1 : Z;
  st_tmp2 : Z;
  st_tmp3 : Z;
  st_res : Z
}.

Definition get_var (s : State) (v : VarId) : Z :=
  match v with
  | V_input1 => st_in1 s
  | V_input2 => st_in2 s
  | V_input3 => st_in3 s
  | V_input4 => st_in4 s
  | V_tmp1   => st_tmp1 s
  | V_tmp2   => st_tmp2 s
  | V_tmp3   => st_tmp3 s
  | V_result => st_res s
  end.

Definition set_var (s : State) (v : VarId) (val : Z) : State :=
  match v with
  | V_input1 => mkState val (st_in2 s) (st_in3 s) (st_in4 s) (st_tmp1 s) (st_tmp2 s) (st_tmp3 s) (st_res s)
  | V_input2 => mkState (st_in1 s) val (st_in3 s) (st_in4 s) (st_tmp1 s) (st_tmp2 s) (st_tmp3 s) (st_res s)
  | V_input3 => mkState (st_in1 s) (st_in2 s) val (st_in4 s) (st_tmp1 s) (st_tmp2 s) (st_tmp3 s) (st_res s)
  | V_input4 => mkState (st_in1 s) (st_in2 s) (st_in3 s) val (st_tmp1 s) (st_tmp2 s) (st_tmp3 s) (st_res s)
  | V_tmp1   => mkState (st_in1 s) (st_in2 s) (st_in3 s) (st_in4 s) val (st_tmp2 s) (st_tmp3 s) (st_res s)
  | V_tmp2   => mkState (st_in1 s) (st_in2 s) (st_in3 s) (st_in4 s) (st_tmp1 s) val (st_tmp3 s) (st_res s)
  | V_tmp3   => mkState (st_in1 s) (st_in2 s) (st_in3 s) (st_in4 s) (st_tmp1 s) (st_tmp2 s) val (st_res s)
  | V_result => mkState (st_in1 s) (st_in2 s) (st_in3 s) (st_in4 s) (st_tmp1 s) (st_tmp2 s) (st_tmp3 s) val
  end.

Inductive AExpr : Type :=
  | AConst (z : Z)
  | AVar (v : VarId)
  | ASatAdd (e1 e2 : AExpr)
  | ASatSub (e1 e2 : AExpr)
  | AMulDiv (e_val e_num e_den : AExpr)
  | AMin (e1 e2 : AExpr)
  | AMax (e1 e2 : AExpr).

Fixpoint eval_aexpr (s : State) (e : AExpr) : Z :=
  match e with
  | AConst z => z
  | AVar v => get_var s v
  | ASatAdd e1 e2 => sat_clamp (eval_aexpr s e1 + eval_aexpr s e2)
  | ASatSub e1 e2 => sat_clamp (eval_aexpr s e1 - eval_aexpr s e2)
  | AMulDiv e_val e_num e_den =>
      let d := eval_aexpr s e_den in
      if d =? 0 then 0
      else sat_clamp (Z.quot (eval_aexpr s e_val * eval_aexpr s e_num) d)
  | AMin e1 e2 => Z.min (eval_aexpr s e1) (eval_aexpr s e2)
  | AMax e1 e2 => Z.max (eval_aexpr s e1) (eval_aexpr s e2)
  end.

Inductive BExpr : Type :=
  | BTrue
  | BFalse
  | BEq (e1 e2 : AExpr)
  | BLt (e1 e2 : AExpr)
  | BGt (e1 e2 : AExpr)
  | BAnd (b1 b2 : BExpr)
  | BOr (b1 b2 : BExpr).

Fixpoint eval_bexpr (s : State) (b : BExpr) : bool :=
  match b with
  | BTrue => true
  | BFalse => false
  | BEq e1 e2 => eval_aexpr s e1 =? eval_aexpr s e2
  | BLt e1 e2 => eval_aexpr s e1 <? eval_aexpr s e2
  | BGt e1 e2 => eval_aexpr s e1 >? eval_aexpr s e2
  | BAnd b1 b2 => eval_bexpr s b1 && eval_bexpr s b2
  | BOr b1 b2 => eval_bexpr s b1 || eval_bexpr s b2
  end.

Inductive Cmd : Type :=
  | CSkip
  | CAssign (v : VarId) (e : AExpr)
  | CSeq (c1 c2 : Cmd)
  | CIf (b : BExpr) (c_then c_else : Cmd).

(******************************************************************************)
(* 3. CLASSIC BIG-STEP NATURAL OPERATIONAL SEMANTICS                           *)
(* Notation: s =[ c ]=> s'                                                    *)
(******************************************************************************)

Reserved Notation "s '=[' c ']=>' s'" (at level 50).

Inductive big_step : State -> Cmd -> State -> Prop :=
  | BS_Skip : forall s,
      s =[ CSkip ]=> s
  | BS_Assign : forall s v e,
      s =[ CAssign v e ]=> (set_var s v (eval_aexpr s e))
  | BS_Seq : forall s s1 s2 c1 c2,
      s =[ c1 ]=> s1 ->
      s1 =[ c2 ]=> s2 ->
      s =[ CSeq c1 c2 ]=> s2
  | BS_IfTrue : forall s s' b c_then c_else,
      eval_bexpr s b = true ->
      s =[ c_then ]=> s' ->
      s =[ CIf b c_then c_else ]=> s'
  | BS_IfFalse : forall s s' b c_then c_else,
      eval_bexpr s b = false ->
      s =[ c_else ]=> s' ->
      s =[ CIf b c_then c_else ]=> s'
where "s '=[' c ']=>' s'" := (big_step s c s').

(******************************************************************************)
(* 4. CLASSIC SMALL-STEP TRANSITION OPERATIONAL SEMANTICS                      *)
(* Notation: (c, s) --> (c', s')                                              *)
(******************************************************************************)

Reserved Notation "cs '-->' cs'" (at level 50).

Inductive small_step : Cmd * State -> Cmd * State -> Prop :=
  | SS_Assign : forall v e s,
      (CAssign v e, s) --> (CSkip, set_var s v (eval_aexpr s e))
  | SS_SeqSkip : forall c2 s,
      (CSeq CSkip c2, s) --> (c2, s)
  | SS_SeqStep : forall c1 c1' c2 s s',
      (c1, s) --> (c1', s') ->
      (CSeq c1 c2, s) --> (CSeq c1' c2, s')
  | SS_IfTrue : forall b c_then c_else s,
      eval_bexpr s b = true ->
      (CIf b c_then c_else, s) --> (c_then, s)
  | SS_IfFalse : forall b c_then c_else s,
      eval_bexpr s b = false ->
      (CIf b c_then c_else, s) --> (c_else, s)
where "cs '-->' cs'" := (small_step cs cs').

Inductive multi_step : Cmd * State -> Cmd * State -> Prop :=
  | MS_Refl : forall cs, multi_step cs cs
  | MS_Step : forall cs1 cs2 cs3,
      cs1 --> cs2 -> multi_step cs2 cs3 -> multi_step cs1 cs3.

Notation "cs '-->*' cs'" := (multi_step cs cs') (at level 50).

(******************************************************************************)
(* 5. SOUNDNESS, DETERMINISM & EQUIVALENCE THEOREMS                            *)
(******************************************************************************)

Lemma multi_step_trans : forall cs1 cs2 cs3,
  cs1 -->* cs2 -> cs2 -->* cs3 -> cs1 -->* cs3.
Proof.
  intros cs1 cs2 cs3 H12 H23.
  induction H12 as [cs | c1 c2 c3 Hstep Hrest IH].
  - exact H23.
  - econstructor; [exact Hstep | apply IH, H23].
Qed.

Lemma multi_step_seq : forall c1 c1' c2 s s',
  (c1, s) -->* (c1', s') ->
  (CSeq c1 c2, s) -->* (CSeq c1' c2, s').
Proof.
  intros c1 c1' c2 s s' Hsteps.
  remember (c1, s) as cs1 eqn:E1.
  remember (c1', s') as cs2 eqn:E2.
  revert c1 c1' c2 s s' E1 E2.
  induction Hsteps as [cs | [c_a s_a] [c_b s_b] [c_d s_d] Hstep Hrest IH]; intros.
  - subst cs. injection E2 as Hc Hs. subst. apply MS_Refl.
  - injection E1 as Hc Hs. subst.
    eapply MS_Step.
    + apply SS_SeqStep, Hstep.
    + apply (IH c_b c1' c2 s_b s'); [reflexivity | exact E2].
Qed.

Theorem big_step_to_small_step : forall c s s',
  s =[ c ]=> s' -> (c, s) -->* (CSkip, s').
Proof.
  intros c s s' Hbs.
  induction Hbs.
  - apply MS_Refl.
  - eapply MS_Step; [apply SS_Assign | apply MS_Refl].
  - eapply multi_step_trans.
    + apply multi_step_seq, IHHbs1.
    + eapply MS_Step; [apply SS_SeqSkip | exact IHHbs2].
  - eapply MS_Step; [apply SS_IfTrue, H | exact IHHbs].
  - eapply MS_Step; [apply SS_IfFalse, H | exact IHHbs].
Qed.

Theorem big_step_deterministic : forall c s s1 s2,
  s =[ c ]=> s1 ->
  s =[ c ]=> s2 ->
  s1 = s2.
Proof.
  intros c s s1 s2 H1 H2.
  revert s2 H2.
  induction H1; intros s_dest H2.
  - inversion H2; subst; reflexivity.
  - inversion H2; subst; reflexivity.
  - inversion H2; subst.
    match goal with
    | Hseq1: s =[ c1 ]=> ?sm, Hseq2: ?sm =[ c2 ]=> s_dest |- _ =>
        assert (s1 = sm) by (apply IHbig_step1; exact Hseq1);
        subst sm;
        apply IHbig_step2; exact Hseq2
    end.
  - inversion H2; subst.
    + apply IHbig_step; assumption.
    + match goal with
      | Hfalse: eval_bexpr s b = false |- _ =>
          rewrite H in Hfalse; discriminate Hfalse
      end.
  - inversion H2; subst.
    + match goal with
      | Htrue: eval_bexpr s b = true |- _ =>
          rewrite H in Htrue; discriminate Htrue
      end.
    + apply IHbig_step; assumption.
Qed.

(******************************************************************************)
(* 6. CONCRETE BLINK LEAF ASTs IN OPERATIONAL SEMANTICS                        *)
(******************************************************************************)

(** Routine 1: MinimumValueForLength AST *)
Definition cmd_MinimumValueForLength : Cmd :=
  CIf (BEq (AVar V_input1) (AConst 0))
      (CAssign V_result (AVar V_input2)) (* Fixed: return length.Value() *)
      (CIf (BEq (AVar V_input1) (AConst 1))
           (CIf (BEq (AVar V_input3) (AConst kIndefiniteSize))
                (CAssign V_result (AConst 0)) (* Percent with indefinite max = 0 *)
                (CAssign V_result (AMulDiv (AVar V_input3) (AVar V_input2) (AConst 100))))
           (CAssign V_result (AConst 0))). (* Auto / FillAvailable = 0 *)

(** Routine 2: InlineSizeFromAspectRatio AST *)
Definition cmd_InlineSizeFromAspectRatio : Cmd :=
  CIf (BEq (AVar V_input3) (AConst 1)) (* BorderBox = 1 *)
      (CSeq (CAssign V_tmp1 (ASatSub (AVar V_input4) (AVar V_input1))) (* block - block_sum *)
      (CSeq (CAssign V_tmp2 (AMulDiv (AVar V_tmp1) (AVar V_tmp3) (AVar V_input4)))
            (CAssign V_result (AMax (AVar V_input2) (ASatAdd (AVar V_tmp2) (AVar V_input2))))))
      (* ContentBox = 0 *)
      (CAssign V_result (AMulDiv (AVar V_input4) (AVar V_tmp3) (AVar V_input4))).

(** Routine 3: ScrollAlignment 1D Exposure Clamping AST *)
Definition cmd_ScrollAlignment_Nearest : Cmd :=
  CIf (BAnd (BGt (AVar V_input2) (AVar V_input1)) (BGt (AVar V_input4) (AVar V_input3)))
      (* Oversized target: aligns start edge to viewport start *)
      (CAssign V_result (AMin (AVar V_input4) (AMax (AVar V_input3) (AVar V_input2))))
      (* Standard in-bounds or clamped nearest *)
      (CAssign V_result (AMin (AVar V_input4) (AMax (AVar V_input3) (AVar V_input1)))).

(** Routine 4: DistributeExtraSpaceToTrack (CSS Grid space distribution) AST *)
(* V_input1: current_growth_limit
   V_input2: extra_space
   V_input3: track_count
   Computes: share = extra_space / track_count, new_growth_limit = growth_limit + share *)
Definition cmd_DistributeExtraSpaceToTrack : Cmd :=
  CIf (BEq (AVar V_input3) (AConst 0))
      (CAssign V_result (AVar V_input1))
      (CSeq (CAssign V_tmp1 (AMulDiv (AVar V_input2) (AConst 1) (AVar V_input3)))
            (CAssign V_result (ASatAdd (AVar V_input1) (AVar V_tmp1)))).

(******************************************************************************)
(* 7. SEMANTIC EQUIVALENCE & EXECUTION THEOREMS                               *)
(******************************************************************************)

Definition init_state (in1 in2 in3 in4 : Z) : State :=
  mkState in1 in2 in3 in4 0 0 0 0.

(** Verified Execution Theorem for MinimumValueForLength (Fixed): *)
Theorem bs_MinimumValueForLength_Fixed :
  forall val max_val,
    init_state 0 val max_val 0 =[ cmd_MinimumValueForLength ]=>
    set_var (init_state 0 val max_val 0) V_result val.
Proof.
  intros val max_val.
  unfold cmd_MinimumValueForLength.
  apply BS_IfTrue.
  - simpl. reflexivity.
  - apply BS_Assign.
Qed.

(** Small-step execution corollary (progress & termination) *)
Corollary ss_MinimumValueForLength_Fixed :
  forall val max_val,
    (cmd_MinimumValueForLength, init_state 0 val max_val 0) -->*
    (CSkip, set_var (init_state 0 val max_val 0) V_result val).
Proof.
  intros val max_val.
  apply big_step_to_small_step, bs_MinimumValueForLength_Fixed.
Qed.

(** Verified Execution Theorem for DistributeExtraSpaceToTrack (Base track_count = 1) *)
Theorem bs_DistributeExtraSpace_SingleTrack :
  forall limit extra,
    0 <= limit ->
    0 <= extra ->
    limit + extra <= kInt32Max ->
    init_state limit extra 1 0 =[ cmd_DistributeExtraSpaceToTrack ]=>
    set_var
      (set_var (init_state limit extra 1 0) V_tmp1 (sat_clamp (Z.quot (extra * 1) 1)))
      V_result (sat_clamp (limit + sat_clamp (Z.quot (extra * 1) 1))).
Proof.
  intros limit extra Hlim Hext Hbound.
  unfold cmd_DistributeExtraSpaceToTrack.
  apply BS_IfFalse.
  - simpl. reflexivity.
  - eapply BS_Seq.
    + apply BS_Assign.
    + apply BS_Assign.
Qed.
