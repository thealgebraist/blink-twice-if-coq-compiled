Here is the architectural and formal audit of Chromium Blink’s `text-wrap: balance` implementation (`NGScoreLineBreakContext`, `NGLineWidths`, and `NGScoreLineBreaker`) evaluated against CSS Text Module Level 4 § 5.1.

---

### 1. Core Data Structures in Blink Balanced Text Wrapping

In Chromium’s LayoutNG engine, balanced text wrapping (primarily governed by `third_party/blink/renderer/core/layout/inline/score_line_breaker.cc` and `line_break_candidate.h`) abstracts inline items into discrete breakable units and evaluates partition trees. For formal verification, we map Blink's internal C++ structures to three canonical abstractions:

1. **`LineBreakCandidate` (`blink::LineBreakCandidate`)**:
   * **Representation**: Represents an atomic inline break opportunity (typically spanning from the start of the text or a prior break opportunity to the end of a word or hyphenation point).
   * **Fields**:
     * `offset`: The UTF-16 character index and inline item index in `NGInlineNodeData`.
     * `pos_no_break`: Cumulative inline width (in `LayoutUnit`, 1/64th of a pixel) if no break occurs here (includes trailing spaces).
     * `pos_if_break`: Cumulative inline width if a line break is inserted at this candidate (excludes trailing collapsible whitespace, adds hyphen width if applicable).
     * `penalty`: Explicit penalty incurred by breaking at this point (e.g., hyphenation penalty).

2. **`LineBalanceScore` (`float` / `LayoutUnit` metrics)**:
   * **Representation**: Encapsulates the objective cost of a given line-break configuration.
   * **Semantics**: In `text-wrap: balance`, the score represents the variance/deviation of line widths relative to the target mean width or the widest line in the paragraph. A lower score (closer to `0`) represents a better balance. Invalid configurations (overflowing `available_width`) are assigned $+\infty$ (`std::numeric_limits<float>::infinity()`).

3. **`TextWrapEvaluator` (`blink::ScoreLineBreaker`)**:
   * **Representation**: The stateful optimization engine that ingests a vector of `LineBreakCandidate`s, the `available_width` (often uniform across lines, stored in `LineWidths`), and a maximum line threshold (`kMaxBalanceLines`, set to 6 in Blink for performance bounds).
   * **Role**: First computes the minimum required number of lines $M$ using a greedy pass (`GreedyLineBreaker`). It then runs a dynamic programming (Knuth-Plass derivative) or bisection algorithm to partition the candidates into exactly $M$ lines to minimize the `LineBalanceScore`.

---

### 2. Balanced Line Breaking Objective

CSS Text Level 4 § 5.1 specifies that under `text-wrap: balance`, *"the remaining space on each line is distributed so that the inline-axis length of the content on each line is as close to equal as possible, without changing the total number of lines."*

Let $M$ be the number of lines determined by standard greedy line breaking. For a candidate partition of text into $M$ lines with widths $w_1, w_2, \dots, w_M$:

1. **LineCount Preservation**: The balanced breaker must not increase the line count beyond $M$.
2. **Mathematical Objective**: We define the target mean width $\bar{w}$ (or ideal width) over the $M$ lines. The objective is to find a valid partition $P = (L_1, L_2, \dots, L_M)$ that minimizes the squared deviation (variance scale):
   $$\text{Score}(P) = \sum_{i=1}^{M} (w_i - \bar{w})^2$$
   *(Note: In discrete fixed-point arithmetic, to avoid rational division truncation, this can be equivalently scaled by $M^2$: $\sum_{i=1}^M (M \cdot w_i - W_{\text{total}})^2$, where $W_{\text{total}} = \sum_{j=1}^M w_j$.)*

---

### 3. Line Partitioning Algorithm

Given $N$ atomic inline segments (words/glyph clusters) with widths $c_1, c_2, \dots, c_N$, an `available_width` $W_{\max}$, and target line count $M$:

1. **Feasibility Constraint**: Every line $L_i$ must be a contiguous non-empty subsegment of candidates (or potentially empty if $N < M$, though typically $N \ge M$) such that its total width satisfies:
   $$\forall i \in \{1, \dots, M\}, \quad w(L_i) \le W_{\max}$$
2. **Dynamic Programming / State Space**:
   Define $DP(k, j)$ as the optimal partition of the first $j$ candidates into $k$ lines.
   $$DP(k, j) = \min_{0 \le i < j \text{ s.t. } w(i+1 \dots j) \le W_{\max}} \left\{ DP(k-1, i) + (w(i+1 \dots j) - \bar{w})^2 \right\}$$
   In Blink, for exact `balance` without complex hyphenation penalties, this is also frequently accelerated by binary searching the tightest shrunk `available_width` $W' \le W_{\max}$ such that greedy breaking still yields $\le M$ lines. However, the formal specification of the CSS objective is directly modeled by minimizing the variance over the space of all valid $M$-partitions.

---

### 4. Mathematical Invariants

To certify the correctness of Blink's line balancer, our formalization proves three core invariants:

1. **Partition Conservation**: Flattening any valid line partition $P = [L_1; L_2; \dots; L_M]$ yields the exact original sequence of input `LineBreakCandidate`s:
   $$\text{concat}(P) = \text{InputCandidates}$$
   No glyphs are dropped, duplicated, or reordered.
2. **Non-Negativity of Score / Variance**: For all partitions $P$ and target widths $\bar{w}$, the computed balance score is strictly non-negative:
   $$\text{Score}(P) \ge 0$$
3. **Determinism**: Given identical input candidates, available width $W_{\max}$, and target line count $M$, the `TextWrapEvaluator` is a pure function that deterministically yields a unique canonical partition $P^*$, resolving ties via a deterministic tie-breaking order (e.g., preferring fuller earlier lines, matching CSS expectations).

---

### 5. Rocq / Coq Formalization (`BlinkTextWrapBalanceSemantics.v`)

Below is the complete, self-contained Rocq (Coq) formalization modeling the data structures, partitioning semantics, objective function, and verified invariants.

```coq
(** * BlinkTextWrapBalanceSemantics.v
    Formalization of Chromium Blink's text-wrap: balance vs CSS Text Level 4 §5.1.
    Agent 52 Audit Artifact. *)

Require Import Coq.Lists.List.
Require Import Coq.Arith.Arith.
Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** Represents an atomic breakable inline unit (word / glyph cluster)
    derived from blink::LineBreakCandidate. *)
Record LineBreakCandidate : Type := mkCandidate {
  cand_id : nat;
  cand_width : Z; (** Width in LayoutUnits (non-negative) *)
}.

(** A Line is a contiguous list of candidates. *)
Definition Line := list LineBreakCandidate.

(** A Partition is a sequence of lines formed from the input text. *)
Definition Partition := list Line.

(** LineBalanceScore represents the variance metric.
    None represents +infinity (an invalid partition that overflows). *)
Definition LineBalanceScore := option Z.

(** Context and configuration for Blink's ScoreLineBreaker / TextWrapEvaluator. *)
Record TextWrapEvaluator : Type := mkEvaluator {
  eval_available_width : Z;
  eval_target_lines : nat;
}.

(** ** 2. Width and Variance Objective Calculations *)

(** Total width of a single line. *)
Fixpoint line_width (l : Line) : Z :=
  match l with
  | [] => 0
  | c :: cs => cand_width c + line_width cs
  end.

(** Total width of all candidates in a list. *)
Definition total_candidates_width (cs : list LineBreakCandidate) : Z :=
  line_width cs.

(** Check if a single line satisfies the available_width constraint. *)
Definition line_fits (avail : Z) (l : Line) : bool :=
  Z.leb (line_width l) avail.

(** Check if all lines in a partition fit within available_width. *)
Definition partition_fits (avail : Z) (p : Partition) : bool :=
  forallb (line_fits avail) p.

(** To avoid rational division in variance sum_{i=1}^M (w_i - W/M)^2,
    we scale by M^2: sum_{i=1}^M (M * w_i - W)^2.
    This preserves exact ordering and non-negativity in Z. *)
Definition scaled_line_deviation_sq (M : Z) (total_W : Z) (l : Line) : Z :=
  let diff := (M * line_width l) - total_W in
  diff * diff.

Fixpoint compute_variance_scaled (M : Z) (total_W : Z) (p : Partition) : Z :=
  match p with
  | [] => 0
  | l :: ls => scaled_line_deviation_sq M total_W l + compute_variance_scaled M total_W ls
  end.

(** Evaluate the score of a partition under a TextWrapEvaluator. *)
Definition evaluate_partition (eval : TextWrapEvaluator) (total_W : Z) (p : Partition) : LineBalanceScore :=
  if andb (Nat.eqb (length p) (eval_target_lines eval))
          (partition_fits (eval_available_width eval) p)
  then Some (compute_variance_scaled (Z.of_nat (eval_target_lines eval)) total_W p)
  else None.

(** ** 3. Line Partitioning Algorithm *)

(** Generate all contiguous splits of a list into a single prefix and suffix. *)
Fixpoint splits {A : Type} (xs : list A) : list (list A * list A) :=
  match xs with
  | [] => [([], [])]
  | x :: xs' => ([], x :: xs') :: map (fun '( l1, l2 ) => (x :: l1, l2)) (splits xs')
  end.

(** Generate all ways to partition `cs` into exactly `k` lines. *)
Fixpoint all_partitions (k : nat) (cs : list LineBreakCandidate) : list Partition :=
  match k with
  | O => match cs with
         | [] => [[]]
         | _  => []
         end
  | S k' =>
      flat_map (fun '(line, rest) =>
        map (fun tail_part => line :: tail_part) (all_partitions k' rest)
      ) (splits cs)
  end.

(** Compare two scores: None is treated as +infinity.
    Returns true if s1 is strictly better than or equal to s2 (preferring earlier in tie-break). *)
Definition score_le (s1 s2 : LineBalanceScore) : bool :=
  match s1, s2 with
  | Some v1, Some v2 => Z.leb v1 v2
  | Some _, None => true
  | None, Some _ => false
  | None, None => true
  end.

(** Select the optimal partition from a list of candidate partitions. *)
Fixpoint select_best_partition
  (eval : TextWrapEvaluator)
  (total_W : Z)
  (ps : list Partition) : option (Partition * LineBalanceScore) :=
  match ps with
  | [] => None
  | p :: ps' =>
      let s := evaluate_partition eval total_W p in
      match select_best_partition eval total_W ps' with
      | None => Some (p, s)
      | Some (best_p, best_s) =>
          if score_le s best_s then Some (p, s) else Some (best_p, best_s)
      end
  end.

(** Top-level balanced line breaking function. *)
Definition balance_lines (eval : TextWrapEvaluator) (cs : list LineBreakCandidate) : option Partition :=
  let total_W := total_candidates_width cs in
  let candidates := all_partitions (eval_target_lines eval) cs in
  match select_best_partition eval total_W candidates with
  | Some (best_p, Some _) => Some best_p
  | _ => None
  end.

(** ** 4. Mathematical Invariants and Proofs *)

(** *** Invariant 1: Non-Negativity of Variance / Score *)

Lemma square_nonneg : forall x : Z, 0 <= x * x.
Proof.
  intro x.
  destruct (Z_le_gt_dec 0 x).
  - apply Z.mul_nonneg_nonneg; lia.
  - assert (0 <= -x) by lia.
    replace (x * x) with ((-x) * (-x)) by ring.
    apply Z.mul_nonneg_nonneg; lia.
Qed.

Theorem variance_nonneg : forall (M total_W : Z) (p : Partition),
  0 <= compute_variance_scaled M total_W p.
Proof.
  intros M total_W p.
  induction p as [| l ls IH].
  - simpl. lia.
  - simpl. unfold scaled_line_deviation_sq.
    pose proof (square_nonneg (M * line_width l - total_W)).
    lia.
Qed.

Theorem evaluate_partition_nonneg : forall eval total_W p score,
  evaluate_partition eval total_W p = Some score ->
  0 <= score.
Proof.
  intros eval total_W p score H.
  unfold evaluate_partition in H.
  destruct (andb (Nat.eqb (length p) (eval_target_lines eval))
                 (partition_fits (eval_available_width eval) p)) eqn:Hcond;
     try discriminate.
  inversion H; subst.
  apply variance_nonneg.
Qed.

(** *** Invariant 2: Partition Conservation (Items Partitioned = Input Items) *)

Lemma splits_conservation : forall {A : Type} (xs l1 l2 : list A),
  In (l1, l2) (splits xs) -> l1 ++ l2 = xs.
Proof.
  intros A xs.
  induction xs as [| x xs' IH]; intros l1 l2 HIn.
  - simpl in HIn. destruct HIn as [Heq | []].
    inversion Heq; subst; reflexivity.
  - simpl in HIn. destruct HIn as [Heq | HInMap].
    + inversion Heq; subst; reflexivity.
    + apply in_map_iff in HIn