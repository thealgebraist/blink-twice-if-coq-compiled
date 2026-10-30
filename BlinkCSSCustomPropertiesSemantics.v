(** * BlinkCSSCustomPropertiesSemantics.v
    Formalization of Chromium Blink's CSS Custom Properties and var() Substitution
    (StyleCascade / CascadeResolver / CSSVariableData) against W3C CSS Custom Properties L1.
*)

From Stdlib Require Import Lists.List.
From Stdlib Require Import Arith.PeanoNat.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.

(** ** 1. Core Syntax and Data Structures *)

Definition VarName := nat.
Definition RawToken := nat.

Inductive ExprToken : Type :=
  | TokRaw : RawToken -> ExprToken
  | TokVar : VarName -> option (list ExprToken) -> ExprToken.

Definition ExprStream := list ExprToken.
Definition ResolvedStream := list RawToken.

Inductive ResolvedValue : Type :=
  | ValValid : ResolvedStream -> ResolvedValue
  | GuaranteedInvalid : ResolvedValue.

Definition CascadeMap := VarName -> option ExprStream.
Definition Stack := list VarName.

Definition in_stack (v : VarName) (stk : Stack) : bool :=
  existsb (Nat.eqb v) stk.

Lemma in_stack_nil : forall v, in_stack v [] = false.
Proof. intros. reflexivity. Qed.

Lemma in_stack_cons_eq : forall v rest, in_stack v (v :: rest) = true.
Proof. intros. unfold in_stack. simpl. rewrite Nat.eqb_refl. reflexivity. Qed.

Lemma in_stack_cons_neq : forall v1 v2 rest,
  v1 <> v2 ->
  in_stack v1 (v2 :: rest) = in_stack v1 rest.
Proof.
  intros v1 v2 rest Hneq.
  unfold in_stack. simpl.
  assert (H : Nat.eqb v1 v2 = false).
  { apply Nat.eqb_neq. exact Hneq. }
  rewrite H. reflexivity.
Qed.

Inductive CycleState : Type :=
  | NoCycle : CycleState
  | ActiveCycle : VarName -> CycleState.

Definition EvalResult := (ResolvedValue * CycleState)%type.

(** ** 2. Resolution Algorithm with Mutual Recursion on Fuel *)

Section BlinkResolver.
  Variable (cascade : CascadeMap).

  Fixpoint resolve_var (fuel : nat) (v : VarName) (stk : Stack) : EvalResult :=
    match fuel with
    | 0 => (GuaranteedInvalid, NoCycle)
    | S fuel' =>
        if in_stack v stk then
          (GuaranteedInvalid, ActiveCycle v)
        else
          match cascade v with
          | None => (GuaranteedInvalid, NoCycle)
          | Some expr =>
              let '(res, cyc) := resolve_stream fuel' expr (v :: stk) in
              match cyc with
              | ActiveCycle target =>
                  if Nat.eqb target v then
                    (GuaranteedInvalid, NoCycle)
                  else
                    (GuaranteedInvalid, ActiveCycle target)
              | NoCycle => (res, NoCycle)
              end
          end
    end
  with resolve_stream (fuel : nat) (expr : ExprStream) (stk : Stack) : EvalResult :=
    match fuel with
    | 0 => (GuaranteedInvalid, NoCycle)
    | S fuel' =>
        match expr with
        | [] => (ValValid [], NoCycle)
        | (TokRaw r) :: rest =>
            let '(rest_res, cyc) := resolve_stream fuel' rest stk in
            match cyc with
            | ActiveCycle target => (GuaranteedInvalid, ActiveCycle target)
            | NoCycle =>
                match rest_res with
                | ValValid toks => (ValValid (r :: toks), NoCycle)
                | GuaranteedInvalid => (GuaranteedInvalid, NoCycle)
                end
            end
        | (TokVar target fallback) :: rest =>
            let '(v_res, cyc) := resolve_var fuel' target stk in
            match cyc with
            | ActiveCycle cycle_target => (GuaranteedInvalid, ActiveCycle cycle_target)
            | NoCycle =>
                let '(head_res, head_cyc) :=
                  match v_res with
                  | ValValid toks => (ValValid toks, NoCycle)
                  | GuaranteedInvalid =>
                      match fallback with
                      | Some fb => resolve_stream fuel' fb stk
                      | None => (GuaranteedInvalid, NoCycle)
                      end
                  end
                in
                match head_cyc with
                | ActiveCycle cycle_target => (GuaranteedInvalid, ActiveCycle cycle_target)
                | NoCycle =>
                    match head_res with
                    | GuaranteedInvalid => (GuaranteedInvalid, NoCycle)
                    | ValValid toks_head =>
                        let '(rest_res, rest_cyc) := resolve_stream fuel' rest stk in
                        match rest_cyc with
                        | ActiveCycle cycle_target => (GuaranteedInvalid, ActiveCycle cycle_target)
                        | NoCycle =>
                            match rest_res with
                            | ValValid toks_rest => (ValValid (toks_head ++ toks_rest), NoCycle)
                            | GuaranteedInvalid => (GuaranteedInvalid, NoCycle)
                            end
                        end
                    end
                end
            end
        end
    end.

End BlinkResolver.

(** ** 3. Formal Theorems & Correctness Invariants *)

Definition raw_to_expr (toks : list RawToken) : ExprStream :=
  map TokRaw toks.

(** Invariant 1: Empty stream resolves to empty valid token list *)
Theorem resolve_stream_empty : forall cascade fuel stk,
  fuel > 0 ->
  resolve_stream cascade fuel [] stk = (ValValid [], NoCycle).
Proof.
  intros cascade fuel stk Hf.
  destruct fuel as [| f]; [lia | simpl; reflexivity].
Qed.

(** Invariant 2: Pure raw token stream evaluates directly to the token list *)
Theorem resolve_stream_pure_raw : forall cascade toks fuel stk,
  fuel > length toks ->
  resolve_stream cascade fuel (raw_to_expr toks) stk = (ValValid toks, NoCycle).
Proof.
  intros cascade toks.
  induction toks as [| r rest IH]; intros fuel stk Hfuel.
  - destruct fuel as [| f]; [lia | simpl; reflexivity].
  - destruct fuel as [| f]; [lia |].
    simpl in Hfuel.
    simpl.
    assert (Hf : f > length rest) by lia.
    rewrite (IH f stk Hf).
    reflexivity.
Qed.

(** Invariant 3: Immediate self-cycle detection *)
Theorem cycle_self_detected : forall cascade fuel v stk,
  fuel > 0 ->
  in_stack v stk = true ->
  resolve_var cascade fuel v stk = (GuaranteedInvalid, ActiveCycle v).
Proof.
  intros cascade fuel v stk Hf Hin.
  destruct fuel as [| f]; [lia |].
  simpl. rewrite Hin. reflexivity.
Qed.

(** Invariant 4: Self-referential property --v: var(--v) unwinds to GuaranteedInvalid with NoCycle *)
Theorem self_referential_cycle_resolves_invalid :
  resolve_var (fun x => if x =? 0 then Some [TokVar 0 None] else None) 3 0 [] =
  (GuaranteedInvalid, NoCycle).
Proof.
  vm_compute. reflexivity.
Qed.

(** Invariant 5: Mutual 2-step cycle unwinds cleanly *)
Theorem mutual_cycle_resolves_invalid :
  resolve_var
    (fun x => if x =? 0 then Some [TokVar 1 None] else if x =? 1 then Some [TokVar 0 None] else None)
    5 0 [] =
  (GuaranteedInvalid, NoCycle).
Proof.
  vm_compute. reflexivity.
Qed.

(** Invariant 6: External property referencing a cycled property successfully activates fallback *)
Theorem cycled_var_fallback_taken : forall fb,
  resolve_var
    (fun x => if x =? 0 then Some [TokVar 1 (Some [TokRaw fb])] else if x =? 1 then Some [TokVar 1 None] else None)
    5 0 [] =
  (ValValid [fb], NoCycle).
Proof.
  intros. vm_compute. reflexivity.
Qed.

(** Invariant 7: Property inside a cycle ignores fallback *)
Theorem cycle_in_progress_ignores_fallback : forall fb,
  resolve_var
    (fun x => if x =? 0 then Some [TokVar 1 (Some [TokRaw fb])] else if x =? 1 then Some [TokVar 0 None] else None)
    5 0 [] =
  (GuaranteedInvalid, NoCycle).
Proof.
  intros. vm_compute. reflexivity.
Qed.
