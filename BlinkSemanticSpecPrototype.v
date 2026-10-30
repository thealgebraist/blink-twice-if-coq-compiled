(******************************************************************************)
(* BlinkSemanticSpecPrototype.v                                               *)
(* End-to-End Formal Verification & Staged Specialization of Chromium Blink   *)
(* LayoutUnit & FlexItem::ClampSizeToMinAndMax                                *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia.
Import ListNotations.
Open Scope Z_scope.

(******************************************************************************)
(* 1. BLINK LAYOUTUNIT ARITHMETIC MODEL (26.6 Fixed-Point, 32-bit Saturating) *)
(******************************************************************************)

Definition kIntMax : Z := 2147483647.
Definition kIntMin : Z := -2147483648.
Definition kIndefiniteRaw : Z := -64. (* LayoutUnit(-1) in 26.6 fixed point *)

(* Saturating 32-bit signed clamp (models Chromium base::saturated_cast<int32_t>) *)
Definition sat32 (x : Z) : Z :=
  if x >? kIntMax then kIntMax
  else if x <? kIntMin then kIntMin
  else x.

(* Saturating addition (models LayoutUnit::operator+) *)
Definition sat_add32 (a b : Z) : Z :=
  sat32 (a + b).

Lemma sat32_bounds : forall x,
  kIntMin <= sat32 x <= kIntMax.
Proof.
  intros x. unfold sat32, kIntMax, kIntMin.
  destruct (x >? 2147483647) eqn:E1.
  - lia.
  - destruct (x <? -2147483648) eqn:E2; lia.
Qed.

(******************************************************************************)
(* 2. LAYER 1: IMPERATIVE C++ STATEMENT AST & OPERATIONAL SEMANTICS           *)
(******************************************************************************)

Record Env := mkEnv {
  env_content : Z;
  env_bp      : Z;
  env_min     : Z;
  env_max     : Z;
  env_size    : Z;
  env_out     : Z
}.

Inductive Var : Type :=
  | V_content | V_bp | V_min | V_max | V_size | V_out.

Definition env_lookup (env : Env) (x : Var) : Z :=
  match x with
  | V_content => env_content env
  | V_bp      => env_bp env
  | V_min     => env_min env
  | V_max     => env_max env
  | V_size    => env_size env
  | V_out     => env_out env
  end.

Definition env_update (env : Env) (x : Var) (v : Z) : Env :=
  match x with
  | V_content => mkEnv v (env_bp env) (env_min env) (env_max env) (env_size env) (env_out env)
  | V_bp      => mkEnv (env_content env) v (env_min env) (env_max env) (env_size env) (env_out env)
  | V_min     => mkEnv (env_content env) (env_bp env) v (env_max env) (env_size env) (env_out env)
  | V_max     => mkEnv (env_content env) (env_bp env) (env_min env) v (env_size env) (env_out env)
  | V_size    => mkEnv (env_content env) (env_bp env) (env_min env) (env_max env) v (env_out env)
  | V_out     => mkEnv (env_content env) (env_bp env) (env_min env) (env_max env) (env_size env) v
  end.

Inductive Expr : Type :=
  | EConst (n : Z)
  | EVar (x : Var)
  | ESatAdd (e1 e2 : Expr).

Fixpoint eval_expr (env : Env) (e : Expr) : Z :=
  match e with
  | EConst n => n
  | EVar x => env_lookup env x
  | ESatAdd e1 e2 => sat_add32 (eval_expr env e1) (eval_expr env e2)
  end.

Inductive Cond : Type :=
  | CEq (e1 e2 : Expr)
  | CNeq (e1 e2 : Expr)
  | CLt (e1 e2 : Expr)
  | CGt (e1 e2 : Expr).

Definition eval_cond (env : Env) (c : Cond) : bool :=
  match c with
  | CEq e1 e2  => Z.eqb (eval_expr env e1) (eval_expr env e2)
  | CNeq e1 e2 => negb (Z.eqb (eval_expr env e1) (eval_expr env e2))
  | CLt e1 e2  => Z.ltb (eval_expr env e1) (eval_expr env e2)
  | CGt e1 e2  => Z.gtb (eval_expr env e1) (eval_expr env e2)
  end.

Inductive Stmt : Type :=
  | SSkip
  | SAssign (x : Var) (e : Expr)
  | SSeq (s1 s2 : Stmt)
  | SIf (c : Cond) (s_then s_else : Stmt).

Fixpoint exec_stmt (env : Env) (s : Stmt) : Env :=
  match s with
  | SSkip => env
  | SAssign x e => env_update env x (eval_expr env e)
  | SSeq s1 s2 => exec_stmt (exec_stmt env s1) s2
  | SIf c s_then s_else =>
      if eval_cond env c then exec_stmt env s_then else exec_stmt env s_else
  end.

Definition Cpp_Blink_ClampFlexItem_AST : Stmt :=
  SSeq (SAssign V_size (ESatAdd (EVar V_content) (EVar V_bp)))
  (SSeq (SIf (CNeq (EVar V_max) (EConst kIndefiniteRaw))
             (SIf (CGt (EVar V_size) (EVar V_max)) (SAssign V_size (EVar V_max)) SSkip)
             SSkip)
  (SSeq (SIf (CNeq (EVar V_min) (EConst kIndefiniteRaw))
             (SIf (CLt (EVar V_size) (EVar V_min)) (SAssign V_size (EVar V_min)) SSkip)
             SSkip)
  (SSeq (SIf (CLt (EVar V_size) (EVar V_bp))
             (SAssign V_size (EVar V_bp))
             SSkip)
  (SSeq (SIf (CLt (EVar V_size) (EConst 0))
             (SAssign V_size (EConst 0))
             SSkip)
        (SAssign V_out (EVar V_size)))))).

Definition make_env (content bp min_s max_s : Z) : Env :=
  mkEnv content bp min_s max_s 0 0.

(******************************************************************************)
(* 3. LAYER 2: MONADIC STATE (SHALLOW EMBEDDING)                              *)
(******************************************************************************)

Record FrameState := mkFrame {
  st_content : Z;
  st_bp      : Z;
  st_min     : Z;
  st_max     : Z;
  st_size    : Z;
  st_out     : Z
}.

Definition StateM (A : Type) : Type := FrameState -> A * FrameState.

Definition M_ClampFlexItem : StateM Z := fun s0 =>
  let c  := st_content s0 in
  let bp := st_bp s0 in
  let mn := st_min s0 in
  let mx := st_max s0 in
  let s1 := sat_add32 c bp in
  let s2 := if negb (mx =? kIndefiniteRaw) then (if s1 >? mx then mx else s1) else s1 in
  let s3 := if negb (mn =? kIndefiniteRaw) then (if s2 <? mn then mn else s2) else s2 in
  let s4 := if s3 <? bp then bp else s3 in
  let s5 := if s4 <? 0 then 0 else s4 in
  (s5, mkFrame c bp mn mx s5 s5).

(******************************************************************************)
(* 4. LAYER 3: PURE GALLINA MATHEMATICAL SPECIFICATION                        *)
(******************************************************************************)

Definition clamp_upper (x max_val : Z) : Z :=
  if max_val =? kIndefiniteRaw then x else Z.min x max_val.

Definition clamp_lower (x min_val : Z) : Z :=
  if min_val =? kIndefiniteRaw then x else Z.max x min_val.

Definition Pure_ClampFlexItem (content_size border_padding min_size max_size : Z) : Z :=
  let s0 := sat_add32 content_size border_padding in
  let s1 := clamp_upper s0 max_size in
  let s2 := clamp_lower s1 min_size in
  let s3 := Z.max s2 border_padding in
  Z.max s3 0.

Lemma if_gt_is_min : forall a b,
  (if a >? b then b else a) = Z.min a b.
Proof.
  intros a b. destruct (Z.gtb_spec a b); lia.
Qed.

Lemma if_lt_is_max : forall a b,
  (if a <? b then b else a) = Z.max a b.
Proof.
  intros a b. destruct (Z.ltb_spec a b); lia.
Qed.

(******************************************************************************)
(* 5. FORMAL EQUIVALENCE & REFINEMENT THEOREMS                                *)
(******************************************************************************)

(* Theorem 1: Layer 2 (Monadic State) is equivalent to Layer 3 (Pure Gallina) *)
Theorem Layer2_to_Layer3_Equiv :
  forall content bp min_s max_s sz out,
    fst (M_ClampFlexItem (mkFrame content bp min_s max_s sz out)) =
    Pure_ClampFlexItem content bp min_s max_s.
Proof.
  intros content bp min_s max_s sz out.
  unfold M_ClampFlexItem, Pure_ClampFlexItem, clamp_upper, clamp_lower.
  simpl.
  rewrite if_gt_is_min.
  rewrite !if_lt_is_max.
  destruct (max_s =? kIndefiniteRaw); simpl;
  destruct (min_s =? kIndefiniteRaw); simpl;
  reflexivity.
Qed.

(* Theorem 2: Layer 1 (Imperative C++ AST) is equivalent to Layer 3 *)
Theorem Layer1_to_Layer3_Equiv :
  forall content bp min_s max_s,
    env_out (exec_stmt (make_env content bp min_s max_s) Cpp_Blink_ClampFlexItem_AST) =
    Pure_ClampFlexItem content bp min_s max_s.
Proof.
  intros content bp min_s max_s.
  unfold Cpp_Blink_ClampFlexItem_AST, Pure_ClampFlexItem, clamp_upper, clamp_lower.
  simpl.
  destruct (max_s =? kIndefiniteRaw) eqn:Emax; simpl;
  [| destruct (sat_add32 content bp >? max_s) eqn:Egt; simpl ];
  destruct (min_s =? kIndefiniteRaw) eqn:Emin; simpl;
  repeat (
    match goal with
    | |- context [?x <? min_s] => destruct (x <? min_s) eqn:?; simpl
    | |- context [?x <? bp] => destruct (x <? bp) eqn:?; simpl
    | |- context [?x <? 0] => destruct (x <? 0) eqn:?; simpl
    end
  );
  repeat (rewrite if_gt_is_min || rewrite if_lt_is_max);
  try lia;
  try reflexivity.
Qed.

(* Theorem 3: Simulation Refinement between Layer 1 (Imperative) and Layer 2 (State) *)
Theorem Layer1_Simulates_Layer2 :
  forall content bp min_s max_s sz out,
    env_out (exec_stmt (make_env content bp min_s max_s) Cpp_Blink_ClampFlexItem_AST) =
    fst (M_ClampFlexItem (mkFrame content bp min_s max_s sz out)).
Proof.
  intros content bp min_s max_s sz out.
  rewrite Layer1_to_Layer3_Equiv.
  rewrite Layer2_to_Layer3_Equiv.
  reflexivity.
Qed.

(******************************************************************************)
(* 6. STAGED PARAMETER SPECIALIZATION WITH PROVEN EQUIVALENCE                 *)
(******************************************************************************)

(* ========================================================================== *)
(* STAGE 1: Specialize max_size := kIndefiniteRaw (No CSS `max-width`)        *)
(* ========================================================================== *)

Definition Spec_Stage1_UnconstrainedMax (content_size border_padding min_size : Z) : Z :=
  let s0 := sat_add32 content_size border_padding in
  let s2 := if min_size =? kIndefiniteRaw then s0 else Z.max s0 min_size in
  Z.max (Z.max s2 border_padding) 0.

Theorem Stage1_Specialization_Correct :
  forall content_size border_padding min_size,
    Pure_ClampFlexItem content_size border_padding min_size kIndefiniteRaw =
    Spec_Stage1_UnconstrainedMax content_size border_padding min_size.
Proof.
  intros content_size border_padding min_size.
  unfold Pure_ClampFlexItem, Spec_Stage1_UnconstrainedMax, clamp_upper, clamp_lower.
  simpl. reflexivity.
Qed.

(* ========================================================================== *)
(* STAGE 2: Default Box Regime (min_size == 0, max_size == kIndefiniteRaw,    *)
(*          border_padding >= 0, content_size >= 0, no overflow)              *)
(* ========================================================================== *)

Definition Spec_Stage2_FastPath (content_size border_padding : Z) : Z :=
  content_size + border_padding.

Theorem Stage2_Specialization_Correct :
  forall content_size border_padding,
    0 <= content_size ->
    0 <= border_padding ->
    content_size + border_padding <= kIntMax ->
    Pure_ClampFlexItem content_size border_padding 0 kIndefiniteRaw =
    Spec_Stage2_FastPath content_size border_padding.
Proof.
  intros content_size border_padding Hc Hbp Hsum.
  rewrite Stage1_Specialization_Correct.
  unfold Spec_Stage1_UnconstrainedMax, Spec_Stage2_FastPath, sat_add32, sat32.
  unfold kIntMax, kIntMin in *.
  simpl.
  destruct (Z.gtb_spec (content_size + border_padding) 2147483647);
  destruct (Z.ltb_spec (content_size + border_padding) (-2147483648));
  lia.
Qed.

(* ========================================================================== *)
(* STAGE 3: Definite Fixed Box (min_size == max_size == fixed_len >= bp >= 0) *)
(* ========================================================================== *)

Definition Spec_Stage3_FixedBounds (fixed_len : Z) : Z :=
  fixed_len.

Theorem Stage3_Specialization_Correct :
  forall content_size border_padding fixed_len,
    0 <= border_padding ->
    border_padding <= fixed_len ->
    Pure_ClampFlexItem content_size border_padding fixed_len fixed_len =
    Spec_Stage3_FixedBounds fixed_len.
Proof.
  intros content_size border_padding fixed_len Hbp Hfixed.
  unfold Pure_ClampFlexItem, Spec_Stage3_FixedBounds, clamp_upper, clamp_lower, kIndefiniteRaw.
  assert (Hneq: (fixed_len =? -64) = false) by lia.
  rewrite Hneq.
  lia.
Qed.

(******************************************************************************)
(* 7. EXECUTABLE COQ COMPUTE TESTS (Concrete Verification Inside Coq)         *)
(******************************************************************************)

(* Test Vector 1: Normal clamping within [min=1280 (20px), max=3500 (54.6px)] *)
Compute (
  let c := 3200 in
  let bp := 640 in
  let min_s := 1280 in
  let max_s := 3500 in
  (env_out (exec_stmt (make_env c bp min_s max_s) Cpp_Blink_ClampFlexItem_AST),
   Pure_ClampFlexItem c bp min_s max_s)
).
(* Expected: (3500, 3500) *)

(* Test Vector 2: Saturation at 32-bit INT_MAX with unconstrained max (-64) *)
Compute (
  let c := 2147483600 in
  let bp := 1000 in
  let min_s := 0 in
  let max_s := kIndefiniteRaw in
  (env_out (exec_stmt (make_env c bp min_s max_s) Cpp_Blink_ClampFlexItem_AST),
   Pure_ClampFlexItem c bp min_s max_s,
   Spec_Stage1_UnconstrainedMax c bp min_s)
).
(* Expected: (2147483647, 2147483647, 2147483647) *)

(* Test Vector 3: Min overrides Max when min_size (5000) > max_size (2000) *)
Compute (
  let c := 3000 in
  let bp := 100 in
  let min_s := 5000 in
  let max_s := 2000 in
  (env_out (exec_stmt (make_env c bp min_s max_s) Cpp_Blink_ClampFlexItem_AST),
   Pure_ClampFlexItem c bp min_s max_s)
).
(* Expected: (5000, 5000) *)

(* Test Vector 4: Negative content_size clamped to border_padding / zero *)
Compute (
  let c := -5000 in
  let bp := 320 in
  let min_s := kIndefiniteRaw in
  let max_s := kIndefiniteRaw in
  (env_out (exec_stmt (make_env c bp min_s max_s) Cpp_Blink_ClampFlexItem_AST),
   Pure_ClampFlexItem c bp min_s max_s)
).
(* Expected: (320, 320) *)
