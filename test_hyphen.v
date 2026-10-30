Require Import BlinkTextHyphenationBreakSemantics.
From Stdlib Require Import ZArith List.
Import ListNotations.
Open Scope Z_scope.

Theorem auto_break_respects_prefix_suffix_test : forall cfg w avail i,
  soft_hyphens w = nil ->
  select_hyphen_break HyphensAuto cfg w avail = Some i ->
  min_prefix cfg <= i /\ i + min_suffix cfg <= word_len w.
Proof.
  intros cfg w avail i Hsoft Hsel.
  apply auto_break_respects_prefix_suffix in Hsel; [assumption | assumption].
Qed.
