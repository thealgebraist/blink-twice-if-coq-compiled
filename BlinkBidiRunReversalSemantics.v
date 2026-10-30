(**
  BlinkBidiRunReversalSemantics.v
  Formal specification of Chromium Blink inline bidi reordering and run reversal
  derived from third_party/blink/renderer/platform/text/bidi_resolver.h
  and core/layout/inline/bidi_paragraph.cc
  according to Unicode Standard Annex #9 (UAX #9 §3.4 Rule L2: Reversing Resolved Levels)
  and CSS Writing Modes Level 3.
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Record BidiRun := {
  run_id : Z;
  embedding_level : Z
}.

(** 1. UAX #9 L2 Contiguous Subsegment Reversal *)

Fixpoint reverse_contiguous_ge (target_level : Z) (acc : list BidiRun) (runs : list BidiRun) : list BidiRun :=
  match runs with
  | [] => rev acc
  | r :: rs =>
      if target_level <=? r.(embedding_level) then
        reverse_contiguous_ge target_level (r :: acc) rs
      else
        (rev acc) ++ (r :: reverse_contiguous_ge target_level [] rs)
  end.

Definition apply_l2_reversal_step (target_level : Z) (runs : list BidiRun) : list BidiRun :=
  reverse_contiguous_ge target_level [] runs.

(** 2. Invariant Theorems *)

Lemma reverse_contiguous_ge_length :
  forall (target_level : Z) (runs acc : list BidiRun),
    length (reverse_contiguous_ge target_level acc runs) = (length acc + length runs)%nat.
Proof.
  intros target_level runs.
  induction runs as [|r rs IH].
  - intros acc.
    simpl.
    rewrite length_rev.
    lia.
  - intros acc.
    simpl.
    destruct (target_level <=? r.(embedding_level)) eqn:Ege.
    + rewrite IH.
      simpl. lia.
    + rewrite length_app.
      rewrite length_rev.
      simpl.
      rewrite IH.
      simpl. lia.
Qed.

Theorem l2_step_preserves_run_count :
  forall (target_level : Z) (runs : list BidiRun),
    length (apply_l2_reversal_step target_level runs) = length runs.
Proof.
  intros target_level runs.
  unfold apply_l2_reversal_step.
  rewrite reverse_contiguous_ge_length.
  simpl. reflexivity.
Qed.

Theorem run_reversal_involutive :
  forall (runs : list BidiRun),
    rev (rev runs) = runs.
Proof.
  intros runs.
  apply rev_involutive.
Qed.

Theorem empty_runs_l2_invariant :
  forall target_level : Z,
    apply_l2_reversal_step target_level [] = [].
Proof.
  intros target_level.
  unfold apply_l2_reversal_step.
  simpl. reflexivity.
Qed.
