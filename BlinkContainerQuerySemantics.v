(* =========================================================================
   BlinkContainerQuerySemantics.v
   Formalization of Chromium Blink CSS Container Query Evaluation
   Source: third_party/blink/renderer/core/css/container_query_evaluator.cc
   Specification: W3C CSS Containment Module Level 3 §3
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

Inductive ContainerQueryCondition : Type :=
  | CQMinWidth (min_w : Z)
  | CQMaxWidth (max_w : Z)
  | CQAnd (q1 q2 : ContainerQueryCondition)
  | CQOr (q1 q2 : ContainerQueryCondition)
  | CQNot (q : ContainerQueryCondition).

Fixpoint eval_container_query
    (q : ContainerQueryCondition) (container_width : Z) : bool :=
  match q with
  | CQMinWidth min_w => min_w <=? container_width
  | CQMaxWidth max_w => container_width <=? max_w
  | CQAnd q1 q2 => eval_container_query q1 container_width && eval_container_query q2 container_width
  | CQOr q1 q2 => eval_container_query q1 container_width || eval_container_query q2 container_width
  | CQNot q1 => negb (eval_container_query q1 container_width)
  end.

Theorem min_width_monotonic :
  forall w cw1 cw2,
    cw1 <= cw2 ->
    eval_container_query (CQMinWidth w) cw1 = true ->
    eval_container_query (CQMinWidth w) cw2 = true.
Proof.
  intros w cw1 cw2 Hle Hq.
  simpl in *.
  apply Z.leb_le in Hq.
  apply Z.leb_le.
  lia.
Qed.

Theorem max_width_anti_monotonic :
  forall w cw1 cw2,
    cw1 <= cw2 ->
    eval_container_query (CQMaxWidth w) cw2 = true ->
    eval_container_query (CQMaxWidth w) cw1 = true.
Proof.
  intros w cw1 cw2 Hle Hq.
  simpl in *.
  apply Z.leb_le in Hq.
  apply Z.leb_le.
  lia.
Qed.

Theorem cq_de_morgan_and :
  forall q1 q2 cw,
    eval_container_query (CQNot (CQAnd q1 q2)) cw =
    eval_container_query (CQOr (CQNot q1) (CQNot q2)) cw.
Proof.
  intros q1 q2 cw.
  simpl.
  apply negb_andb.
Qed.

Theorem cq_not_involutive :
  forall q cw,
    eval_container_query (CQNot (CQNot q)) cw = eval_container_query q cw.
Proof.
  intros q cw.
  simpl.
  apply negb_involutive.
Qed.

Theorem eval_container_query_deterministic :
  forall q cw r1 r2,
    r1 = eval_container_query q cw ->
    r2 = eval_container_query q cw ->
    r1 = r2.
Proof.
  intros q cw r1 r2 H1 H2.
  subst. reflexivity.
Qed.
