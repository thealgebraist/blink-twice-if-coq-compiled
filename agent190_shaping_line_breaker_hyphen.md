### Audit Report: Agent 190
**Target:** Chromium Blink `ShapingLineBreaker` (Hyphen Insertion)  
**Specification:** CSS Text Module Level 3, §5.4 (Hyphenation: the `hyphens` property)  
**Artifact:** `BlinkShapingLineBreakerHyphenSemantics.v`

---

### 1. Hyphen Line Break Mechanics (Blink vs. CSS Text 3 §5.4)

In Chromium Blink (`third_party/blink/renderer/platform/fonts/shaping/shaping_line_breaker.cc`), when shaping a line that overflows `available_width`, the line breaker queries `Hyphenation` for valid break opportunities prior to the first overflowing character offset. 

According to CSS Text 3 §5.4, when a word is broken at a hyphenation opportunity, the hyphen glyph itself must be rendered inside the line box, contributing to the inline advance of that line.

For a candidate break offset $i$ (where $i$ represents the UTF-16 code unit offset within the text node/run):
1. **Prefix Measurement:** Blink computes the inline advance of the text slice from the line start offset $s$ up to candidate offset $i$, denoted as $\text{prefix\_width}(i)$.
2. **Hyphen Advance Addition:** If offset $i$ requires a visible hyphen (soft hyphen `U+00AD` or dictionary-driven auto-hyphenation), Blink shapes the target hyphen string (typically `U+2010` or `-`) using the current font and style to obtain $\text{hyphen\_width}$.
3. **Fit Criterion:** The candidate break at $i$ fits the line box if and only if:
   $$\text{prefix\_width}(i) + \text{hyphen\_width} \le \text{available\_width}$$
   Blink iterates backward from the overflow point to find the maximum valid hyphenation offset $i$ satisfying this inequality.

---

### 2. Core Invariants

To guarantee absence of inline layout overflow and infinite pagination loops in Blink’s `NGInlineLayoutAlgorithm`, `ShapingLineBreaker` enforces two strict invariants whenever a hyphenated line break is committed:

1. **Bounded Line Advance Invariant:** The total inline advance of the broken line segment—comprising the shaped prefix up to $i$ plus the appended hyphen glyph—must never exceed the remaining space in the line box:
   $$\text{total\_advance}(i) = \text{prefix\_width}(i) + \text{hyphen\_width} \le \text{available\_width}$$
   *(Note: If no candidate $i$ satisfies this, hyphenation is aborted for that word, falling back to an earlier break opportunity or emergency overflow wrapping).*

2. **Strict Positivity Invariant (Progress Guarantee):** The chosen break index $i$ relative to the start of the current line must be strictly positive ($i > 0$). Breaking at $i = 0$ with a hyphen would consume inline space solely for a leading hyphen without advancing the text stream, causing non-termination in line breaking.

---

### 3. Concrete Rocq / Coq Formalization

Below is the self-contained formalization for `BlinkShapingLineBreakerHyphenSemantics.v`, modeling the monotonic prefix width, backward candidate search, and formal verification of the two invariants.

```coq
(** * BlinkShapingLineBreakerHyphenSemantics.v
    Formal Audit of Chromium Blink ShapingLineBreaker Hyphen Insertion
    against CSS Text Module Level 3 §5.4. *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

Section BlinkHyphenSemantics.

  (** ** 1. Context Parameters & Types *)

  (** Inline layout quantities (LayoutUnit modeled as nat). *)
  Variable available_width : nat.
  Variable hyphen_width : nat.

  (** Prefix width function mapping character index [i] to inline advance. *)
  Variable prefix_width : nat -> nat.

  (** Predicate identifying valid hyphenation opportunities (CSS Text 3 §5.4). *)
  Variable is_hyphen_opportunity : nat -> bool.

  (** Monotonicity of shaping advances (non-negative glyph advances). *)
  Hypothesis prefix_width_monotonic :
    forall i j, i <= j -> prefix_width i <= prefix_width j.

  Hypothesis prefix_width_zero :
    prefix_width 0 = 0.

  (** ** 2. Definitions of Fit and Validity *)

  (** Total advance of a line broken with a hyphen at index [i]. *)
  Definition total_hyphenated_advance (i : nat) : nat :=
    prefix_width i + hyphen_width.

  (** Decidable fit condition: prefix_width(i) + hyphen_width <= available_width. *)
  Definition hyphen_break_fitsb (i : nat) : bool :=
     total_hyphenated_advance i <=? available_width.

  (** Prop-level specification of a valid hyphenated break at index [i]. *)
  Definition valid_hyphen_break (i : nat) : Prop :=
    i > 0 /\
    is_hyphen_opportunity i = true /\
    total_hyphenated_advance i <= available_width.

  (** Boolean checker used by the line breaker search algorithm. *)
  Definition valid_hyphen_breakb (i : nat) : bool :=
    (0 <? i) && is_hyphen_opportunity i && hyphen_break_fitsb i.

  (** ** 3. Backward Candidate Search (ShapingLineBreaker::Hyphenate) *)

  (** Searches backward from [max_idx] down to 1 for the largest valid break. *)
  Fixpoint select_hyphen_break (max_idx : nat) : option nat :=
    match max_idx with
    | 0 => None
    | S k =>
        if valid_hyphen_breakb (S k) then Some (S k)
        else select_hyphen_break k
    end.

  (** ** 4. Lemmas & Invariant Theorems *)

  Lemma valid_hyphen_breakb_spec : forall i,
    valid_hyphen_breakb i = true <-> valid_hyphen_break i.
  Proof.
    intros i.
    unfold valid_hyphen_breakb, valid_hyphen_break, hyphen_break_fitsb.
    rewrite !andb_true_iff, Nat.ltb_lt, Nat.leb_le.
    split; intros [[Hpos Hopp] Hfit]; repeat split; auto; lia.
  Qed.

  (** *** Theorem 1: Soundness of Invariants (Advance Bound & Strict Positivity)
      If [select_hyphen_break] returns [Some i], then:
      1. [i > 0] (Strict Positivity / Progress Invariant)
      2. [prefix_width i + hyphen_width <= available_width] (Bounded Advance Invariant)
      3. [i] is a valid CSS Text 3 §5.4 hyphenation opportunity. *)
  Theorem select_hyphen_break_invariants : forall max_idx i,
    select_hyphen_break max_idx = Some i ->
    i > 0 /\
    total_hyphenated_advance i <= available_width /\
    is_hyphen_opportunity i = true.
  Proof.
    induction max_idx as [| k IH]; intros i Hsel.
    - simpl in Hsel. discriminate Hsel.
    - simpl in Hsel.
      destruct (valid_hyphen_breakb (S k)) eqn:Hvalid.
      + injection Hsel as Heq; subst i.
        apply valid_hyphen_breakb_spec in Hvalid.
        destruct Hvalid as [Hpos [Hopp Hfit]].
        repeat split; assumption.
      + apply IH in Hsel. exact Hsel.
  Qed.

  (** *** Theorem 2: Bound by Search Ceiling
      The selected break index never exceeds the initial overflow index [max_idx]. *)
  Theorem select_hyphen_break_le_max : forall max_idx i,
    select_hyphen_break max_idx = Some i ->
    i <= max_idx.
  Proof.
    induction max_idx as [| k IH]; intros i Hsel.
    - simpl in Hsel. discriminate Hsel.
    - simpl in Hsel.
      destruct (valid_hyphen_breakb (S k)) eqn:Hvalid.
      + injection Hsel as Heq; subst i. lia.
      + apply IH in Hsel. lia.
  Qed.

  (** *** Theorem 3: Greedy Optimality (CSS Text 3 Line-Fitting Maximality)
      [select_hyphen_break] selects the largest valid break index <= [max_idx]. *)
  Theorem select_hyphen_break_maximal : forall max_idx i j,
    select_hyphen_break max_idx = Some i ->
    j <= max_idx ->
    valid_hyphen_break j ->
    j <= i.
  Proof.
    induction max_idx as [| k IH]; intros i j Hsel Hjle Hvalidj.
    - simpl in Hsel. discriminate Hsel.
    - simpl in Hsel.
      destruct (valid_hyphen_breakb (S k)) eqn:Hvk.
      + injection Hsel as Heq; subst i. exact Hjle.
      + assert ( j <> S k ) as Hneq.
        { intros Heq; subst j.
          apply valid_hyphen_breakb_spec in Hvalidj.
          rewrite Hvalidj in Hvk. discriminate Hvk. }
        assert ( j <= k ) as Hjlek by lia.
        eapply IH; eauto.
  Qed.

End BlinkHyphenSemantics.
```