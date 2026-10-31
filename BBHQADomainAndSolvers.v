(******************************************************************************)
(*                                                                            *)
(*                     BBH LLM QA DOMAIN ONTOLOGY & SOLVERS                   *)
(*                                                                            *)
(*  Pure ADT & Multi-Paradigm Solver Formalization of 8 BIG-Bench Hard (BBH)  *)
(*  LLM Evaluation Domains in Rocq/Coq 9.3.0:                                 *)
(*    1. 2D Spatial Navigation       (Pose2D Turtle vs SE(2,Z) Matrix Monoid) *)
(*    2. Epistemic Web of Lies       (Forward Env vs Backward F_2 XOR Graph)  *)
(*    3. Tracking Shuffled Objects   (Forward Sim vs Weakest-Precond Pullback)*)
(*    4. Logical Order Deduction     (S_3 Model Enum vs Arc-Pruned CSP Masks) *)
(*    5. Taxonomic Object Counting   (Relational Filter-Sum vs 5-Bin MapRed)  *)
(*    6. Propositional Boolean Logic (AST Denotation vs De Morgan NNF + VM)   *)
(*    7. Multi-Step Ring Arithmetic  (AST Denotation vs Postfix RPN Stack VM) *)
(*    8. Temporal Interval Sequences (Hourly Bitmap vs Symbolic Disjointness) *)
(*                                                                            *)
(*  STRICT INVARIANT: This module does NOT import String or Ascii.            *)
(*  Every domain entity, constraint, question, answer, and computation engine *)
(*  is a pure algebraic data type (0 strings, 0 admits, 0 axioms).            *)
(*                                                                            *)
(******************************************************************************)

From Stdlib Require Import ZArith.
From Stdlib Require Import List.
From Stdlib Require Import Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

(* ========================================================================= *)
(* SECTION 1: SHARED MULTIPLE-CHOICE & SOLVER PARADIGM ADTS                  *)
(* ========================================================================= *)

Inductive Option3 : Type :=
  | Opt3_A
  | Opt3_B
  | Opt3_C.

Inductive Option4 : Type :=
  | Opt4_A
  | Opt4_B
  | Opt4_C
  | Opt4_D.

Record ChoiceTriple (A : Type) : Type := {
  ct_A : A;
  ct_B : A;
  ct_C : A
}.
Arguments ct_A {A}.
Arguments ct_B {A}.
Arguments ct_C {A}.

Record ChoiceQuad (A : Type) : Type := {
  cq_A : A;
  cq_B : A;
  cq_C : A;
  cq_D : A
}.
Arguments cq_A {A}.
Arguments cq_B {A}.
Arguments cq_C {A}.
Arguments cq_D {A}.

(** Two mathematically distinct computation paradigms across all 8 domains:
    - Mode_Operational: stateful step-by-step simulation, recursive AST
      evaluation, exhaustive enumeration, or discrete hourly sweep.
    - Mode_Algebraic: group/monoid homomorphisms (SE(2,Z), S_3 pullback, F_2
      parity), CSP domain-bound propagation, MapReduce histograms, bytecode
      stack machines, and symbolic interval algebra. *)
Inductive SolverMode : Type :=
  | Mode_Operational
  | Mode_Algebraic.

Definition option3_eqb (o1 o2 : Option3) : bool :=
  match o1, o2 with
  | Opt3_A, Opt3_A | Opt3_B, Opt3_B | Opt3_C, Opt3_C => true
  | _, _ => false
  end.

Definition option4_eqb (o1 o2 : Option4) : bool :=
  match o1, o2 with
  | Opt4_A, Opt4_A | Opt4_B, Opt4_B | Opt4_C, Opt4_C | Opt4_D, Opt4_D => true
  | _, _ => false
  end.

(* ========================================================================= *)
(* SECTION 2: DOMAIN 1 — 2D SPATIAL NAVIGATION (TURTLE VS SE(2, Z) MONOID)   *)
(* ========================================================================= *)

Inductive CardinalDir : Type :=
  | Dir_North
  | Dir_East
  | Dir_South
  | Dir_West.

Inductive RelMoveDir : Type :=
  | Move_Forward
  | Move_Backward
  | Move_Left
  | Move_Right.

Inductive NavInstruction : Type :=
  | Nav_AlwaysFaceForward
  | Nav_TurnLeft
  | Nav_TurnRight
  | Nav_TurnAround
  | Nav_Step (dir : RelMoveDir) (steps : Z).

Record Pose2D : Type := {
  pose_x   : Z;
  pose_y   : Z;
  pose_dir : CardinalDir
}.

Definition local_step_vec (rel : RelMoveDir) (n : Z) : Z * Z :=
  match rel with
  | Move_Forward  => (0, n)
  | Move_Backward => (0, -n)
  | Move_Left     => (-n, 0)
  | Move_Right    => (n, 0)
  end.

(** Method 1A (Operational): Imperative 4-heading turtle state machine. *)
Definition turtle_step (p : Pose2D) (ins : NavInstruction) : Pose2D :=
  match ins with
  | Nav_AlwaysFaceForward => p
  | Nav_TurnLeft =>
      let nd := match p.(pose_dir) with
                | Dir_North => Dir_West | Dir_West => Dir_South
                | Dir_South => Dir_East | Dir_East => Dir_North
                end in
      {| pose_x := p.(pose_x); pose_y := p.(pose_y); pose_dir := nd |}
  | Nav_TurnRight =>
      let nd := match p.(pose_dir) with
                | Dir_North => Dir_East | Dir_East => Dir_South
                | Dir_South => Dir_West | Dir_West => Dir_North
                end in
      {| pose_x := p.(pose_x); pose_y := p.(pose_y); pose_dir := nd |}
  | Nav_TurnAround =>
      let nd := match p.(pose_dir) with
                | Dir_North => Dir_South | Dir_South => Dir_North
                | Dir_East  => Dir_West  | Dir_West  => Dir_East
                end in
      {| pose_x := p.(pose_x); pose_y := p.(pose_y); pose_dir := nd |}
  | Nav_Step rel n =>
      let '(lx, ly) := local_step_vec rel n in
      let '(wx, wy) :=
        match p.(pose_dir) with
        | Dir_North => (lx, ly)
        | Dir_East  => (ly, -lx)
        | Dir_South => (-lx, -ly)
        | Dir_West  => (-ly, lx)
        end in
      {| pose_x := p.(pose_x) + wx; pose_y := p.(pose_y) + wy; pose_dir := p.(pose_dir) |}
  end.

Definition nav_solve_operational (prog : list NavInstruction) : bool :=
  let end_p := fold_left turtle_step prog {| pose_x := 0; pose_y := 0; pose_dir := Dir_North |} in
  (end_p.(pose_x) =? 0) && (end_p.(pose_y) =? 0).

(** Method 1B (Algebraic): Discrete 2D Special Euclidean Group SE(2, Z) = Z^2 |x Z_4
    homomorphism. Each instruction maps to an affine matrix (R, t) composed via
    semidirect product (R1, t1) * (R2, t2) = (R1 * R2, t1 + R1 * t2). *)
Record SE2Transform : Type := {
  r00 : Z; r01 : Z;
  r10 : Z; r11 : Z;
  tx  : Z; ty  : Z
}.

Definition se2_id : SE2Transform :=
  {| r00 := 1; r01 := 0; r10 := 0; r11 := 1; tx := 0; ty := 0 |}.

Definition se2_compose (a b : SE2Transform) : SE2Transform :=
  {| r00 := a.(r00) * b.(r00) + a.(r01) * b.(r10);
     r01 := a.(r00) * b.(r01) + a.(r01) * b.(r11);
     r10 := a.(r10) * b.(r00) + a.(r11) * b.(r10);
     r11 := a.(r10) * b.(r01) + a.(r11) * b.(r11);
     tx  := a.(tx) + a.(r00) * b.(tx) + a.(r01) * b.(ty);
     ty  := a.(ty) + a.(r10) * b.(tx) + a.(r11) * b.(ty) |}.

Definition se2_of_instr (ins : NavInstruction) : SE2Transform :=
  match ins with
  | Nav_AlwaysFaceForward => se2_id
  | Nav_TurnLeft   => {| r00 := 0; r01 := -1; r10 := 1; r11 := 0; tx := 0; ty := 0 |}
  | Nav_TurnRight  => {| r00 := 0; r01 := 1; r10 := -1; r11 := 0; tx := 0; ty := 0 |}
  | Nav_TurnAround => {| r00 := -1; r01 := 0; r10 := 0; r11 := -1; tx := 0; ty := 0 |}
  | Nav_Step rel n =>
      let '(lx, ly) := local_step_vec rel n in
      {| r00 := 1; r01 := 0; r10 := 0; r11 := 1; tx := lx; ty := ly |}
  end.

Fixpoint se2_eval_prog (prog : list NavInstruction) : SE2Transform :=
  match prog with
  | [] => se2_id
  | ins :: rest => se2_compose (se2_of_instr ins) (se2_eval_prog rest)
  end.

Definition nav_solve_algebraic (prog : list NavInstruction) : bool :=
  let tf := se2_eval_prog prog in
  (tf.(tx) =? 0) && (tf.(ty) =? 0).

Definition dir_basis (d : CardinalDir) : Z * Z * Z * Z :=
  match d with
  | Dir_North => (1, 0, 0, 1)
  | Dir_East  => (0, 1, -1, 0)
  | Dir_South => (-1, 0, 0, -1)
  | Dir_West  => (0, -1, 1, 0)
  end.

Lemma turtle_se2_frame_invariant :
  forall (prog : list NavInstruction) (p : Pose2D),
    let end_p := fold_left turtle_step prog p in
    let tf := se2_eval_prog prog in
    let '(b00, b01, b10, b11) := dir_basis p.(pose_dir) in
    end_p.(pose_x) = p.(pose_x) + b00 * tf.(tx) + b01 * tf.(ty) /\
    end_p.(pose_y) = p.(pose_y) + b10 * tf.(tx) + b11 * tf.(ty).
Proof.
  induction prog as [| ins rest IH]; intros p; simpl.
  - destruct (pose_dir p); simpl; split; lia.
  - specialize (IH (turtle_step p ins)).
    destruct p as [px py pdir].
    destruct pdir, ins; try destruct dir;
      cbn [turtle_step se2_eval_prog se2_of_instr se2_compose se2_id local_step_vec
           dir_basis pose_dir pose_x pose_y r00 r01 r10 r11 tx ty] in *;
      destruct IH as [IHx IHy]; split; rewrite ?IHx, ?IHy; lia.
Qed.

Theorem nav_operational_eq_algebraic :
  forall prog : list NavInstruction,
    nav_solve_operational prog = nav_solve_algebraic prog.
Proof.
  intros prog.
  unfold nav_solve_operational, nav_solve_algebraic.
  pose proof (turtle_se2_frame_invariant prog {| pose_x := 0; pose_y := 0; pose_dir := Dir_North |}) as [Hx Hy].
  cbn [dir_basis pose_dir pose_x pose_y] in Hx, Hy.
  assert (Ex : (fold_left turtle_step prog {| pose_x := 0; pose_y := 0; pose_dir := Dir_North |}).(pose_x) =
               (se2_eval_prog prog).(tx)) by lia.
  assert (Ey : (fold_left turtle_step prog {| pose_x := 0; pose_y := 0; pose_dir := Dir_North |}).(pose_y) =
               (se2_eval_prog prog).(ty)) by lia.
  rewrite Ex, Ey. reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 3: DOMAIN 2 — EPISTEMIC WEB OF LIES (FORWARD ENV VS F_2 XOR)      *)
(* ========================================================================= *)

Inductive SpeakerADT : Type :=
  | Sp_Alejandro | Sp_Alexis | Sp_Amberly | Sp_Andree | Sp_Antwan
  | Sp_Audrie | Sp_Bernita | Sp_Christie | Sp_Conception | Sp_Crista
  | Sp_Dallas | Sp_Delbert | Sp_Delfina | Sp_Elanor | Sp_Fidel
  | Sp_Fletcher | Sp_Gwenn | Sp_Helene | Sp_Inga | Sp_Jamey
  | Sp_Jaymie | Sp_Jerry | Sp_Jim | Sp_Ka | Sp_Kandi
  | Sp_Kristian | Sp_Leda | Sp_Lorine | Sp_Maybelle | Sp_Michael
  | Sp_Michaela | Sp_Millicent | Sp_Millie | Sp_Osvaldo | Sp_Phoebe
  | Sp_Rashida | Sp_Raymond | Sp_Ryan | Sp_Sal | Sp_Shalonda
  | Sp_Shaunda | Sp_Shenna | Sp_Sherrie | Sp_Sima | Sp_Tamika
  | Sp_Teressa | Sp_Vernell | Sp_Vina | Sp_Willian | Sp_Yoland.

Definition speaker_code (s : SpeakerADT) : Z :=
  match s with
  | Sp_Alejandro => 0 | Sp_Alexis => 1 | Sp_Amberly => 2 | Sp_Andree => 3 | Sp_Antwan => 4
  | Sp_Audrie => 5 | Sp_Bernita => 6 | Sp_Christie => 7 | Sp_Conception => 8 | Sp_Crista => 9
  | Sp_Dallas => 10 | Sp_Delbert => 11 | Sp_Delfina => 12 | Sp_Elanor => 13 | Sp_Fidel => 14
  | Sp_Fletcher => 15 | Sp_Gwenn => 16 | Sp_Helene => 17 | Sp_Inga => 18 | Sp_Jamey => 19
  | Sp_Jaymie => 20 | Sp_Jerry => 21 | Sp_Jim => 22 | Sp_Ka => 23 | Sp_Kandi => 24
  | Sp_Kristian => 25 | Sp_Leda => 26 | Sp_Lorine => 27 | Sp_Maybelle => 28 | Sp_Michael => 29
  | Sp_Michaela => 30 | Sp_Millicent => 31 | Sp_Millie => 32 | Sp_Osvaldo => 33 | Sp_Phoebe => 34
  | Sp_Rashida => 35 | Sp_Raymond => 36 | Sp_Ryan => 37 | Sp_Sal => 38 | Sp_Shalonda => 39
  | Sp_Shaunda => 40 | Sp_Shenna => 41 | Sp_Sherrie => 42 | Sp_Sima => 43 | Sp_Tamika => 44
  | Sp_Teressa => 45 | Sp_Vernell => 46 | Sp_Vina => 47 | Sp_Willian => 48 | Sp_Yoland => 49
  end.

Definition speaker_eqb (s1 s2 : SpeakerADT) : bool :=
  Z.eqb (speaker_code s1) (speaker_code s2).

Inductive TruthPolarity : Type :=
  | Pol_Truth
  | Pol_Lies.

Inductive TestimonyClause : Type :=
  | TC_Fact (who : SpeakerADT) (pol : TruthPolarity)
  | TC_Says (speaker : SpeakerADT) (subject : SpeakerADT) (pol : TruthPolarity).

Definition polarity_bool (p : TruthPolarity) : bool :=
  match p with Pol_Truth => true | Pol_Lies => false end.

Definition opt_xor (flip : bool) (ob : option bool) : option bool :=
  match ob with
  | Some b => Some (xorb flip b)
  | None   => None
  end.

(** Method 2A (Operational): Forward epistemic state-map propagation. *)
Definition wol_step_env (env : SpeakerADT -> option bool) (c : TestimonyClause)
  : SpeakerADT -> option bool :=
  match c with
  | TC_Fact s pol =>
      fun x => if speaker_eqb x s then Some (polarity_bool pol) else env x
  | TC_Says a b pol =>
      fun x => if speaker_eqb x a then opt_xor (negb (polarity_bool pol)) (env b) else env x
  end.

Definition wol_solve_operational (kb : list TestimonyClause) (target : SpeakerADT) : option bool :=
  fold_left wol_step_env kb (fun _ => None) target.

(** Method 2B (Algebraic): Backward goal-directed GF(2) / XOR parity pullback
    along the reverse testimony graph without materializing intermediate environments. *)
Fixpoint wol_backward_xor (rkb : list TestimonyClause) (target : SpeakerADT) (flip : bool)
  : option bool :=
  match rkb with
  | [] => None
  | TC_Fact s pol :: rest =>
      if speaker_eqb target s then Some (xorb flip (polarity_bool pol))
      else wol_backward_xor rest target flip
  | TC_Says a b pol :: rest =>
      if speaker_eqb target a then
        wol_backward_xor rest b (xorb flip (negb (polarity_bool pol)))
      else wol_backward_xor rest target flip
  end.

Definition wol_solve_algebraic (kb : list TestimonyClause) (target : SpeakerADT) : option bool :=
  wol_backward_xor (rev kb) target false.

Lemma wol_backward_eq_fold_right :
  forall (rkb : list TestimonyClause) (target : SpeakerADT) (flip : bool),
    wol_backward_xor rkb target flip =
    opt_xor flip (fold_right (fun c env => wol_step_env env c) (fun _ => None) rkb target).
Proof.
  induction rkb as [| [s pol | a b pol] rest IH]; intros target flip; simpl.
  - reflexivity.
  - destruct (speaker_eqb target s); [reflexivity | apply IH].
  - destruct (speaker_eqb target a).
    + rewrite IH.
      destruct (fold_right (fun c env => wol_step_env env c) (fun _ => None) rest b) as [vb |];
        simpl; [f_equal; destruct flip, pol, vb; reflexivity | reflexivity].
    + apply IH.
Qed.

Theorem wol_operational_eq_algebraic :
  forall (kb : list TestimonyClause) (target : SpeakerADT),
    wol_solve_operational kb target = wol_solve_algebraic kb target.
Proof.
  intros kb target.
  unfold wol_solve_operational, wol_solve_algebraic.
  rewrite wol_backward_eq_fold_right.
  change wol_step_env with (fun (x : SpeakerADT -> option bool) (y : TestimonyClause) => wol_step_env x y) at 1.
  rewrite (fold_left_rev_right (fun (y : TestimonyClause) (x : SpeakerADT -> option bool) => wol_step_env x y)).
  assert (Hx0 : forall o : option bool, opt_xor false o = o) by (intros [[|] |]; reflexivity).
  rewrite Hx0. reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 4: DOMAIN 3 — TRACKING SHUFFLED OBJECTS (SIM VS WP PULLBACK)      *)
(* ========================================================================= *)

Inductive SwapScenario : Type :=
  | Scen_Books
  | Scen_Balls
  | Scen_Gifts
  | Scen_DancePartners
  | Scen_SoccerPositions.

Inductive SwapAgent : Type :=
  | Ag_Alice
  | Ag_Bob
  | Ag_Claire.

Inductive HeldObjectADT : Type :=
  | HO_Catch22 | HO_FellowshipOfTheRing | HO_Frankenstein | HO_GreatGatsby
  | HO_Helga | HO_HoundOfTheBaskervilles | HO_Izzi | HO_Jamie | HO_Karl
  | HO_Lola | HO_Lolita | HO_Melissa | HO_MobyDick | HO_Odyssey | HO_Ophelia
  | HO_Patrick | HO_Pearl | HO_Rodrigo | HO_Sam | HO_Ulysses
  | HO_Benchwarmer | HO_BlackBall | HO_BlueBall | HO_BluePresent
  | HO_BrownBall | HO_BrownPresent | HO_CenterMidfielder | HO_Cheerleader
  | HO_Fullback | HO_Goalkeeper | HO_GreenBall | HO_GreenPresent
  | HO_LeftMidfielder | HO_LeftWinger | HO_OrangeBall | HO_PinkBall
  | HO_PurpleBall | HO_PurplePresent | HO_RedBall | HO_RedPresent
  | HO_RightMidfielder | HO_RightWinger | HO_Striker | HO_WhiteBall
  | HO_WhitePresent | HO_YellowBall | HO_YellowPresent.

Definition held_object_code (h : HeldObjectADT) : Z :=
  match h with
  | HO_Catch22 => 0 | HO_FellowshipOfTheRing => 1 | HO_Frankenstein => 2 | HO_GreatGatsby => 3
  | HO_Helga => 4 | HO_HoundOfTheBaskervilles => 5 | HO_Izzi => 6 | HO_Jamie => 7 | HO_Karl => 8
  | HO_Lola => 9 | HO_Lolita => 10 | HO_Melissa => 11 | HO_MobyDick => 12 | HO_Odyssey => 13 | HO_Ophelia => 14
  | HO_Patrick => 15 | HO_Pearl => 16 | HO_Rodrigo => 17 | HO_Sam => 18 | HO_Ulysses => 19
  | HO_Benchwarmer => 20 | HO_BlackBall => 21 | HO_BlueBall => 22 | HO_BluePresent => 23
  | HO_BrownBall => 24 | HO_BrownPresent => 25 | HO_CenterMidfielder => 26 | HO_Cheerleader => 27
  | HO_Fullback => 28 | HO_Goalkeeper => 29 | HO_GreenBall => 30 | HO_GreenPresent => 31
  | HO_LeftMidfielder => 32 | HO_LeftWinger => 33 | HO_OrangeBall => 34 | HO_PinkBall => 35
  | HO_PurpleBall => 36 | HO_PurplePresent => 37 | HO_RedBall => 38 | HO_RedPresent => 39
  | HO_RightMidfielder => 40 | HO_RightWinger => 41 | HO_Striker => 42 | HO_WhiteBall => 43
  | HO_WhitePresent => 44 | HO_YellowBall => 45 | HO_YellowPresent => 46
  end.

Definition held_object_eqb (a b : HeldObjectADT) : bool :=
  Z.eqb (held_object_code a) (held_object_code b).

Record InitialHolding : Type := {
  hold_alice  : HeldObjectADT;
  hold_bob    : HeldObjectADT;
  hold_claire : HeldObjectADT
}.

Record TranspositionSwap : Type := {
  swap_lhs : SwapAgent;
  swap_rhs : SwapAgent
}.

Definition get_holding (h : InitialHolding) (ag : SwapAgent) : HeldObjectADT :=
  match ag with
  | Ag_Alice  => h.(hold_alice)
  | Ag_Bob    => h.(hold_bob)
  | Ag_Claire => h.(hold_claire)
  end.

(** Method 3A (Operational): Forward mutable world simulation across swaps. *)
Definition apply_swap_holding (h : InitialHolding) (sw : TranspositionSwap) : InitialHolding :=
  match sw.(swap_lhs), sw.(swap_rhs) with
  | Ag_Alice, Ag_Bob | Ag_Bob, Ag_Alice =>
      {| hold_alice := h.(hold_bob); hold_bob := h.(hold_alice); hold_claire := h.(hold_claire) |}
  | Ag_Alice, Ag_Claire | Ag_Claire, Ag_Alice =>
      {| hold_alice := h.(hold_claire); hold_bob := h.(hold_bob); hold_claire := h.(hold_alice) |}
  | Ag_Bob, Ag_Claire | Ag_Claire, Ag_Bob =>
      {| hold_alice := h.(hold_alice); hold_bob := h.(hold_claire); hold_claire := h.(hold_bob) |}
  | _, _ => h
  end.

Definition swap_eval_operational (init : InitialHolding) (swaps : list TranspositionSwap)
                                 (target : SwapAgent) : HeldObjectADT :=
  get_holding (fold_left apply_swap_holding swaps init) target.

(** Method 3B (Algebraic): Weakest-Precondition / Adjoint S_3 Transposition Pullback.
    Pulls ONLY the queried agent index backward through the swap group without
    allocating or mutating item holdings. *)
Definition transpose_agent (sw : TranspositionSwap) (ag : SwapAgent) : SwapAgent :=
  match sw.(swap_lhs), sw.(swap_rhs), ag with
  | Ag_Alice, Ag_Bob, Ag_Alice | Ag_Bob, Ag_Alice, Ag_Alice => Ag_Bob
  | Ag_Alice, Ag_Bob, Ag_Bob   | Ag_Bob, Ag_Alice, Ag_Bob   => Ag_Alice
  | Ag_Alice, Ag_Claire, Ag_Alice  | Ag_Claire, Ag_Alice, Ag_Alice  => Ag_Claire
  | Ag_Alice, Ag_Claire, Ag_Claire | Ag_Claire, Ag_Alice, Ag_Claire => Ag_Alice
  | Ag_Bob, Ag_Claire, Ag_Bob    | Ag_Claire, Ag_Bob, Ag_Bob    => Ag_Claire
  | Ag_Bob, Ag_Claire, Ag_Claire | Ag_Claire, Ag_Bob, Ag_Claire => Ag_Bob
  | _, _, _ => ag
  end.

Definition swap_eval_algebraic (init : InitialHolding) (swaps : list TranspositionSwap)
                               (target : SwapAgent) : HeldObjectADT :=
  get_holding init (fold_right transpose_agent target swaps).

Definition match_held_choice (item : HeldObjectADT) (opts : ChoiceTriple HeldObjectADT)
  : option (Option3 * HeldObjectADT) :=
  if held_object_eqb item opts.(ct_A) then Some (Opt3_A, item)
  else if held_object_eqb item opts.(ct_B) then Some (Opt3_B, item)
  else if held_object_eqb item opts.(ct_C) then Some (Opt3_C, item)
  else None.

Lemma swap_step_adjoint :
  forall (h : InitialHolding) (sw : TranspositionSwap) (ag : SwapAgent),
    get_holding (apply_swap_holding h sw) ag = get_holding h (transpose_agent sw ag).
Proof.
  intros [ha hb hc] [a1 a2] ag.
  destruct a1, a2, ag; reflexivity.
Qed.

Theorem swap_operational_eq_algebraic :
  forall (swaps : list TranspositionSwap) (init : InitialHolding) (target : SwapAgent),
    swap_eval_operational init swaps target = swap_eval_algebraic init swaps target.
Proof.
  unfold swap_eval_operational, swap_eval_algebraic.
  induction swaps as [| sw rest IH]; intros init target; simpl.
  - reflexivity.
  - rewrite IH. apply swap_step_adjoint.
Qed.

(** Conservation Law: Every sequence of swaps preserves the sum of object codes
    (no item is ever created, destroyed, or overwritten). *)
Theorem swap_item_conservation :
  forall (swaps : list TranspositionSwap) (init : InitialHolding),
    let fin := fold_left apply_swap_holding swaps init in
    held_object_code fin.(hold_alice) + held_object_code fin.(hold_bob) + held_object_code fin.(hold_claire) =
    held_object_code init.(hold_alice) + held_object_code init.(hold_bob) + held_object_code init.(hold_claire).
Proof.
  induction swaps as [| [a1 a2] rest IH]; intros [ha hb hc]; simpl.
  - reflexivity.
  - rewrite IH. destruct a1, a2; simpl; lia.
Qed.

(* ========================================================================= *)
(* SECTION 5: DOMAIN 4 — LOGICAL DEDUCTION (S_3 ENUM VS ARC-PRUNED CSP)      *)
(* ========================================================================= *)

Inductive OrderScenario : Type :=
  | Ord_BirdsBranch
  | Ord_AntiqueCars
  | Ord_FruitPrices
  | Ord_ShelfBooks
  | Ord_GolfTournament.

Inductive RankedObjectADT : Type :=
  | RO_Ada | RO_Amy | RO_Ana | RO_Dan | RO_Eli | RO_Eve | RO_Joe | RO_Mel | RO_Mya | RO_Rob
  | RO_Apples | RO_BlackBook | RO_BlueBook | RO_BlueJay | RO_BrownBook | RO_Bus
  | RO_Cantaloupes | RO_Cardinal | RO_Convertible | RO_Crow | RO_Falcon | RO_GrayBook
  | RO_GreenBook | RO_Hatchback | RO_Hawk | RO_Hummingbird | RO_Kiwis | RO_Limousine
  | RO_Loquats | RO_Mangoes | RO_Minivan | RO_Motorcyle | RO_OrangeBook | RO_Oranges
  | RO_Owl | RO_Peaches | RO_Pears | RO_Plums | RO_PurpleBook | RO_Quail | RO_Raven
  | RO_RedBook | RO_Robin | RO_Sedan | RO_StationWagon | RO_Tractor | RO_Truck
  | RO_Watermelons | RO_WhiteBook | RO_YellowBook.

Definition ranked_object_code (r : RankedObjectADT) : Z :=
  match r with
  | RO_Ada => 0 | RO_Amy => 1 | RO_Ana => 2 | RO_Dan => 3 | RO_Eli => 4
  | RO_Eve => 5 | RO_Joe => 6 | RO_Mel => 7 | RO_Mya => 8 | RO_Rob => 9
  | RO_Apples => 10 | RO_BlackBook => 11 | RO_BlueBook => 12 | RO_BlueJay => 13 | RO_BrownBook => 14
  | RO_Bus => 15 | RO_Cantaloupes => 16 | RO_Cardinal => 17 | RO_Convertible => 18 | RO_Crow => 19
  | RO_Falcon => 20 | RO_GrayBook => 21 | RO_GreenBook => 22 | RO_Hatchback => 23 | RO_Hawk => 24
  | RO_Hummingbird => 25 | RO_Kiwis => 26 | RO_Limousine => 27 | RO_Loquats => 28 | RO_Mangoes => 29
  | RO_Minivan => 30 | RO_Motorcyle => 31 | RO_OrangeBook => 32 | RO_Oranges => 33 | RO_Owl => 34
  | RO_Peaches => 35 | RO_Pears => 36 | RO_Plums => 37 | RO_PurpleBook => 38 | RO_Quail => 39
  | RO_Raven => 40 | RO_RedBook => 41 | RO_Robin => 42 | RO_Sedan => 43 | RO_StationWagon => 44
  | RO_Tractor => 45 | RO_Truck => 46 | RO_Watermelons => 47 | RO_WhiteBook => 48 | RO_YellowBook => 49
  end.

Definition ranked_object_eqb (a b : RankedObjectADT) : bool :=
  Z.eqb (ranked_object_code a) (ranked_object_code b).

Inductive RankSlot : Type :=
  | Slot_First   (* Rank 0: leftmost / newest / cheapest / 1st *)
  | Slot_Middle  (* Rank 1: second *)
  | Slot_Last.   (* Rank 2: rightmost / oldest / most expensive / 3rd *)

Inductive OrderConstraint : Type :=
  | OC_Before  (lhs rhs : RankedObjectADT)
  | OC_After   (lhs rhs : RankedObjectADT)
  | OC_PinSlot (ent : RankedObjectADT) (slot : RankSlot).

Record EntityTriple : Type := {
  et_0 : RankedObjectADT;
  et_1 : RankedObjectADT;
  et_2 : RankedObjectADT
}.

Inductive EntityIdx : Type := EIdx_0 | EIdx_1 | EIdx_2.
Inductive Perm3 : Type := P012 | P021 | P102 | P120 | P201 | P210.

Definition all_perms3 : list Perm3 := [P012; P021; P102; P120; P201; P210].

Definition lookup_entity_idx (dom : EntityTriple) (o : RankedObjectADT) : option EntityIdx :=
  if ranked_object_eqb o dom.(et_0) then Some EIdx_0
  else if ranked_object_eqb o dom.(et_1) then Some EIdx_1
  else if ranked_object_eqb o dom.(et_2) then Some EIdx_2
  else None.

Definition perm_rank (p : Perm3) (i : EntityIdx) : Z :=
  match p, i with
  | P012, EIdx_0 => 0 | P012, EIdx_1 => 1 | P012, EIdx_2 => 2
  | P021, EIdx_0 => 0 | P021, EIdx_1 => 2 | P021, EIdx_2 => 1
  | P102, EIdx_0 => 1 | P102, EIdx_1 => 0 | P102, EIdx_2 => 2
  | P120, EIdx_0 => 1 | P120, EIdx_1 => 2 | P120, EIdx_2 => 0
  | P201, EIdx_0 => 2 | P201, EIdx_1 => 0 | P201, EIdx_2 => 1
  | P210, EIdx_0 => 2 | P210, EIdx_1 => 1 | P210, EIdx_2 => 0
  end.

Definition slot_rank (s : RankSlot) : Z :=
  match s with Slot_First => 0 | Slot_Middle => 1 | Slot_Last => 2 end.

Definition check_order_constraint (dom : EntityTriple) (p : Perm3) (c : OrderConstraint) : bool :=
  match c with
  | OC_Before a b =>
      match lookup_entity_idx dom a, lookup_entity_idx dom b with
      | Some ia, Some ib => perm_rank p ia <? perm_rank p ib
      | _, _ => false
      end
  | OC_After a b =>
      match lookup_entity_idx dom a, lookup_entity_idx dom b with
      | Some ia, Some ib => perm_rank p ib <? perm_rank p ia
      | _, _ => false
      end
  | OC_PinSlot a s =>
      match lookup_entity_idx dom a with
      | Some ia => perm_rank p ia =? slot_rank s
      | None => false
      end
  end.

Fixpoint check_all_order_constraints (dom : EntityTriple) (p : Perm3) (cs : list OrderConstraint) : bool :=
  match cs with
  | [] => true
  | c :: rest => check_order_constraint dom p c && check_all_order_constraints dom p rest
  end.

Definition eval_options_on_perm (dom : EntityTriple) (p : Perm3) (opts : ChoiceTriple OrderConstraint)
  : option Option3 :=
  if check_order_constraint dom p opts.(ct_A) then Some Opt3_A
  else if check_order_constraint dom p opts.(ct_B) then Some Opt3_B
  else if check_order_constraint dom p opts.(ct_C) then Some Opt3_C
  else None.

(** Method 4A (Operational): Exhaustive S_3 model enumeration. *)
Definition order_solve_operational (dom : EntityTriple) (premises : list OrderConstraint)
                                   (opts : ChoiceTriple OrderConstraint) : option Option3 :=
  match filter (fun p => check_all_order_constraints dom p premises) all_perms3 with
  | p :: _ => eval_options_on_perm dom p opts
  | [] => None
  end.

(** Method 4B (Algebraic CSP): Finite-Domain Rank-Bitmask Arc Propagation.
    Narrows candidate rank masks for each entity using unary pins and binary
    strict-inequality endpoint elimination (a < b => rank(a) != 2 /\ rank(b) != 0)
    before checking remaining relational constraints. *)
Record RankMask : Type := { m0 : bool; m1 : bool; m2 : bool }.
Record CSPDomains : Type := { d0 : RankMask; d1 : RankMask; d2 : RankMask }.

Definition full_mask : RankMask := {| m0 := true; m1 := true; m2 := true |}.
Definition init_csp_domains : CSPDomains := {| d0 := full_mask; d1 := full_mask; d2 := full_mask |}.

Definition mask_allows (m : RankMask) (r : Z) : bool :=
  if r =? 0 then m.(m0) else if r =? 1 then m.(m1) else m.(m2).

Definition mask_pin (m : RankMask) (s : RankSlot) : RankMask :=
  match s with
  | Slot_First  => {| m0 := m.(m0); m1 := false;  m2 := false  |}
  | Slot_Middle => {| m0 := false;  m1 := m.(m1); m2 := false  |}
  | Slot_Last   => {| m0 := false;  m1 := false;  m2 := m.(m2) |}
  end.

Definition mask_forbid_0 (m : RankMask) : RankMask := {| m0 := false; m1 := m.(m1); m2 := m.(m2) |}.
Definition mask_forbid_2 (m : RankMask) : RankMask := {| m0 := m.(m0); m1 := m.(m1); m2 := false |}.

Definition update_domain_at (ds : CSPDomains) (idx : EntityIdx) (f : RankMask -> RankMask) : CSPDomains :=
  match idx with
  | EIdx_0 => {| d0 := f ds.(d0); d1 := ds.(d1); d2 := ds.(d2) |}
  | EIdx_1 => {| d0 := ds.(d0); d1 := f ds.(d1); d2 := ds.(d2) |}
  | EIdx_2 => {| d0 := ds.(d0); d1 := ds.(d1); d2 := f ds.(d2) |}
  end.

Definition propagate_one_constraint (dom : EntityTriple) (c : OrderConstraint) (ds : CSPDomains) : CSPDomains :=
  match c with
  | OC_PinSlot a s =>
      match lookup_entity_idx dom a with
      | Some ia => update_domain_at ds ia (fun m => mask_pin m s)
      | None => ds
      end
  | OC_Before a b =>
      match lookup_entity_idx dom a, lookup_entity_idx dom b with
      | Some ia, Some ib =>
          update_domain_at (update_domain_at ds ia mask_forbid_2) ib mask_forbid_0
      | _, _ => ds
      end
  | OC_After a b =>
      match lookup_entity_idx dom a, lookup_entity_idx dom b with
      | Some ia, Some ib =>
          update_domain_at (update_domain_at ds ia mask_forbid_0) ib mask_forbid_2
      | _, _ => ds
      end
  end.

Fixpoint propagate_all_constraints (dom : EntityTriple) (cs : list OrderConstraint) (ds : CSPDomains) : CSPDomains :=
  match cs with
  | [] => ds
  | c :: rest => propagate_all_constraints dom rest (propagate_one_constraint dom c ds)
  end.

Definition perm_consistent_with_csp (ds : CSPDomains) (p : Perm3) : bool :=
  mask_allows ds.(d0) (perm_rank p EIdx_0) &&
  mask_allows ds.(d1) (perm_rank p EIdx_1) &&
  mask_allows ds.(d2) (perm_rank p EIdx_2).

Definition order_solve_algebraic (dom : EntityTriple) (premises : list OrderConstraint)
                                 (opts : ChoiceTriple OrderConstraint) : option Option3 :=
  let pruned := propagate_all_constraints dom premises init_csp_domains in
  match filter (fun p => perm_consistent_with_csp pruned p && check_all_order_constraints dom p premises) all_perms3 with
  | p :: _ => eval_options_on_perm dom p opts
  | [] => None
  end.

Lemma mask_forbid_0_sound : forall m r, r = 1 \/ r = 2 -> mask_allows m r = true -> mask_allows (mask_forbid_0 m) r = true.
Proof. intros [b0 b1 b2] r [Hr | Hr] H; subst; exact H. Qed.

Lemma mask_forbid_2_sound : forall m r, r = 0 \/ r = 1 -> mask_allows m r = true -> mask_allows (mask_forbid_2 m) r = true.
Proof. intros [b0 b1 b2] r [Hr | Hr] H; subst; exact H. Qed.

Lemma mask_pin_sound : forall m s r, r = slot_rank s -> mask_allows m r = true -> mask_allows (mask_pin m s) r = true.
Proof. intros [b0 b1 b2] [| |] r Hr H; subst; exact H. Qed.

Lemma propagate_one_sound :
  forall dom c ds p,
    check_order_constraint dom p c = true ->
    perm_consistent_with_csp ds p = true ->
    perm_consistent_with_csp (propagate_one_constraint dom c ds) p = true.
Proof.
  intros dom [a b | a b | a s] [[x0 x1 x2] [y0 y1 y2] [z0 z1 z2]] p Hc Hcons.
  - simpl in Hc |- *.
    destruct (lookup_entity_idx dom a) as [ia |]; [| discriminate].
    destruct (lookup_entity_idx dom b) as [ib |]; [| discriminate].
    destruct ia, ib, p; simpl in *; try discriminate; exact Hcons.
  - simpl in Hc |- *.
    destruct (lookup_entity_idx dom a) as [ia |]; [| discriminate].
    destruct (lookup_entity_idx dom b) as [ib |]; [| discriminate].
    destruct ia, ib, p; simpl in *; try discriminate; exact Hcons.
  - simpl in Hc |- *.
    destruct (lookup_entity_idx dom a) as [ia |]; [| discriminate].
    destruct ia, s, p; simpl in *; try discriminate; exact Hcons.
Qed.

Lemma propagate_all_sound :
  forall cs dom ds p,
    check_all_order_constraints dom p cs = true ->
    perm_consistent_with_csp ds p = true ->
    perm_consistent_with_csp (propagate_all_constraints dom cs ds) p = true.
Proof.
  induction cs as [| c rest IH]; intros dom ds p Hall Hcons; simpl in *.
  - exact Hcons.
  - apply andb_prop in Hall as [Hc Hrest].
    apply IH; [exact Hrest | apply propagate_one_sound; assumption].
Qed.

Lemma filter_pruned_eq_filter_enum :
  forall (ps : list Perm3) dom premises,
    filter (fun p => perm_consistent_with_csp (propagate_all_constraints dom premises init_csp_domains) p &&
                     check_all_order_constraints dom p premises) ps =
    filter (fun p => check_all_order_constraints dom p premises) ps.
Proof.
  induction ps as [| p rest IH]; intros dom premises; simpl; [reflexivity |].
  destruct (check_all_order_constraints dom p premises) eqn:Hchk.
  - assert (Hinit : perm_consistent_with_csp init_csp_domains p = true) by (destruct p; reflexivity).
    pose proof (propagate_all_sound premises dom init_csp_domains p Hchk Hinit) as Hpr.
    rewrite Hpr; simpl; rewrite IH; reflexivity.
  - rewrite Bool.andb_false_r. apply IH.
Qed.

Theorem order_operational_eq_algebraic :
  forall dom premises opts,
    order_solve_operational dom premises opts = order_solve_algebraic dom premises opts.
Proof.
  intros dom premises opts.
  unfold order_solve_operational, order_solve_algebraic.
  rewrite filter_pruned_eq_filter_enum. reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 6: DOMAIN 5 — OBJECT COUNTING (FILTER-SUM VS 5-BIN MAPREDUCE)     *)
(* ========================================================================= *)

Inductive OntologyTaxon : Type :=
  | Tax_MusicalInstrument
  | Tax_Fruit
  | Tax_Vegetable
  | Tax_Animal
  | Tax_ArtifactOther.

Inductive EntityNounADT : Type :=
  | EN_Accordion | EN_Apple | EN_Banana | EN_Bear | EN_Bed | EN_Blackberry
  | EN_Cabbage | EN_Car | EN_Carrot | EN_Cat | EN_Cauliflower | EN_Chair
  | EN_Chicken | EN_Clarinet | EN_Couch | EN_Cow | EN_Dog | EN_Donkey
  | EN_Drum | EN_Duck | EN_Fish | EN_Flute | EN_Fridge | EN_Frog
  | EN_Garlic | EN_Goat | EN_Grape | EN_HeadOfBroccoli | EN_Lamp | EN_LettuceHead
  | EN_Microwave | EN_Mouse | EN_Nectarine | EN_Onion | EN_Orange | EN_Oven
  | EN_Peach | EN_Piano | EN_Pig | EN_Plum | EN_Potato | EN_Rabbit
  | EN_Raspberry | EN_Snail | EN_Snake | EN_StalkOfCelery | EN_Stove | EN_Strawberry
  | EN_Table | EN_Toaster | EN_Trombone | EN_Trumpet | EN_Violin | EN_Yam.

Definition classify_noun (n : EntityNounADT) : OntologyTaxon :=
  match n with
  | EN_Accordion | EN_Clarinet | EN_Drum | EN_Flute | EN_Piano
  | EN_Trombone | EN_Trumpet | EN_Violin => Tax_MusicalInstrument
  | EN_Apple | EN_Banana | EN_Blackberry | EN_Grape | EN_Nectarine
  | EN_Orange | EN_Peach | EN_Plum | EN_Raspberry | EN_Strawberry => Tax_Fruit
  | EN_Cabbage | EN_Carrot | EN_Cauliflower | EN_Garlic | EN_HeadOfBroccoli
  | EN_LettuceHead | EN_Onion | EN_Potato | EN_StalkOfCelery | EN_Yam => Tax_Vegetable
  | EN_Bear | EN_Cat | EN_Chicken | EN_Cow | EN_Dog | EN_Donkey | EN_Duck
  | EN_Fish | EN_Frog | EN_Goat | EN_Mouse | EN_Pig | EN_Rabbit
  | EN_Snail | EN_Snake => Tax_Animal
  | EN_Bed | EN_Car | EN_Chair | EN_Couch | EN_Fridge | EN_Lamp
  | EN_Microwave | EN_Oven | EN_Stove | EN_Table | EN_Toaster => Tax_ArtifactOther
  end.

Inductive CountQueryTarget : Type :=
  | CQT_Taxon (t : OntologyTaxon)
  | CQT_AllObjects.

Record InventoryEntry : Type := {
  inv_qty  : Z;
  inv_noun : EntityNounADT
}.

Definition taxon_eqb (t1 t2 : OntologyTaxon) : bool :=
  match t1, t2 with
  | Tax_MusicalInstrument, Tax_MusicalInstrument
  | Tax_Fruit, Tax_Fruit
  | Tax_Vegetable, Tax_Vegetable
  | Tax_Animal, Tax_Animal
  | Tax_ArtifactOther, Tax_ArtifactOther => true
  | _, _ => false
  end.

Definition matches_count_target (tgt : CountQueryTarget) (n : EntityNounADT) : bool :=
  match tgt with
  | CQT_AllObjects => true
  | CQT_Taxon t => taxon_eqb (classify_noun n) t
  end.

(** Method 5A (Operational): Filter-then-sum pipeline. *)
Fixpoint count_solve_operational (inv : list InventoryEntry) (tgt : CountQueryTarget) : Z :=
  match inv with
  | [] => 0
  | e :: rest =>
      (if matches_count_target tgt e.(inv_noun) then e.(inv_qty) else 0) +
      count_solve_operational rest tgt
  end.

(** Method 5B (Algebraic): Single-pass homomorphic 5-bin TaxonHistogram MapReduce. *)
Record TaxonHistogram : Type := {
  th_inst  : Z;
  th_fruit : Z;
  th_veg   : Z;
  th_anim  : Z;
  th_other : Z
}.

Fixpoint build_taxon_histogram (inv : list InventoryEntry) : TaxonHistogram :=
  match inv with
  | [] => {| th_inst := 0; th_fruit := 0; th_veg := 0; th_anim := 0; th_other := 0 |}
  | e :: rest =>
      let h := build_taxon_histogram rest in
      let q := e.(inv_qty) in
      match classify_noun e.(inv_noun) with
      | Tax_MusicalInstrument => {| th_inst := q + h.(th_inst); th_fruit := h.(th_fruit); th_veg := h.(th_veg); th_anim := h.(th_anim); th_other := h.(th_other) |}
      | Tax_Fruit             => {| th_inst := h.(th_inst); th_fruit := q + h.(th_fruit); th_veg := h.(th_veg); th_anim := h.(th_anim); th_other := h.(th_other) |}
      | Tax_Vegetable         => {| th_inst := h.(th_inst); th_fruit := h.(th_fruit); th_veg := q + h.(th_veg); th_anim := h.(th_anim); th_other := h.(th_other) |}
      | Tax_Animal            => {| th_inst := h.(th_inst); th_fruit := h.(th_fruit); th_veg := h.(th_veg); th_anim := q + h.(th_anim); th_other := h.(th_other) |}
      | Tax_ArtifactOther     => {| th_inst := h.(th_inst); th_fruit := h.(th_fruit); th_veg := h.(th_veg); th_anim := h.(th_anim); th_other := q + h.(th_other) |}
      end
  end.

Definition project_histogram (h : TaxonHistogram) (tgt : CountQueryTarget) : Z :=
  match tgt with
  | CQT_Taxon Tax_MusicalInstrument => h.(th_inst)
  | CQT_Taxon Tax_Fruit             => h.(th_fruit)
  | CQT_Taxon Tax_Vegetable         => h.(th_veg)
  | CQT_Taxon Tax_Animal            => h.(th_anim)
  | CQT_Taxon Tax_ArtifactOther     => h.(th_other)
  | CQT_AllObjects => h.(th_inst) + h.(th_fruit) + h.(th_veg) + h.(th_anim) + h.(th_other)
  end.

Definition count_solve_algebraic (inv : list InventoryEntry) (tgt : CountQueryTarget) : Z :=
  project_histogram (build_taxon_histogram inv) tgt.

Theorem count_operational_eq_algebraic :
  forall (inv : list InventoryEntry) (tgt : CountQueryTarget),
    count_solve_operational inv tgt = count_solve_algebraic inv tgt.
Proof.
  unfold count_solve_algebraic.
  induction inv as [| [qty noun] rest IH]; intros tgt; simpl.
  - destruct tgt as [[| | | |] |]; reflexivity.
  - pose proof (IH (CQT_Taxon Tax_MusicalInstrument)) as H1.
    pose proof (IH (CQT_Taxon Tax_Fruit)) as H2.
    pose proof (IH (CQT_Taxon Tax_Vegetable)) as H3.
    pose proof (IH (CQT_Taxon Tax_Animal)) as H4.
    pose proof (IH (CQT_Taxon Tax_ArtifactOther)) as H5.
    pose proof (IH CQT_AllObjects) as H6.
    unfold matches_count_target in *.
    destruct (build_taxon_histogram rest) as [hi hf hv ha ho];
    destruct (classify_noun noun), tgt as [[| | | |] |]; simpl in *; lia.
Qed.

(* ========================================================================= *)
(* SECTION 7: DOMAIN 6 — BOOLEAN EXPRESSIONS (AST VS DE MORGAN NNF + VM)     *)
(* ========================================================================= *)

Inductive BoolExprADT : Type :=
  | BE_Const (b : bool)
  | BE_Not   (e : BoolExprADT)
  | BE_And   (e1 e2 : BoolExprADT)
  | BE_Or    (e1 e2 : BoolExprADT).

(** Method 6A (Operational): Direct recursive denotational evaluation. *)
Fixpoint bool_solve_operational (e : BoolExprADT) : bool :=
  match e with
  | BE_Const b   => b
  | BE_Not e1    => negb (bool_solve_operational e1)
  | BE_And e1 e2 => bool_solve_operational e1 && bool_solve_operational e2
  | BE_Or  e1 e2 => bool_solve_operational e1 || bool_solve_operational e2
  end.

(** Method 6B (Algebraic + Compiler VM): Push negations to leaves via De Morgan
    duality into Negation Normal Form (NNF), compile to postfix bytecode, and
    execute on a stack machine. *)
Inductive NNFExpr : Type :=
  | NNF_Lit (b : bool)
  | NNF_And (n1 n2 : NNFExpr)
  | NNF_Or  (n1 n2 : NNFExpr).

Fixpoint to_nnf (pol : bool) (e : BoolExprADT) : NNFExpr :=
  match e with
  | BE_Const b   => NNF_Lit (if pol then b else negb b)
  | BE_Not e1    => to_nnf (negb pol) e1
  | BE_And e1 e2 =>
      if pol then NNF_And (to_nnf true e1) (to_nnf true e2)
      else NNF_Or (to_nnf false e1) (to_nnf false e2)
  | BE_Or e1 e2  =>
      if pol then NNF_Or (to_nnf true e1) (to_nnf true e2)
      else NNF_And (to_nnf false e1) (to_nnf false e2)
  end.

Fixpoint eval_nnf (n : NNFExpr) : bool :=
  match n with
  | NNF_Lit b     => b
  | NNF_And n1 n2 => eval_nnf n1 && eval_nnf n2
  | NNF_Or  n1 n2 => eval_nnf n1 || eval_nnf n2
  end.

Inductive BoolOpcode : Type :=
  | BOp_Push (b : bool)
  | BOp_And
  | BOp_Or.

Fixpoint compile_nnf (n : NNFExpr) : list BoolOpcode :=
  match n with
  | NNF_Lit b     => [BOp_Push b]
  | NNF_And n1 n2 => compile_nnf n1 ++ compile_nnf n2 ++ [BOp_And]
  | NNF_Or  n1 n2 => compile_nnf n1 ++ compile_nnf n2 ++ [BOp_Or]
  end.

Fixpoint run_bool_vm (code : list BoolOpcode) (stk : list bool) : list bool :=
  match code with
  | [] => stk
  | BOp_Push b :: rest => run_bool_vm rest (b :: stk)
  | BOp_And :: rest =>
      match stk with
      | v2 :: v1 :: s' => run_bool_vm rest ((v1 && v2) :: s')
      | _ => stk
      end
  | BOp_Or :: rest =>
      match stk with
      | v2 :: v1 :: s' => run_bool_vm rest ((v1 || v2) :: s')
      | _ => stk
      end
  end.

Definition bool_solve_algebraic (e : BoolExprADT) : bool :=
  match run_bool_vm (compile_nnf (to_nnf true e)) [] with
  | v :: _ => v
  | [] => false
  end.

Lemma to_nnf_sound :
  forall (e : BoolExprADT) (pol : bool),
    eval_nnf (to_nnf pol e) = (if pol then bool_solve_operational e else negb (bool_solve_operational e)).
Proof.
  induction e as [b | e1 IH1 | e1 IH1 e2 IH2 | e1 IH1 e2 IH2]; intros [|]; simpl;
    try reflexivity; rewrite ?IH1, ?IH2;
    destruct (bool_solve_operational e1); try destruct (bool_solve_operational e2); reflexivity.
Qed.

Lemma compile_nnf_correct :
  forall (n : NNFExpr) (cont : list BoolOpcode) (stk : list bool),
    run_bool_vm (compile_nnf n ++ cont) stk = run_bool_vm cont (eval_nnf n :: stk).
Proof.
  induction n as [b | n1 IH1 n2 IH2 | n1 IH1 n2 IH2]; intros cont stk; simpl.
  - reflexivity.
  - rewrite <- !app_assoc. rewrite IH1. simpl. rewrite IH2. reflexivity.
  - rewrite <- !app_assoc. rewrite IH1. simpl. rewrite IH2. reflexivity.
Qed.

Theorem bool_operational_eq_algebraic :
  forall e : BoolExprADT,
    bool_solve_operational e = bool_solve_algebraic e.
Proof.
  intros e. unfold bool_solve_algebraic.
  pose proof (compile_nnf_correct (to_nnf true e) [] []) as Hvm.
  rewrite app_nil_r in Hvm. rewrite Hvm; simpl.
  rewrite to_nnf_sound. reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 8: DOMAIN 7 — MULTISTEP ARITHMETIC (AST VS RPN STACK VM)          *)
(* ========================================================================= *)

Inductive ArithExprADT : Type :=
  | AE_Lit (n : Z)
  | AE_Neg (e : ArithExprADT)
  | AE_Add (e1 e2 : ArithExprADT)
  | AE_Sub (e1 e2 : ArithExprADT)
  | AE_Mul (e1 e2 : ArithExprADT).

(** Method 7A (Operational): Direct recursive ring AST evaluation. *)
Fixpoint arith_solve_operational (e : ArithExprADT) : Z :=
  match e with
  | AE_Lit n     => n
  | AE_Neg e1    => - arith_solve_operational e1
  | AE_Add e1 e2 => arith_solve_operational e1 + arith_solve_operational e2
  | AE_Sub e1 e2 => arith_solve_operational e1 - arith_solve_operational e2
  | AE_Mul e1 e2 => arith_solve_operational e1 * arith_solve_operational e2
  end.

(** Method 7B (Algebraic / Compiler VM): Reverse Polish Notation (RPN) bytecode
    compilation + stack-machine execution. *)
Inductive ArithOpcode : Type :=
  | AOp_Push (n : Z)
  | AOp_Neg
  | AOp_Add
  | AOp_Sub
  | AOp_Mul.

Fixpoint compile_arith (e : ArithExprADT) : list ArithOpcode :=
  match e with
  | AE_Lit n     => [AOp_Push n]
  | AE_Neg e1    => compile_arith e1 ++ [AOp_Neg]
  | AE_Add e1 e2 => compile_arith e1 ++ compile_arith e2 ++ [AOp_Add]
  | AE_Sub e1 e2 => compile_arith e1 ++ compile_arith e2 ++ [AOp_Sub]
  | AE_Mul e1 e2 => compile_arith e1 ++ compile_arith e2 ++ [AOp_Mul]
  end.

Fixpoint run_arith_vm (code : list ArithOpcode) (stk : list Z) : list Z :=
  match code with
  | [] => stk
  | AOp_Push n :: rest => run_arith_vm rest (n :: stk)
  | AOp_Neg :: rest =>
      match stk with
      | v :: s' => run_arith_vm rest ((- v) :: s')
      | _ => stk
      end
  | AOp_Add :: rest =>
      match stk with
      | v2 :: v1 :: s' => run_arith_vm rest ((v1 + v2) :: s')
      | _ => stk
      end
  | AOp_Sub :: rest =>
      match stk with
      | v2 :: v1 :: s' => run_arith_vm rest ((v1 - v2) :: s')
      | _ => stk
      end
  | AOp_Mul :: rest =>
      match stk with
      | v2 :: v1 :: s' => run_arith_vm rest ((v1 * v2) :: s')
      | _ => stk
      end
  end.

Definition arith_solve_algebraic (e : ArithExprADT) : Z :=
  match run_arith_vm (compile_arith e) [] with
  | v :: _ => v
  | [] => 0
  end.

Lemma compile_arith_correct :
  forall (e : ArithExprADT) (cont : list ArithOpcode) (stk : list Z),
    run_arith_vm (compile_arith e ++ cont) stk = run_arith_vm cont (arith_solve_operational e :: stk).
Proof.
  induction e as [n | e1 IH1 | e1 IH1 e2 IH2 | e1 IH1 e2 IH2 | e1 IH1 e2 IH2];
    intros cont stk; simpl.
  - reflexivity.
  - rewrite <- app_assoc. rewrite IH1. reflexivity.
  - rewrite <- !app_assoc. rewrite IH1; simpl; rewrite IH2; reflexivity.
  - rewrite <- !app_assoc. rewrite IH1; simpl; rewrite IH2; reflexivity.
  - rewrite <- !app_assoc. rewrite IH1; simpl; rewrite IH2; reflexivity.
Qed.

Theorem arith_operational_eq_algebraic :
  forall e : ArithExprADT,
    arith_solve_operational e = arith_solve_algebraic e.
Proof.
  intros e. unfold arith_solve_algebraic.
  pose proof (compile_arith_correct e [] []) as Hvm.
  rewrite app_nil_r in Hvm. rewrite Hvm. reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 9: DOMAIN 8 — TEMPORAL SEQUENCES (BITMAP SWEEP VS INTERVAL ALG)   *)
(* ========================================================================= *)

Inductive PersonADT : Type :=
  | Per_Andrew | Per_Anthony | Per_Ashley | Per_Betty | Per_David
  | Per_Elizabeth | Per_Emily | Per_Hannah | Per_James | Per_Jason
  | Per_Jennifer | Per_Jessica | Per_John | Per_Kimberly | Per_Leslie
  | Per_Linda | Per_Lisa | Per_Mark | Per_Mary | Per_Michael
  | Per_Nancy | Per_Richard | Per_Samantha | Per_Sarah | Per_Sean
  | Per_Steven | Per_Susan | Per_Thomas | Per_Tiffany | Per_William.

Inductive VenueADT : Type :=
  | Ven_AmusementPark | Ven_ArtShow | Ven_ArtStudio | Ven_Bakery
  | Ven_BasketballCourt | Ven_Beach | Ven_Bookstore | Ven_ClothingStore
  | Ven_CoffeeShop | Ven_ConstructionSite | Ven_DanceStudio | Ven_FootballField
  | Ven_GasStation | Ven_Library | Ven_Market | Ven_Movies | Ven_Museum
  | Ven_OrchestraHall | Ven_Park | Ven_PhysicsClassroom | Ven_Restaurant
  | Ven_SoccerField | Ven_SwimmingPool.

Inductive ObservedActivity : Type :=
  | Act_AttendingClassAtSchool
  | Act_BuyingBikeAtBikeShop
  | Act_BuyingPhoneAtElectronicsStore
  | Act_BuyingClothesAtMall
  | Act_BuyingCookiesAtBakery
  | Act_BuyingLunchAtDeli
  | Act_DrivingToWaterPark
  | Act_FixingComputerAtElectronicStore
  | Act_GettingCoffeeAtCafe
  | Act_PlayingTennisAtTennisCourt
  | Act_ReadingAtLibrary
  | Act_SittingOnRooftop
  | Act_StretchingAtYogaStudio
  | Act_TakingPhotosNearEiffelTower
  | Act_TakingPhotosNearLeaningTowerOfPisa
  | Act_WaitingAtAirport
  | Act_WaitingAtTrainStation
  | Act_WalkingInGarden
  | Act_WalkingTowardsStatueOfLiberty
  | Act_WatchingMovieAtTheater
  | Act_WorkingAtOffice
  | Act_WorkingOutAtGym.

Inductive ScheduleConstraint : Type :=
  | SC_WokeUpAt     (hour : Z)
  | SC_ClosedBefore (hour : Z)
  | SC_ClosedAfter  (hour : Z)
  | SC_Observed     (witness : PersonADT) (act : ObservedActivity) (t_start t_end : Z).

Record TimeInterval : Type := {
  ti_start : Z;
  ti_end   : Z
}.

Definition time_interval_eqb (w1 w2 : TimeInterval) : bool :=
  (w1.(ti_start) =? w2.(ti_start)) && (w1.(ti_end) =? w2.(ti_end)).

(** Method 8A (Operational): Discrete hourly occupancy sweep across [s, e). *)
Definition constraint_busy_at (c : ScheduleConstraint) (h : Z) : bool :=
  match c with
  | SC_WokeUpAt wake       => h <? wake
  | SC_ClosedBefore open_h => h <? open_h
  | SC_ClosedAfter close_h => close_h <=? h
  | SC_Observed _ _ a b    => (a <=? h) && (h <? b)
  end.

Fixpoint any_constraint_busy_at (facts : list ScheduleConstraint) (h : Z) : bool :=
  match facts with
  | [] => false
  | c :: rest => constraint_busy_at c h || any_constraint_busy_at rest h
  end.

Fixpoint hourly_range_free (facts : list ScheduleConstraint) (h : Z) (len : nat) : bool :=
  match len with
  | O => true
  | S rest => negb (any_constraint_busy_at facts h) && hourly_range_free facts (h + 1) rest
  end.

Definition window_open_operational (facts : list ScheduleConstraint) (w : TimeInterval) : bool :=
  let s := w.(ti_start) in
  let e := w.(ti_end) in
  (0 <=? s) && (s <? e) && (e <=? 24) &&
  hourly_range_free facts s (Z.to_nat (e - s)).

Definition temp_solve_operational (facts : list ScheduleConstraint)
                                  (opts : ChoiceQuad TimeInterval)
  : option (Option4 * TimeInterval) :=
  if window_open_operational facts opts.(cq_A) then Some (Opt4_A, opts.(cq_A))
  else if window_open_operational facts opts.(cq_B) then Some (Opt4_B, opts.(cq_B))
  else if window_open_operational facts opts.(cq_C) then Some (Opt4_C, opts.(cq_C))
  else if window_open_operational facts opts.(cq_D) then Some (Opt4_D, opts.(cq_D))
  else None.

(** Method 8B (Algebraic): Symbolic interval-disjointness algebra without hour iteration. *)
Definition constraint_disjoint_symbolic (c : ScheduleConstraint) (s e : Z) : bool :=
  match c with
  | SC_WokeUpAt wake       => wake <=? s
  | SC_ClosedBefore open_h => open_h <=? s
  | SC_ClosedAfter close_h => e <=? close_h
  | SC_Observed _ _ a b    => (b <=? a) || (e <=? a) || (b <=? s)
  end.

Fixpoint all_constraints_disjoint (facts : list ScheduleConstraint) (s e : Z) : bool :=
  match facts with
  | [] => true
  | c :: rest => constraint_disjoint_symbolic c s e && all_constraints_disjoint rest s e
  end.

Definition window_open_algebraic (facts : list ScheduleConstraint) (w : TimeInterval) : bool :=
  let s := w.(ti_start) in
  let e := w.(ti_end) in
  (0 <=? s) && (s <? e) && (e <=? 24) &&
  all_constraints_disjoint facts s e.

Definition temp_solve_algebraic (facts : list ScheduleConstraint)
                                (opts : ChoiceQuad TimeInterval)
  : option (Option4 * TimeInterval) :=
  if window_open_algebraic facts opts.(cq_A) then Some (Opt4_A, opts.(cq_A))
  else if window_open_algebraic facts opts.(cq_B) then Some (Opt4_B, opts.(cq_B))
  else if window_open_algebraic facts opts.(cq_C) then Some (Opt4_C, opts.(cq_C))
  else if window_open_algebraic facts opts.(cq_D) then Some (Opt4_D, opts.(cq_D))
  else None.

Fixpoint single_hourly_free (c : ScheduleConstraint) (h : Z) (len : nat) : bool :=
  match len with
  | O => true
  | S rest => negb (constraint_busy_at c h) && single_hourly_free c (h + 1) rest
  end.

Lemma hourly_range_split_cons :
  forall c rest len h,
    hourly_range_free (c :: rest) h len =
    single_hourly_free c h len && hourly_range_free rest h len.
Proof.
  intros c rest len.
  induction len as [| m IH]; intros h; simpl.
  - reflexivity.
  - rewrite negb_orb, IH.
    destruct (negb (constraint_busy_at c h)),
             (any_constraint_busy_at rest h),
             (single_hourly_free c (h + 1) m),
             (hourly_range_free rest (h + 1) m); reflexivity.
Qed.

Lemma hourly_range_empty_facts :
  forall len h, hourly_range_free [] h len = true.
Proof.
  induction len as [| m IH]; intros h; simpl; [reflexivity | apply IH].
Qed.

Lemma single_hourly_free_spec :
  forall c len s,
    single_hourly_free c s len = true <->
    (forall h : Z, s <= h < s + Z.of_nat len -> constraint_busy_at c h = false).
Proof.
  intros c len.
  induction len as [| m IH]; intros s; simpl.
  - split; [intros _ h Hh; lia | intros _; reflexivity].
  - rewrite andb_true_iff, negb_true_iff, IH.
    split.
    + intros [Hs Hrest] h Hh.
      destruct (Z.eq_dec h s) as [Heq | Hneq].
      * subst; exact Hs.
      * apply Hrest. lia.
    + intros Hall. split.
      * apply Hall. lia.
      * intros h Hh. apply Hall. lia.
Qed.

Lemma single_hourly_eq_symbolic :
  forall c s k,
    single_hourly_free c s (S k) =
    constraint_disjoint_symbolic c s (s + Z.of_nat (S k)).
Proof.
  intros c s k.
  apply Bool.eq_true_iff_eq.
  rewrite single_hourly_free_spec.
  destruct c as [wake | open_h | close_h | wit act a b]; simpl.
  - rewrite Z.leb_le. split; intros H.
    + specialize (H s ltac:(lia)). rewrite Z.ltb_ge in H. exact H.
    + intros h Hh. rewrite Z.ltb_ge. lia.
  - rewrite Z.leb_le. split; intros H.
    + specialize (H s ltac:(lia)). rewrite Z.ltb_ge in H. exact H.
    + intros h Hh. rewrite Z.ltb_ge. lia.
  - rewrite Z.leb_le. split; intros H.
    + specialize (H (s + Z.of_nat (S k) - 1) ltac:(lia)).
      rewrite Z.leb_gt in H. lia.
    + intros h Hh. rewrite Z.leb_gt. lia.
  - rewrite !orb_true_iff, !Z.leb_le.
    split; intros H.
    + destruct (Z_le_gt_dec b a) as [Hba | Hab]; [left; left; exact Hba |].
      destruct (Z_le_gt_dec (s + Z.of_nat (S k)) a) as [Hea | Hae]; [left; right; exact Hea |].
      destruct (Z_le_gt_dec b s) as [Hbs | Hsb]; [right; exact Hbs |].
      exfalso.
      pose (hm := Z.max s a).
      assert (Hbounds : s <= hm < s + Z.of_nat (S k)) by lia.
      specialize (H hm Hbounds).
      rewrite andb_false_iff, Z.leb_gt, Z.ltb_ge in H.
      lia.
    + intros h Hh. rewrite andb_false_iff, Z.leb_gt, Z.ltb_ge.
      destruct H as [[Hba | Hea] | Hbs]; lia.
Qed.

Lemma all_hourly_eq_all_symbolic :
  forall facts s k,
    hourly_range_free facts s (S k) =
    all_constraints_disjoint facts s (s + Z.of_nat (S k)).
Proof.
  induction facts as [| c rest IH]; intros s k.
  - apply hourly_range_empty_facts.
  - cbn [all_constraints_disjoint].
    rewrite hourly_range_split_cons, single_hourly_eq_symbolic, IH. reflexivity.
Qed.

Lemma window_open_operational_eq_algebraic :
  forall facts w,
    window_open_operational facts w = window_open_algebraic facts w.
Proof.
  intros facts [s e]. unfold window_open_operational, window_open_algebraic; simpl.
  destruct ((0 <=? s) && (s <? e) && (e <=? 24)) eqn:Hwf; simpl; [| reflexivity].
  apply andb_prop in Hwf as [Hwf1 _]. apply andb_prop in Hwf1 as [_ Hse].
  rewrite Z.ltb_lt in Hse.
  destruct (Z.to_nat (e - s)) eqn:Hnat; [lia |].
  replace e with (s + Z.of_nat (S n)) by lia.
  apply all_hourly_eq_all_symbolic.
Qed.

Theorem temp_operational_eq_algebraic :
  forall facts opts,
    temp_solve_operational facts opts = temp_solve_algebraic facts opts.
Proof.
  intros facts [wA wB wC wD].
  unfold temp_solve_operational, temp_solve_algebraic; simpl.
  rewrite !window_open_operational_eq_algebraic.
  reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 10: UNIFIED QUESTION ADT, ANSWER ADT & GRAND EQUIVALENCE THEOREM  *)
(* ========================================================================= *)

Inductive QuestionADT : Type :=
  | Q_Navigate         (prog : list NavInstruction)
  | Q_WebOfLies        (kb : list TestimonyClause) (target : SpeakerADT)
  | Q_SwapTracking     (scen : SwapScenario) (init : InitialHolding)
                       (swaps : list TranspositionSwap) (queried : SwapAgent)
                       (opts : ChoiceTriple HeldObjectADT)
  | Q_LogicalDeduction (scen : OrderScenario) (dom : EntityTriple)
                       (premises : list OrderConstraint)
                       (opts : ChoiceTriple OrderConstraint)
  | Q_ObjectCounting   (inv : list InventoryEntry) (target : CountQueryTarget)
  | Q_BooleanExpr      (formula : BoolExprADT)
  | Q_MultistepArith   (expr : ArithExprADT)
  | Q_TemporalSeq      (agent : PersonADT) (venue : VenueADT)
                       (facts : list ScheduleConstraint)
                       (opts : ChoiceQuad TimeInterval).

Inductive AnswerADT : Type :=
  | Ans_YesNo       (b : bool)
  | Ans_Truth       (b : bool)
  | Ans_Count       (n : Z)
  | Ans_IntVal      (n : Z)
  | Ans_HeldChoice  (choice : Option3) (item : HeldObjectADT)
  | Ans_OrderChoice (choice : Option3)
  | Ans_TimeChoice  (choice : Option4) (window : TimeInterval)
  | Ans_Undetermined.

Definition answer_eqb (a1 a2 : AnswerADT) : bool :=
  match a1, a2 with
  | Ans_YesNo b1, Ans_YesNo b2 => Bool.eqb b1 b2
  | Ans_Truth b1, Ans_Truth b2 => Bool.eqb b1 b2
  | Ans_Count n1, Ans_Count n2 => Z.eqb n1 n2
  | Ans_IntVal n1, Ans_IntVal n2 => Z.eqb n1 n2
  | Ans_HeldChoice c1 i1, Ans_HeldChoice c2 i2 =>
      option3_eqb c1 c2 && held_object_eqb i1 i2
  | Ans_OrderChoice c1, Ans_OrderChoice c2 =>
      option3_eqb c1 c2
  | Ans_TimeChoice c1 w1, Ans_TimeChoice c2 w2 =>
      option4_eqb c1 c2 && time_interval_eqb w1 w2
  | Ans_Undetermined, Ans_Undetermined => true
  | _, _ => false
  end.

(** Master Multi-Paradigm QA Evaluator executing entirely inside Rocq/Coq. *)
Definition compute_answer (mode : SolverMode) (q : QuestionADT) : AnswerADT :=
  match q with
  | Q_Navigate prog =>
      Ans_YesNo (match mode with
                 | Mode_Operational => nav_solve_operational prog
                 | Mode_Algebraic   => nav_solve_algebraic prog
                 end)
  | Q_WebOfLies kb target =>
      let res := match mode with
                 | Mode_Operational => wol_solve_operational kb target
                 | Mode_Algebraic   => wol_solve_algebraic kb target
                 end in
      match res with
      | Some b => Ans_YesNo b
      | None   => Ans_Undetermined
      end
  | Q_SwapTracking _ init swaps queried opts =>
      let item := match mode with
                  | Mode_Operational => swap_eval_operational init swaps queried
                  | Mode_Algebraic   => swap_eval_algebraic init swaps queried
                  end in
      match match_held_choice item opts with
      | Some (ch, it) => Ans_HeldChoice ch it
      | None          => Ans_Undetermined
      end
  | Q_LogicalDeduction _ dom premises opts =>
      let res := match mode with
                 | Mode_Operational => order_solve_operational dom premises opts
                 | Mode_Algebraic   => order_solve_algebraic dom premises opts
                 end in
      match res with
      | Some ch => Ans_OrderChoice ch
      | None    => Ans_Undetermined
      end
  | Q_ObjectCounting inv target =>
      Ans_Count (match mode with
                 | Mode_Operational => count_solve_operational inv target
                 | Mode_Algebraic   => count_solve_algebraic inv target
                 end)
  | Q_BooleanExpr formula =>
      Ans_Truth (match mode with
                 | Mode_Operational => bool_solve_operational formula
                 | Mode_Algebraic   => bool_solve_algebraic formula
                 end)
  | Q_MultistepArith expr =>
      Ans_IntVal (match mode with
                  | Mode_Operational => arith_solve_operational expr
                  | Mode_Algebraic   => arith_solve_algebraic expr
                  end)
  | Q_TemporalSeq _ _ facts opts =>
      let res := match mode with
                 | Mode_Operational => temp_solve_operational facts opts
                 | Mode_Algebraic   => temp_solve_algebraic facts opts
                 end in
      match res with
      | Some (ch, win) => Ans_TimeChoice ch win
      | None           => Ans_Undetermined
      end
  end.

(** GRAND UNIFIED MULTI-PARADIGM EQUIVALENCE THEOREM:
    For EVERY well-typed QuestionADT across all 8 domains (including arbitrary
    unseen questions beyond the 2,000-item BBH dataset), the Operational solver
    and the Algebraic/Bytecode/CSP solver compute the EXACT same AnswerADT! *)
Theorem universal_multi_paradigm_qa_equivalence :
  forall (q : QuestionADT),
    compute_answer Mode_Operational q = compute_answer Mode_Algebraic q.
Proof.
  destruct q as [prog | kb target | scen init swaps queried opts |
                 scen dom premises opts | inv target | formula | expr |
                 agent venue facts opts]; simpl.
  - rewrite nav_operational_eq_algebraic. reflexivity.
  - rewrite wol_operational_eq_algebraic. reflexivity.
  - rewrite swap_operational_eq_algebraic. reflexivity.
  - rewrite order_operational_eq_algebraic. reflexivity.
  - rewrite count_operational_eq_algebraic. reflexivity.
  - rewrite bool_operational_eq_algebraic. reflexivity.
  - rewrite arith_operational_eq_algebraic. reflexivity.
  - rewrite temp_operational_eq_algebraic. reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 11: PURE-ADT BENCHMARK HARNESS & SCORECARD STRUCTURES             *)
(* ========================================================================= *)

Inductive TaskDomainId : Type :=
  | Dom_Navigate
  | Dom_WebOfLies
  | Dom_SwapTracking
  | Dom_LogicalDeduction
  | Dom_ObjectCounting
  | Dom_BooleanExpr
  | Dom_MultistepArith
  | Dom_TemporalSeq.

Record QABenchmarkItem : Type := {
  qbi_id       : nat;
  qbi_domain   : TaskDomainId;
  qbi_question : QuestionADT;
  qbi_gold     : AnswerADT
}.

Record SuiteScorecard : Type := {
  sc_total  : Z;
  sc_passed : Z;
  sc_failed : Z
}.

Fixpoint evaluate_qa_suite (mode : SolverMode) (items : list QABenchmarkItem) : SuiteScorecard :=
  match items with
  | [] => {| sc_total := 0; sc_passed := 0; sc_failed := 0 |}
  | it :: rest =>
      let sub := evaluate_qa_suite mode rest in
      let pred := compute_answer mode it.(qbi_question) in
      if answer_eqb pred it.(qbi_gold) then
        {| sc_total := 1 + sub.(sc_total); sc_passed := 1 + sub.(sc_passed); sc_failed := sub.(sc_failed) |}
      else
        {| sc_total := 1 + sub.(sc_total); sc_passed := sub.(sc_passed); sc_failed := 1 + sub.(sc_failed) |}
  end.

Theorem scorecard_partition_conservation :
  forall (mode : SolverMode) (items : list QABenchmarkItem),
    (evaluate_qa_suite mode items).(sc_passed) +
    (evaluate_qa_suite mode items).(sc_failed) =
    (evaluate_qa_suite mode items).(sc_total).
Proof.
  intros mode items.
  induction items as [| it rest IH]; cbn [evaluate_qa_suite sc_passed sc_failed sc_total]; [lia |].
  destruct (answer_eqb (compute_answer mode it.(qbi_question)) it.(qbi_gold));
    cbn [sc_passed sc_failed sc_total]; lia.
Qed.

Theorem evaluate_qa_suite_mode_invariant :
  forall (items : list QABenchmarkItem),
    evaluate_qa_suite Mode_Operational items = evaluate_qa_suite Mode_Algebraic items.
Proof.
  induction items as [| it rest IH]; simpl; [reflexivity |].
  rewrite universal_multi_paradigm_qa_equivalence, IH.
  reflexivity.
Qed.
