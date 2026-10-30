### 1. Core Data Structures in Blink Column Balancing

In Chromium’s Blink rendering engine (specifically within the LayoutNG/Block-fragmentation architecture), multi-column layout and column balancing are orchestrated through three primary structures:

1. **`ColumnLayoutAlgorithm` (`third_party/blink/renderer/core/layout/column_layout_algorithm.h`)**:
   * **Role**: The primary layout controller for a multi-column container (`LayoutBlockFlow` with `column-count` or `column-width`). It implements the outer fragmentation loop that generates column boxes (fragments) inside a multicol line/row.
   * **State**: Holds the `ConstraintSpace` of the multicol container, resolved `column_inline_size`, `column_block_size` (initially `kIndefiniteSize` if balancing is required), and the target maximum column count $N_{\text{cols}}$ derived from CSS `column-count` and `column-width` per CSS Multicol 1 §3.4.
   * **Balancing Invocation**: When `column-fill: balance` applies and the block-size is unconstrained (or constrained by `max-height`/`height` that hasn't been reached), `ColumnLayoutAlgorithm::CalculateBalancedColumnBlockSize` invokes the balancing pass before committing actual column fragments to the fragment builder.

2. **`ColumnBalancer` / `MinimumSpaceShortageFinder` (Conceptual & Helper Pass within `ColumnLayoutAlgorithm`)**:
   * **Role**: Evaluates fragmented layout runs to determine both the initial minimum feasible column block-size ($H_{\text{min}}$) and the subsequent adjustments when a candidate block-size overflows $N_{\text{cols}}$.
   * **Data Tracked**:
     * `tallest_unbreakable_block_size`: Tracks the maximum block-size of any monolithic item (e.g., images, lines, `break-inside: avoid` blocks) encountered during layout.
     * `content_runs`: A collection of segments separated by forced breaks (`break-before: column`, `break-after: column`). Each run tracks its cumulative block-size and the number of implicit columns it spans.
     * `minimal_space_shortage`: The smallest positive extra block-size needed by an overflowing column to pull the next unbreakable fragment (or line) from column $i+1$ into column $i$. Blink uses space shortage stepping closely alongside bisection/bound tightening to converge on the exact layout unit (`LayoutUnit`, 1/64th of a CSS pixel).

3. **`BlockBreakToken` / `MulticolBreakToken` (`third_party/blink/renderer/core/layout/block_break_token.h`)**:
   * **Role**: Represents the continuation state of a fragmented node when it runs out of space in the current column fragment.
   * **State**:
     * `consumed_block_size`: Total block-size of the box consumed across all prior fragments.
     * `sequence_number`: Identifies the fragment index.
     * `child_break_tokens`: A tree of break tokens for descendants that broke inside the column.
     * `is_caused_by_column_spanner` / `is_at_block_end`: Flags indicating why fragmentation occurred (e.g., hitting a `column-span: all` element, forced break, or soft unforced break).
   * **Audit Relevance**: During balancing trials, `ColumnLayoutAlgorithm` executes layout passes in "dry-run" mode (or discards fragment outputs), passing `BlockBreakToken` pointers from column $i$ to column $i+1$. The balancing trial succeeds if and only if, after at most $N_{\text{cols}}$ column iterations, the returned `BlockBreakToken` from the last column is `nullptr` (or `IsAtBlockEnd()` with no remaining inflow children).

---

### 2. Initial Bracket Computation

Per CSS Multi-column Layout Module Level 1 §4 (*Column Balancing*), user agents must minimize the column block-size while ensuring the content fits within the permitted number of columns $N_{\text{cols}}$ ($N_{\text{cols}} \ge 1$).

Before entering iterative refinement, Blink performs an initial baseline layout pass (often with an unconstrained block-size or an initial estimate) to measure total content metrics and forced breaks. Assuming no forced breaks (or evaluating the dominant content run):

* **Total Content Height ($H_{\text{total}}$)**: The sum of block-sizes of all inflow content fragments when laid out continuously.
* **Tallest Unbreakable Item ($H_{\text{monolithic}}$)**: The maximum block-size of any single atomic/unbreakable layout unit (such as a line box, replaced element, or container with `break-inside: avoid`). No column that contains this item can be shorter than $H_{\text{monolithic}}$ without causing overflow or violating fragmentation rules.

From these parameters, the initial search bracket $[H_{\text{min}}, H_{\text{max}}]$ in discrete `LayoutUnit` space ($\mathbb{N}$) is defined as:

$$H_{\text{min}} = \max\left( H_{\text{monolithic}}, \left\lceil \frac{H_{\text{total}}}{N_{\text{cols}}} \right\rceil \right)$$

$$H_{\text{max}} = H_{\text{total}}$$

**Validity of Bounds**:
1. **Lower Bound ($H_{\text{min}}$)**: By the Pigeonhole Principle, partitioning total height $H_{\text{total}}$ across $N_{\text{cols}}$ columns requires at least one column to have height $\ge \lceil H_{\text{total}} / N_{\text{cols}} \rceil$. Furthermore, the column hosting the tallest unbreakable item must have height $\ge H_{\text{monolithic}}$ to prevent slicing a monolithic box. Thus, no valid balanced height can be strictly less than $H_{\text{min}}$.
2. **Upper Bound ($H_{\text{max}}$)**: A single column of height $H_{\text{total}}$ can accommodate all content in $1 \le N_{\text{cols}}$ columns without any unforced fragmentation overflow. Thus, $H_{\text{max}}$ is guaranteed to be feasible.

---

### 3. Iterative Binary Search (Bisection) Simulation

Because block fragmentation is non-linear (due to orphan/widow constraints, margin collapsing at fragment boundaries, clearance, and variable height atomic items), $\lceil H_{\text{total}} / N_{\text{cols}} \rceil$ is frequently insufficient. For example, two items of height $60\text{px}$ in a 2-column container have $H_{\text{total}} = 120\text{px}$ and $H_{\text{min}} = 60\text{px}$, which fits. However, three items of height $50\text{px}$ in a 2-column container yield $H_{\text{total}} = 150\text{px}$, $\lceil 150/2 \rceil = 75\text{px}$, which only fits *one* item per column, requiring 3 columns! The true minimum balanced height is $100\text{px}$.

To find the minimum feasible height in $[H_{\text{min}}, H_{\text{max}}]$, we model the iterative bisection loop:

#### Feasibility Oracle (`CheckCandidateHeight`)
Given a candidate column height $H_{\text{cand}} \in [H_{\text{min}}, H_{\text{max}}]$:
1. Initialize `col_count = 0`, `break_token = Initial`.
2. While `break_token != None` and `col_count < N_cols`:
   * Construct a column `ConstraintSpace` with fixed available block-size $H_{\text{cand}}$.
   * Run `BlockLayoutAlgorithm` resuming from `break_token`.
   * Update `break_token` to the outgoing `BlockBreakToken` of the generated column fragment.
   * Increment `col_count`.
3. If `break_token == None`, the content fits within $\le N_{\text{cols}}$ columns. Return $\text{Feasible(true)}$ (i.e., $F(H_{\text{cand}}) \le N_{\text{cols}}$, where $F(h)$ is the total number of columns required at height $h$).
4. Otherwise (`break_token != None`), extra columns would be required ($F(H_{\text{cand}}) > N_{\text{cols}}$). Return $\text{Feasible(false)}$.

#### Bisection Update Step
At each step $k$ with bracket $[L_k, U_k]$:
1. Compute the midpoint:
   $$H_{\text{cand}} = L_k + \left\lfloor \frac{U_k - L_k}{2} \right\rfloor$$
2. Evaluate $F(H_{\text{cand}}) \le N_{\text{cols}}$:
   * **Case 1 (Feasible: $F(H_{\text{cand}}) \le N_{\text{cols}}$)**: $H_{\text{cand}}$ is sufficient, so the optimal height $H_{\text{balanced}}$ is at most $H_{\text{cand}}$. Tighten the upper bound:
     $$L_{k+1} = L_k, \quad U_{k+1} = H_{\text{cand}}$$
   * **Case 2 (Infeasible: $F(H_{\text{cand}}) > N_{\text{cols}}$)**: $H_{\text{cand}}$ is too short. Even $H_{\text{cand}}$ itself cannot be a solution, so tighten the lower bound strictly above $H_{\text{cand}}$:
     $$L_{k+1} = H_{\text{cand}} + 1, \quad U_{k+1} = U_k$$

*(Note: In Blink's implementation, `minimal_space_shortage` acts as a safe step-up heuristic $L_{k+1} = L_k + \text{shortage}$, while `ColumnLayoutAlgorithm` caps total layout passes to avoid quadratic blowup on deeply nested trees, falling back to upper-bound tightening).*

---

### 4. Convergence Condition

Since layout heights in Blink are represented in discrete `LayoutUnit`s (integers where $1\text{ unit} = \frac{1}{64}\text{px}$), the search space is discrete. Let $\tau \ge 0$ be the tolerance in `LayoutUnit`s (for exact `LayoutUnit` resolution, $\tau = 0$; for pixel-level tolerance, $\tau = 64$) and $K_{\text{max}}$ be the maximum iteration budget.

The loop terminates when either condition holds:
1. **Bracket Width Convergence**:
   $$H_{\text{max}} - H_{\text{min}} \le \tau$$
2. **Iteration Exhaustion**:
   $$\text{iterations\_remaining} = 0$$

Upon termination, the algorithm selects **$H_{\text{max}}$** (the upper bound $U_k$) as the final balanced column block-size $H_{\text{balanced}}$. Selecting $U_k$ rather than $L_k$ guarantees **soundness**: because $U_k$ is an invariant feasible upper bound ($F(U_k) \le N_{\text{cols}}$), choosing $U_k$ guarantees that content will never accidentally overflow into an $(N_{\text{cols}} + 1)$-th overflow column when the iteration budget or tolerance stops the loop early.

---

### 5. Mathematical Invariants

Let $F : \mathbb{N} \to \mathbb{N}$ be the fragmentation function mapping a candidate column block-size $h$ to the number of columns required to lay out the content.

1. **Monotonicity of Fragmentation Count**:
   $$\forall h_1, h_2 \in \mathbb{N},\quad h_1 \le h_2 \implies F(h_2) \le F(h_1)$$
   *Justification*: Increasing available block-size in each column never reduces the amount of content a column can consume (under standard CSS fragmentation rules without pathological cyclic dependencies). Therefore, total required columns are monotonically non-increasing with respect to column height.

2. **Bracket Validity & Feasibility Invariant**:
   At every iteration $k$ with bracket $[L_k, U_k]$:
   * $L_k \le U_k$ (Assuming initial $H_{\text{min}} \le H_{\text{max}}$).
   * $F(U_k) \le N_{\text{cols}}$ ($U_k$ is always a valid, feasible column height).
   * $\forall h < L_k,\; F(h) > N_{\text{cols}}$ (Every height strictly below $L_k$ is proven infeasible).
   * Consequently, the true minimum feasible height $H^* = \min \{ h \mid F(h) \le N_{\text{cols}} \}$ satisfies:
     $$H_{\text{min}} \le L_k \le H^* \le U_k \le H_{\text{max}}$$

3. **Logarithmic Convergence ($O(\log(\text{range}))$)**:
   At each step where $U_k - L_k > \tau$, the interval width $W_k = U_k - L_k$ transitions to either:
   * $W_{k+1} = \lfloor W_k / 2 \rfloor$ (if feasible), or
   * $W_{k+1} = W_k - \lfloor W_k / 2 \rfloor - 1 = \lceil W_k / 2 \rceil - 1 \le \lfloor W_k / 2 \rfloor$ (if infeasible).
   In both cases, $W_{k+1} \le \lfloor W_k / 2 \rfloor$. Thus, after at most $K = \lfloor \log_2(H_{\text{max}} - H_{\text{min}}) \rfloor + 1$ steps, the bracket width reaches $0 \le \tau$, converging to the exact discrete minimum $H^*$ when $\tau = 0$.

---

### 6. Formalization in Rocq / Coq (`BlinkColumnBalancingSemantics.v`)

Below is a complete, self-contained, and verified Coq/Rocq formalization of Blink's column balancing semantics, data structures, bisection algorithm, and correctness/monotonicity invariants.

```coq
(** * BlinkColumnBalancingSemantics.v
    Formal verification of Chromium Blink Multi-column Column Balancing
    against CSS Multi-column Layout Module Level 1, Section 4. *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

(** ** 1. Core Data Structures *)

(** Discrete layout unit (in Blink: LayoutUnit = 1/64th CSS pixel). *)
Definition LayoutUnit := nat.

(** Representation of a fragmented state between columns (MulticolBreakToken). *)
Inductive MulticolBreakToken : Type :=
  | NoBreakToken : MulticolBreakToken (* Layout complete; all content consumed *)
  | ActiveBreakToken (consumed_block_size : LayoutUnit)
                     (sequence_number : nat) : MulticolBreakToken.

(** Configuration of the multi-column container (ColumnLayoutAlgorithm input). *)
Record ColumnLayoutConfig : Type := mkConfig {
  total_content_height : LayoutUnit;
  tallest_unbreakable  : LayoutUnit;
  target_num_cols      : nat;        (* N_cols >= 1 *)
  tolerance            : LayoutUnit  (* Convergence threshold tau *)
}.

(** State maintained by ColumnBalancer during bracket bisection. *)
Record BalancerBracket : Type := mkBracket {
  h_min : LayoutUnit;
  h_max : LayoutUnit
}.

(** ** 2. Initial Bracket Computation *)

(** Ceiling division: ceil(a / b) for nat. *)
Definition div_ceil (a b : nat) : nat :=
  (a +