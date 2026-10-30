(**
  BlinkMediaQueryRangeSemantics.v
  Formal specification of Chromium Blink CSS media queries range context evaluation
  derived from third_party/blink/renderer/core/css/media_query_evaluator.cc
  according to W3C Media Queries Level 4 (§2 Media Query Range Syntax).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Inductive MQOp : Type :=
  | MQ_Eq
  | MQ_Lt
  | MQ_Le
  | MQ_Gt
  | MQ_Ge.

Definition eval_mq_op (actual_val : Z) (op : MQOp) (bound : Z) : bool :=
  match op with
  | MQ_Eq => actual_val =? bound
  | MQ_Lt => actual_val <? bound
  | MQ_Le => actual_val <=? bound
  | MQ_Gt => bound <? actual_val
  | MQ_Ge => bound <=? actual_val
  end.

Inductive MQExpr : Type :=
  | MQConst (b : bool)
  | MQRange (op : MQOp) (bound : Z)
  | MQInterval (op_l : MQOp) (bound_l : Z) (op_r : MQOp) (bound_r : Z)
  | MQAnd (e1 e2 : MQExpr)
  | MQOr (e1 e2 : MQExpr)
  | MQNot (e : MQExpr).

Fixpoint eval_mq_expr (actual_val : Z) (e : MQExpr) : bool :=
  match e with
  | MQConst b => b
  | MQRange op bound => eval_mq_op actual_val op bound
  | MQInterval op_l bound_l op_r bound_r =>
      eval_mq_op bound_l op_l actual_val && eval_mq_op actual_val op_r bound_r
  | MQAnd e1 e2 => eval_mq_expr actual_val e1 && eval_mq_expr actual_val e2
  | MQOr e1 e2 => eval_mq_expr actual_val e1 || eval_mq_expr actual_val e2
  | MQNot e' => negb (eval_mq_expr actual_val e')
  end.

(** 1. Boolean De Morgan Laws & Involution Invariants *)

Theorem mq_not_involutive :
  forall (actual_val : Z) (e : MQExpr),
    eval_mq_expr actual_val (MQNot (MQNot e)) = eval_mq_expr actual_val e.
Proof.
  intros actual_val e.
  simpl.
  apply negb_involutive.
Qed.

Theorem mq_de_morgan_and :
  forall (actual_val : Z) (e1 e2 : MQExpr),
    eval_mq_expr actual_val (MQNot (MQAnd e1 e2)) =
    eval_mq_expr actual_val (MQOr (MQNot e1) (MQNot e2)).
Proof.
  intros actual_val e1 e2.
  simpl.
  apply negb_andb.
Qed.

Theorem mq_de_morgan_or :
  forall (actual_val : Z) (e1 e2 : MQExpr),
    eval_mq_expr actual_val (MQNot (MQOr e1 e2)) =
    eval_mq_expr actual_val (MQAnd (MQNot e1) (MQNot e2)).
Proof.
  intros actual_val e1 e2.
  simpl.
  apply negb_orb.
Qed.

(** 2. Relational Monotonicity Invariants *)

Theorem mq_le_monotonic :
  forall (v b1 b2 : Z),
    eval_mq_op v MQ_Le b1 = true ->
    b1 <= b2 ->
    eval_mq_op v MQ_Le b2 = true.
Proof.
  intros v b1 b2 Hle Hord.
  unfold eval_mq_op in *.
  apply Z.leb_le in Hle.
  apply Z.leb_le.
  lia.
Qed.

Theorem mq_ge_anti_monotonic :
  forall (v b1 b2 : Z),
    eval_mq_op v MQ_Ge b2 = true ->
    b1 <= b2 ->
    eval_mq_op v MQ_Ge b1 = true.
Proof.
  intros v b1 b2 Hge Hord.
  unfold eval_mq_op in *.
  apply Z.leb_le in Hge.
  apply Z.leb_le.
  lia.
Qed.

