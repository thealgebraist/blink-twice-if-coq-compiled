(* =========================================================================
   BlinkHyphenationSemantics.v
   Formalization of Chromium Blink Inline Hyphenation & Opportunity Bounds
   Source: third_party/blink/renderer/core/layout/inline/hyphenator.cc
   Specification: W3C CSS Text Module Level 3 §5.4 Hyphenation
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Arith.Arith.
From Coq Require Import Lia.
Open Scope Z_scope.

Record HyphenationConfig : Type := mkHyphenationConfig {
  hc_min_prefix : nat;
  hc_min_suffix : nat;
  hc_hyphen_width : Z
}.

Definition is_valid_hyphen_break
    (cfg : HyphenationConfig) (word_len : nat) (break_idx : nat) : bool :=
  if (break_idx <? cfg.(hc_min_prefix))%nat then false
  else if (word_len <? break_idx + cfg.(hc_min_suffix))%nat then false
  else true.

Definition compute_hyphenated_prefix_width
    (raw_prefix_width : Z) (hyphen_width : Z) : Z :=
  raw_prefix_width + hyphen_width.

Theorem valid_break_satisfies_min_prefix :
  forall cfg word_len break_idx,
    is_valid_hyphen_break cfg word_len break_idx = true ->
    (cfg.(hc_min_prefix) <= break_idx)%nat.
Proof.
  intros cfg word_len break_idx Hval.
  unfold is_valid_hyphen_break in Hval.
  destruct (break_idx <? hc_min_prefix cfg)%nat eqn:Epre.
  - discriminate Hval.
  - apply Nat.ltb_ge in Epre. exact Epre.
Qed.

Theorem valid_break_satisfies_min_suffix :
  forall cfg word_len break_idx,
    is_valid_hyphen_break cfg word_len break_idx = true ->
    (break_idx + cfg.(hc_min_suffix) <= word_len)%nat.
Proof.
  intros cfg word_len break_idx Hval.
  unfold is_valid_hyphen_break in Hval.
  destruct (break_idx <? hc_min_prefix cfg)%nat eqn:Epre; [discriminate Hval |].
  destruct (word_len <? break_idx + hc_min_suffix cfg)%nat eqn:Esuf; [discriminate Hval |].
  apply Nat.ltb_ge in Esuf. exact Esuf.
Qed.

Theorem hyphenated_prefix_width_increases :
  forall raw_w hyphen_w,
    0 <= hyphen_w ->
    raw_w <= compute_hyphenated_prefix_width raw_w hyphen_w.
Proof.
  intros raw_w hyphen_w Hh.
  unfold compute_hyphenated_prefix_width.
  lia.
Qed.

Theorem compute_hyphenated_prefix_width_deterministic :
  forall rw hw w1 w2,
    w1 = compute_hyphenated_prefix_width rw hw ->
    w2 = compute_hyphenated_prefix_width rw hw ->
    w1 = w2.
Proof.
  intros rw hw w1 w2 H1 H2.
  subst. reflexivity.
Qed.

