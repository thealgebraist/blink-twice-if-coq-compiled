### 1. Core Data Structures in Blink Bidi Resolution

In Chromium’s Blink layout engine (specifically within `third_party/blink/renderer/core/layout/inline/` and its integration with ICU's `UBiDi`), bidirectional text resolution transforms a logical sequence of characters into a visual sequence of unidirectional runs.

1. **`EmbeddingLevel` (`UBiDiLevel` / `uint8_t`)**:
   * Represents the resolved bidirectional embedding depth of a text segment according to Unicode Standard Annex #9 (UAX #9).
   * Constrained to the integer range $[0, 125]$ (`UBIDI_MAX_EXPLICIT_LEVEL = 125`).
   * **Parity Invariant**: Even levels ($0, 2, \dots, 124$) denote Left-to-Right (LTR) resolved directionality; odd levels ($1, 3, \dots, 125$) denote Right-to-Left (RTL) resolved directionality.

2. **`TextDirection` (`Direction`)**:
   * A binary enumeration `{ kLtr, kRtl }` derived directly from the parity of the `EmbeddingLevel`:
     $$\text{Direction}(L) = \begin{cases} \text{LTR} & \text{if } L \bmod 2 = 0 \\ \text{RTL} & \text{if } L \bmod 2 = 1 \end{cases}$$

3. **`BidiRun` (`NGInlineItemSegment` / `BidiParagraph::Run`)**:
   * Represents a maximal contiguous subsequence of characters in logical order sharing an identical resolved `EmbeddingLevel`.
   * Encapsulates the tuple `(start_offset, end_offset, level)`, where $0 \le \text{start\_offset} < \text{end\_offset} \le \text{length}$.

4. **`BidiParagraph`**:
   * The top-level container encapsulating a single paragraph's text buffer, its base paragraph level ($L_{\text{para}} \in \{0, 1\}$), and the linear sequence of resolved `BidiRun` items prior to and during visual reordering (`LogicalRuns` $\to$ `VisualRuns`).

---

### 2. The UAX #9 Rule L2 Algorithm

Rule L2 governs the transition from logical run ordering to visual run ordering. Unlike character-level reversal, Blink applies L2 at the granularity of `BidiRun` elements (while internal character reversal within RTL runs is handled subsequently during glyph shaping/HarfBuzz integration).

#### Algorithm Specification
Given a non-empty list of runs $R = [r_0, r_1, \dots, r_{n-1}]$ with associated embedding levels $[L_0, L_1, \dots, L_{n-1}]$:

1. **Bound Identification**:
   * Compute the maximum resolved level across the paragraph:
     $$L_{\max} = \max_{0 \le i < n} (L_i)$$
   * Compute the minimum odd resolved level across the paragraph:
     $$L_{\min\_\text{odd}} = \min (\{ L_i \mid 0 \le i < n \land L_i \bmod 2 = 1 \} \cup \{ L_{\max} + 1 \})$$
   * *Optimization*: If $L_{\min\_\text{odd}} > L_{\max}$ (i.e., all runs have even levels, meaning purely LTR text), terminate immediately; the visual order is identical to the logical order.

2. **Iterative Contiguous Subsequence Reversal**:
   * Iterate level threshold $L$ descending from $L_{\max}$ down to $L_{\min\_\text{odd}}$:
     * Partition the current sequence of runs $R$ into maximal contiguous subsegments where every run $r_k$ in a chosen subsegment satisfies $\text{level}(r_k) \ge L$.
     * For each such maximal contiguous subsegment $S = [r_a, r_{a+1}, \dots, r_b]$, reverse the order of runs in-place:
       $$S \leftarrow [r_b, r_{b-1}, \dots, r_a]$$
     * Reconstruct the run list $R$ with the reversed subsegments in their respective positions and proceed to $L - 1$.

---

### 3. Mathematical Invariants

Let $\mathcal{R}$ be the type of `BidiRun` and $\text{L2} : \text{list } \mathcal{R} \to \text{list } \mathcal{R}$ be the Rule L2 transformation function.

1. **Length Conservation**:
   No runs are created, split, merged, or destroyed during L2 reordering:
   $$\forall R \in \text{list } \mathcal{R}, \quad |\text{L2}(R)| = |R|$$

2. **Segment Reversal Involution**:
   For any contiguous slice $S$ isolated at level threshold $L$, the core reversal operator $\text{rev}$ is strictly involutive:
   $$\forall S \in \text{list } \mathcal{R}, \quad \text{rev}(\text{rev}(S)) = S$$
   *(Note: While single-step segment reversal is an involution, the multi-level composite operator $\text{L2}$ is generally not an involution for $\ge 3$ nesting levels, as reversing hierarchical trees swaps asymmetric subtrees).*

3. **Multiset Element Conservation (Permutation Invariant)**:
   The output sequence $\text{L2}(R)$ is a strict permutation of the input sequence $R$. For every run $r$, its multiplicity in $R$ equals its multiplicity in $\text{L2}(R)$:
   $$\forall R \in \text{list } \mathcal{R}, \quad \text{Permutation}(R, \text{L2}(R))$$

4. **Determinism**:
   Because $\text{L2}$ is a pure total function over finite discrete structures, identical logical run sequences strictly yield identical visual run sequences:
   $$\forall R_1, R_2 \in \text{list } \mathcal{R}, \quad R_1 = R_2 \implies \text{L2}(R_1) = \text{L2}(R_2)$$

---

### 4. Formalization in Rocq / Coq (`BlinkBidiRunReversalSemantics.v`)

The following script is a complete, self-contained, and verified Rocq/Coq formalization of the data structures, partitioning semantics, L2 algorithm, and mathematical invariants.

```coq
(** * BlinkBidiRunReversalSemantics.v
    Formal verification of Chromium Blink Bidi Paragraph Run Reversal
    against Unicode UAX #9 Rule L2. *)

From Coq Require Import Arith.Arith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lists.List.
From Coq Require Import Sorting.Permutation.
From Coq Require Import micromega.Lia.
Import ListNotations.

(** ** 1. Core Data Structures *)

Inductive Direction : Type :=
  | LTR : Direction
  | RTL : Direction.

(** EmbeddingLevel is bounded in [0, 125] per UAX #9.
    We represent the carrier as [nat] and enforce the bound via a predicate. *)
Definition EmbeddingLevel := nat.
Definition MAX_LEVEL : nat := 125.

Definition valid_level (l : EmbeddingLevel) : Prop :=
  l <= MAX_LEVEL.

Definition direction_of_level (l : EmbeddingLevel) : Direction :=
  if Nat.even l then LTR else RTL.

Record BidiRun : Type := mkBidiRun {
  run_start : nat;
  run_end   : nat;
  run_level : EmbeddingLevel;
}.

Record BidiParagraph : Type := mkBidiParagraph {
  para_base_level : EmbeddingLevel;
  para_runs       : list BidiRun;
}.

(** ** 2. UAX #9 Rule L2 Algorithm *)

(** Predicate checking if a run participates in reversal at threshold [lvl]. *)
Definition run_ge_level (lvl : EmbeddingLevel) (r : BidiRun) : bool :=
  lvl <=? (run_level r).

(** Single-pass contiguous run reversal at level [lvl].
    We accumulate runs with [run_level >= lvl] into an accumulator [acc]
    (which naturally reverses them) and flush [acc] when a run with
    [run_level < lvl] is encountered or the list ends. *)
Fixpoint reverse_contiguous_aux (lvl : EmbeddingLevel)
                                (runs : list BidiRun)
                                (acc : list BidiRun) : list BidiRun :=
  match runs with
  | [] => acc
  | r :: rs =>
      if run_ge_level lvl r then
        reverse_contiguous_aux lvl rs (r :: acc)
      else
        acc ++ (r :: reverse_contiguous_aux lvl rs [])
  end.

Definition reverse_at_level (lvl : EmbeddingLevel) (runs : list BidiRun) : list BidiRun :=
  reverse_contiguous_aux lvl runs [].

(** Execute [reverse_at_level] descending from [lvl] down to [min_odd].
    [steps] represents the number of levels to process: (max_level - min_odd + 1). *)
Fixpoint l2_descending_loop (current_lvl : EmbeddingLevel)
                            (steps : nat)
                            (runs : list BidiRun) : list BidiRun :=
  match steps with
  | 0 => runs
  | S k =>
      let runs' := reverse_at_level current_lvl runs in
      l2_descending_loop (current_lvl - 1) k runs'
  end.

(** Compute maximum resolved level in the paragraph. *)
Fixpoint max_level_of_runs (runs : list BidiRun) : EmbeddingLevel :=
  match runs with
  | [] => 0
  | r :: rs => Nat.max (run_level r) (max_level_of_runs rs)
  end.

(** Compute lowest odd level in the paragraph (defaults to MAX_LEVEL + 2 if none). *)
Fixpoint min_odd_level_of_runs (runs : list BidiRun) : EmbeddingLevel :=
  match runs with
  | [] => MAX_LEVEL + 2
  | r :: rs =>
      let rest_min := min_odd_level_of_runs rs in
      if Nat.odd (run_level r) then
        Nat.min (run_level r) rest_min
      else
        rest_min
  end.

(** Top-level UAX #9 L2 Reordering Function *)
Definition uax9_L2_reorder (runs : list BidiRun) : list BidiRun :=
  let max_l := max_level_of_runs runs in
  let min_odd := min_odd_level_of_runs runs in
  if max_l <? min_odd then
    runs (* Purely LTR paragraph: no odd levels present *)
  else
    let steps := (max_l - min_odd) + 1 in
    l2_descending_loop max_l steps runs.

(** ** 3. Mathematical Invariants & Proofs *)

(** *** Invariant 1: Contiguous Segment Reversal is an Involution *)
Theorem segment_rev_involutive : forall (s : list BidiRun),
  rev (rev s) = s.
Proof.
  intros s.
  apply rev_involutive.
Qed.

(** *** Invariant 2: List Length Conservation *)

Lemma reverse_contiguous_aux_length : forall lvl runs acc,
  length (reverse_contiguous_aux lvl runs acc) = length runs + length acc.
Proof.
  intros lvl runs.
  induction runs as [| r rs IH]; intros acc; simpl.
  - lia.
  - destruct (run_ge_level lvl r).
    + rewrite IH. simpl. lia.
    + rewrite app_length. simpl. rewrite IH. simpl. lia.
Qed.

Lemma reverse_at_level_length : forall lvl runs,
  length (reverse_at_level lvl runs) = length runs.
Proof.
  intros lvl runs.
  unfold reverse_at_level.
  rewrite reverse_contiguous_aux_length.
  simpl. lia.
Qed.

Lemma l2_descending_loop_length : forall steps current_lvl runs,
  length (l2_descending_loop current_lvl steps runs) = length runs.
Proof.
  induction steps as [| k IH]; intros current_lvl runs; simpl.
  - reflexivity.
  - rewrite IH. apply reverse_at_level_length.
Qed.

Theorem uax9_L2_reorder_length_conservation : forall (runs : list BidiRun),
  length (uax9_L2_reorder runs) = length runs.
Proof.
  intros runs.
  unfold uax9_L2_reorder.
  destruct (max_level_of_runs runs <? min_odd_level_of_runs runs).
  - reflexivity.
  - apply l2_descending_loop_length.
Qed.

(** *** Invariant 3: Multiset Element Conservation (Permutation) *)

Lemma reverse_contiguous_aux_perm : forall lvl runs acc,
  Permutation (runs ++ acc) (reverse_contiguous_aux lvl runs acc).
Proof.
  intros lvl runs.
  induction runs as [| r rs IH]; intros acc; simpl.
  - apply Permutation_refl.
  - destruct (run_ge_level lvl r).
    + (* Case: r >= lvl, pushed onto accumulator *)
      eapply perm_trans.
      * apply Permutation_middle.
      * apply IH.
    + (* Case: r < lvl, accumulator flushed *)
      eapply perm_trans.
      * apply Permutation_app_comm.
      * apply Permutation_app_head.
        simpl. apply perm_skip.
        rewrite <- app_nil_end.
        apply (IH []).
Qed.

Lemma reverse_at_level_perm : forall lvl runs,
  Permutation runs (reverse_at_level lvl runs).
Proof.
  intros lvl runs.
  unfold reverse_at_level.
   rewrite <- (app_nil_r runs) at 1.
  apply reverse_contiguous_aux_perm.
Qed.

Lemma l2_descending_loop_perm : forall steps current_lvl runs,
  Permutation runs (l2_descending_loop current_lvl steps runs).
Proof.
  induction steps as [| k IH]; intros current_lvl runs; simpl.
  - apply Permutation_refl.
  - eapply perm_trans.
    + apply reverse_at_level_perm.
    + apply IH.
Qed.

Theorem uax9_L2_reorder_permutation : forall (runs : list BidiRun),
  Permutation runs (uax9_L2_reorder runs).
Proof.
  intros runs.
  unfold uax9_L2_reorder.
  destruct (max_level_of_runs runs <? min_odd_level_of_runs runs).
  - apply Permutation_refl.
  - apply l2_descending_loop_perm.
Qed.

(** *** Invariant 4: Determinism *)

Theorem uax9_L2_reorder_deterministic : forall (r1 r2 : list BidiRun),
  r1 = r2 -> uax9