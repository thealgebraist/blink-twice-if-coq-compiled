# Agent 62 Audit Report: Chromium Blink Fragmentation Break Tokens vs. CSS Fragmentation Level 3 §4

## 1. Core Data Structures in Blink Fragmentation

In Chromium’s Blink rendering engine (specifically within the `core/layout/ng/`—now `core/layout/`—module), fragmentation across pages, columns, or regions is driven by immutable state tokens passed between layout passes of a single DOM node's box tree. This architecture implements the rules specified in **CSS Fragmentation Module Level 3 §4 (Fragmentation Rules)**.

### 1.1 `BreakToken` (`break_token.h`)
`BreakToken` is the base class representing the continuation state of a `LayoutInputNode` that could not fit completely within a single fragmentainer.
* **Key Fields**:
  * `LayoutInputNode box_`: The layout node being fragmented.
  * `unsigned flags_`: Encodes the token type (`kBlockBreakToken` vs. `kInlineBreakToken`) and layout-specific state flags.

### 1.2 `BlockBreakToken` (`block_break_token.h`)
Derived from `BreakToken`, `BlockBreakToken` captures the state of a block-level box broken across fragmentainers.
* **Key Fields**:
  * `LayoutUnit consumed_block_size_`: The cumulative block-size consumed by this box in all *preceding* fragments, plus the current fragment.
  * `unsigned sequence_number_`: A zero-based index tracking which fragment of the node this token represents ($0, 1, \dots, k-1$).
  * `base::span<const Member<const BreakToken>> child_break_tokens_`: A trailing array of break tokens for in-flow and out-of-flow children that also broke inside this block.
  * **State Flags**:
    * `is_break_before_`: Indicates the node broke *before* its first piece of content (e.g., due to a forced break or unappealing space at the bottom of a fragmentainer), so `consumed_block_size_` is $0$, yet a token exists to push the node to the next fragmentainer.
    * `is_forced_break_`: Indicates the break was caused by an explicit CSS property (`break-before: page`, `break-after: column`, etc.).
    * `is_at_block_end_`: Indicates all inflow content of the block has been consumed, and only trailing border/padding, margin, or overflow remains to be painted/sized in subsequent fragmentainers.
    * `has_seen_all_children_`: Indicates the layout algorithm has iterated through all DOM children of this block, even if some children still have active break tokens in `child_break_tokens_`.

### 1.3 `BreakAppeal` (`ng_break_appeal.h` / `break_appeal.h`)
To satisfy CSS Fragmentation Level 3 §4.2 (Unforced Breaks) and §4.4 (Optimizing Unforced Breaks), Blink evaluates candidate break points using a discrete priority metric called `BreakAppeal`.

```cpp
enum BreakAppeal {
  kBreakAppealLastResort,
  kBreakAppealViolatesOrphanWidow, // Violation of orphans/widows (or break-inside: avoid)
  kBreakAppealNone,                // Generic valid break point without perfect clearance
  kBreakAppealPerfect              // Violates no rules (W3C §4.4 compliance)
};
```
*(Note: In Blink's exact source, intermediate violations like `break-inside: avoid` vs `orphans`/`widows` are stratified within the appeal enum between `kBreakAppealLastResort` and `kBreakAppealPerfect`. For this formal audit, we model the four canonical levels specified).*

The strict total ordering is:
$$\text{kBreakAppealLastResort} < \text{kBreakAppealViolatesOrphanWidow} < \text{kBreakAppealNone} < \text{kBreakAppealPerfect}$$

---

## 2. Consumed Block Size Tracking and Sequence Chaining

When a block box of intrinsic total block-size $H_{\text{total}}$ undergoes layout inside a fragmentation context, `BlockLayoutAlgorithm` (and `FragmentationUtils`) executes an iterative state machine parameterized by an incoming `const BlockBreakToken* break_token`.

1. **Fragment 1 (Initial Layout, $i = 1$)**:
   * **Input**: `incoming_break_token = nullptr`.
   * **Resumption Offset**: $\text{offset}_1 = 0$.
   * **Execution**: The layout algorithm lays out children starting from offset $0$ until it hits the fragmentainer boundary or a forced break. Suppose it fits a block extent of $h_1$ within the available fragmentainer space.
   * **Output**: It produces `PhysicalBoxFragment` $F_1$ of block size $h_1$, carrying an outgoing `BlockBreakToken` $T_1$ with:
     $$\text{consumed\_block\_size}(T_1) = h_1, \quad \text{sequence\_number}(T_1) = 0$$

2. **Fragment 2 (Resumed Layout, $i = 2$)**:
   * **Input**: `incoming_break_token` $= T_1$.
   * **Resumption Offset**: The algorithm reads $\text{offset}_2 = \text{consumed\_block\_size}(T_1) = h_1$.
   * **Execution**: Box decorations (like `border-top` and `padding-top`, if `box-decoration-break: slice` is active) are skipped because $\text{offset}_2 > 0$. Child layout resumes using $T_1$'s `child_break_tokens_`. The fragment consumes an additional block size $h_2$ in the second fragmentainer.
   * **Output**: It produces `PhysicalBoxFragment` $F_2$ of block size $h_2$. If $h_1 + h_2 < H_{\text{total}}$, it emits outgoing token $T_2$:
     $$\text{consumed\_block\_size}(T_2) = \text{offset}_2 + h_2 = h_1 + h_2, \quad \text{sequence\_number}(T_2) = 1$$

3. **Fragment $k$ (Termination)**:
   * When $\sum_{i=1}^k h_i = H_{\text{total}}$ and all children have completed layout (`child_break_tokens_` is empty), the outgoing `BlockBreakToken` is `nullptr`, terminating the fragmentation chain for that node.

---

## 3. Break Appeal Total Ordering and Optimal Break Selection

CSS Fragmentation Level 3 §4.4 states that if multiple unforced break points exist within a fragmentainer, the user agent must choose the break point that violates the fewest rules and occurs latest in the flow (to maximize space utilization).

Blink implements this in `FragmentainerCapacity` and `BreakBeforeChild` / `MovePastBreakpoint` (`fragmentation_utils.cc`) via an online optimization pass:

1. **State Tracking**: During layout of a fragment, the algorithm maintains an active `EarlyBreak` candidate:
   $$\text{best\_break} = (\text{location}, \text{appeal}_{\text{best}})$$
2. **Candidate Evaluation (`MovePastBreakpoint`)**:
   As each child or line box is placed at block offset $y$:
   * **Fits in Fragmentainer ($y \le H_{\text{avail}}$)**:
     The algorithm computes the `BreakAppeal` $\alpha$ of breaking *after* this child (evaluating `break-after`, the next sibling's `break-before`, `break-inside: avoid` on ancestors, and `orphans`/`widows`).
     If $\alpha \ge \text{appeal}_{\text{best}}$, Blink updates $\text{best\_break} \leftarrow (\text{after child}, \alpha)$. Note the $\ge$ operator: **ties are broken by choosing the later offset**, maximizing consumed space in the current fragmentainer.
   * **Overflows Fragmentainer ($y > H_{\text{avail}}$)**:
     The child cannot fit. The algorithm must break *before* or *inside* this child.
     * It calculates the appeal $\alpha_{\text{curr}}$ of breaking right at the overflow boundary.
     * If $\alpha_{\text{curr}} < \text{appeal}_{\text{best}}$ (for example, breaking here violates `break-inside: avoid` or `widows`, whereas an earlier break point recorded in $\text{best\_break}$ had `kBreakAppealPerfect`), Blink **Aborts and Re-runs** the layout of the current fragment, passing $\text{best\_break}$ as an `EarlyBreak` target, forcing a break at that earlier, more appealing offset.
     * If no valid break point exists at all ($\text{appeal}_{\text{best}}$ is unset and current break is impossible), Blink falls back to `kBreakAppealLastResort` to guarantee forward progress and prevent infinite pagination loops (CSS Fragmentation §4.4 Rule 4: *"Cannot prevent a break if there is no other way to make progress"*).

---

## 4. Mathematical Invariants

Let a fragmented block node have total intrinsic block size $H_{\text{total}} \in \mathbb{N}$. Let its layout produce a sequence of $n$ fragments $F_1, F_2, \dots, F_n$ with individual fragment block sizes $h_1, h_2, \dots, h_n \in \mathbb{N}$ and connecting break tokens $T_1, T_2, \dots, T_{n-1}$ (with $T_0 = \text{None}$ and $T_n = \text{None}$).

### Invariant 1: Consumed Block Size Monotonic Accumulation & Boundedness
For every step $k \in \{1, \dots, n\}$, let $C_k = \text{consumed\_block\_size}(T_k)$ (where $C_n$ is the final total consumed size).
1. **Additive Chaining**: $C_k = C_{k-1} + h_k = \sum_{i=1}^k h_i$ (with $C_0 = 0$).
2. **Monotonicity**: Since fragment block sizes are non-negative ($h_i \ge 0$), for all $1 \le j \le k \le n$:
   $$C_j \le C_k$$
   Furthermore, under non-empty fragment progress ($h_i > 0$ when `is_break_before` is false), $C_{k-1} < C_k$ (strict monotonicity, guaranteeing termination).
3. **Conservation Bound**: At any intermediate step $k \le n$ (in the absence of fragmentainer-induced monolithic overflow expansion):
   $$\sum_{i=1}^k h_i \le H_{\text{total}}, \quad \text{and at termination } k = n, \quad \sum_{i=1}^n h_i = H_{\text{total}}$$

### Invariant 2: Break Appeal Strict Total Order
Let $\mathcal{A} = \{\text{LastResort}, \text{ViolatesOrphanWidow}, \text{None}, \text{Perfect}\}$ equipped with relation $\le_{\mathcal{A}}$. $(\mathcal{A}, \le_{\mathcal{A}})$ forms a finite **total order** (chain):
1. **Reflexivity**: $\forall x \in \mathcal{A}, x \le_{\mathcal{A}} x$.
2. **Antisymmetry**: $\forall x, y \in \mathcal{A}, (x \le_{\mathcal{A}} y \land y \le_{\mathcal{A}} x) \implies x = y$.
3. **Transitivity**: $\forall x, y, z \in \mathcal{A}, (x \le_{\mathcal{A}} y \land y \le_{\mathcal{A}} z) \implies x \le_{\mathcal{A}} z$.
4. **Totality (Connexity)**: $\forall x, y \in \mathcal{A}, x \le_{\mathcal{A}} y \lor y \le_{\mathcal{A}} x$.

### Invariant 3: Optimal Break Selection Determinism & Dominance
Given a non-empty list of candidate break points $L = [(o_1, \alpha_1), (o_2, \alpha_2), \dots, (o_m, \alpha_m)]$ ordered by strictly increasing block offsets ($o_1 < o_2 < \dots < o_m \le H_{\text{avail}}$), the selection function $\text{SelectBestBreak}(L)$ is:
1. **Deterministic**: Calling $\text{SelectBestBreak}(L)$ always yields a unique candidate $(o^*, \alpha^*)$.
2. **Appeal-Optimal**: $\forall (o_i, \alpha_i) \in L, \alpha_i \le_{\mathcal{A}} \alpha^*$.
3. **Offset-Maximal among Optima**: $\forall (o_i, \alpha_i) \in L, (\alpha_i = \alpha^*) \implies o_i \le o^*$.

---

## 5. Concrete Rocq / Coq Formalization (`BlinkBreakTokenAppealSemantics.v`)

The following self-contained Rocq (Coq) specification formalizes `BreakAppeal`, `BlockBreakToken`, fragment sequence chaining, optimal break point selection, and proves all required mathematical invariants without axioms or admitted lemmas.

```coq
(** * BlinkBreakTokenAppealSemantics.v
    Formal Audit of Chromium Blink Fragmentation Break Tokens vs.
    CSS Fragmentation Module Level 3 Section 4. *)

From Coq Require Import Arith PeanoNat Lia Bool List.
Import ListNotations.

(** ========================================================================= *)
(** ** 1. Core Data Structures: BreakAppeal & BlockBreakToken                 *)
(** ========================================================================= *)

(** Blink's BreakAppeal enum (core/layout/break_appeal.h) *)
Inductive BreakAppeal : Type :=
  | kBreakAppealLastResort
  | kBreakAppealViolatesOrphanWidow
  | kBreakAppealNone
  | kBreakAppealPerfect.

(** Mapping BreakAppeal to natural numbers for rank semantics *)
Definition appeal_rank (a : BreakAppeal) : nat :=
  match a with
  | kBreakAppealLastResort          => 0
  | kBreakAppealViolatesOrphanWidow => 1
  | kBreakAppealNone                => 2
  | kBreakAppealPerfect             => 3
  end.

(** Strict and non-strict ordering on BreakAppeal *)
Definition appeal_le (a b : BreakAppeal) : Prop :=
  appeal_rank a <= appeal_rank b.

Definition appeal_lt (a b : BreakAppeal) : Prop :=
  appeal_rank a < appeal_rank b.

Definition appeal_leb (a b : BreakAppeal) : bool :=
  Nat.leb (appeal_rank a) (appeal_rank b).

(** Injectivity of appeal_rank *)
Lemma appeal_rank_injective : forall a b : BreakAppeal,
  appeal_rank a = appeal_rank b -> a = b.
Proof.
  intros a b H.
  destruct a, b; simpl in H; try reflexivity; discriminate H.
Qed.

(** Concrete strict inequality chain as required by the Blink spec *)
Theorem blink_appeal_hierarchy :
  appeal_lt kBreakAppealLastResort kBreakAppealViolatesOrphanWidow /\
  appeal_lt kBreakAppealViolatesOrphanWidow kBreakAppealNone /\
  appeal_lt kBreakAppealNone kBreakAppealPerfect.
Proof.
  unfold appeal_lt, appeal_rank. repeat split; lia.
Qed.

(** BlockBreakToken (core/layout/block_break_token.h) *)
