### Audit Report: Agent 207 — Chromium Blink Column Fill Balance vs. CSS Multi-column Layout Module Level 1 §7

#### 1. Balanced Height Formula & Specification Analysis
According to **CSS Multi-column Layout Module Level 1 §7 (`column-fill`)**, when `column-fill: balance` (or `balance-all`) is applied to a multi-column container with $N$ columns ($N \ge 1$) and an unconstrained block-size, the User Agent must minimize the column block-size while dividing content as equally as possible across the columns.

In Chromium Blink's LayoutNG (`NGColumnLayoutAlgorithm`), layout measurements are represented in discrete subpixel units (`LayoutUnit`, isomorphic to non-negative integers $\mathbb{N}$). Ignoring fragmentation struts (atomic inlines, break-avoidance) for the baseline initial column height estimation, the theoretical ideal balanced column height $H_{\text{col}}$ is derived via integer ceiling division bounded below by $1$ layout unit (to guarantee forward layout progress):

$$H_{\text{col}} = \max\left(1, \left\lfloor \frac{H_{\text{total}} + N - 1}{N} \right\rfloor\right)$$

Where:
* $H_{\text{total}} \in \mathbb{N}$ is the `total_content_height` (total block-size of the flow thread).
* $N \in \mathbb{N}^+$ ($N \ge 1$) is the computed `column-count`.

---

#### 2. Core Invariants
To satisfy CSS Multicol §7 without overflow or infinite fragmentation loops, Blink's baseline height computation enforces two core mathematical invariants for all $N \ge 1$:

1. **Capacity Sufficiency Invariant:** 
   $$N \cdot H_{\text{col}} \ge H_{\text{total}}$$
   The aggregate block-size across all $N$ columns is guaranteed to accommodate the entire unfragmented content height.

2. **Minimality Invariant (Tightest Upper Bound):**
   $$\forall h \in \mathbb{N}, \quad (h \ge 1 \land N \cdot h \ge H_{\text{total}}) \implies H_{\text{col}} \le h$$
   $H_{\text{col}}$ is the minimal positive integer height capable of containing $H_{\text{total}}$ across $N$ columns. If $H_{\text{total}} > 0$, any strictly smaller column height $h < H_{\text{col}}$ results in an underflow ($N \cdot h < H_{\text{total}}$), causing content to overflow into extra overflow columns.

---

#### 3. Formal Verification in Rocq / Coq (`BlinkMulticolColumnFillSemantics.v`)

Below is the self-contained, fully mechanized Rocq (Coq) formalization verifying the Blink column balance formula and its invariants.

```coq
(** * BlinkMulticolColumnFillSemantics.v
    Formal Audit of Chromium Blink Column Fill Balance (CSS Multicol 1 §7)
    Agent 207 Verification Module *)

From Coq Require Import Arith PeanoNat Lia.

Module BlinkMulticolColumnFillSemantics.

  (** ** 1. Definitions *)

  (** [balanced_col_height total_content_height N] computes the initial
      balanced column block-size in discrete layout units:
      H_col = max(1, (total_content_height + N - 1) / N) *)
  Definition balanced_col_height (total_content_height N : nat) : nat :=
    Nat.max 1 ((total_content_height + N - 1) / N).

  (** Predicate stating that a given column height [h] is valid (positive)
      and provides sufficient aggregate capacity across [N] columns. *)
  Definition is_sufficient_height (total_content_height N h : nat) : Prop :=
    h >= 1 /\ N * h >= total_content_height.

  (** ** 2. Helper Lemmas on Euclidean Ceiling Division *)

  Lemma ceil_div_mul_ge : forall (A N : nat),
    N >= 1 ->
    N * ((A + N - 1) / N) >= A.
  Proof.
    intros A N HN.
    pose proof (Nat.div_mod (A + N - 1) N ltac:(lia)) as Hdiv.
    pose proof (Nat.mod_upper_bound (A + N - 1) N ltac:(lia)) as Hmod.
    lia.
  Qed.

  Lemma ceil_div_minimal : forall (A N h : nat),
    N >= 1 ->
    N * h >= A ->
    (A + N - 1) / N <= h.
  Proof.
    intros A N h HN Hcap.
    pose proof (Nat.div_mod (A + N - 1) N ltac:(lia)) as Hdiv.
    pose proof (Nat.mod_upper_bound (A + N - 1) N ltac:(lia)) as Hmod.
    (* If (A + N - 1) / N > h, then (A + N - 1) / N >= h + 1,
       which implies A + N - 1 >= N * (h + 1) = N * h + N, contradicting N * h >= A. *)
    nia.
  Qed.

  (** ** 3. Main Invariant Theorems *)

  (** Theorem 1: H_col is strictly positive (>= 1), guaranteeing layout progress. *)
  Theorem balanced_col_height_pos : forall (total_content_height N : nat),
    balanced_col_height total_content_height N >= 1.
  Proof.
    intros total_content_height N.
    unfold balanced_col_height.
    lia.
  Qed.

  (** Theorem 2 (Capacity Invariant): N * H_col >= total_content_height. *)
  Theorem balanced_col_height_sufficient : forall (total_content_height N : nat),
    N >= 1 ->
    N * balanced_col_height total_content_height N >= total_content_height.
  Proof.
    intros total_content_height N HN.
    unfold balanced_col_height.
    pose proof (ceil_div_mul_ge total_content_height N HN) as Hceil.
    pose proof (Nat.le_max_r 1 ((total_content_height + N - 1) / N)) as Hmax.
    nia.
  Qed.

  (** Theorem 3 (Minimality Invariant): H_col is the minimal positive integer
      height that accommodates all content across N columns. *)
  Theorem balanced_col_height_minimal : forall (total_content_height N h : nat),
    N >= 1 ->
    is_sufficient_height total_content_height N h ->
    balanced_col_height total_content_height N <= h.
  Proof.
    intros total_content_height N h HN [Hh_pos Hh_cap].
    unfold balanced_col_height.
    apply Nat.max_lub.
    - exact Hh_pos.
    - apply ceil_div_minimal; assumption.
  Qed.

  (** Theorem 4 (Strict Underflow Below H_col): For non-empty content, any height
      strictly less than H_col fails to accommodate total_content_height. *)
  Theorem balanced_col_height_tight : forall (total_content_height N h : nat),
    N >= 1 ->
    total_content_height >= 1 ->
    h < balanced_col_height total_content_height N ->
    N * h < total_content_height.
  Proof.
    intros total_content_height N h HN Hcontent Hlt.
    unfold balanced_col_height in Hlt.
    pose proof (Nat.div_mod (total_content_height + N - 1) N ltac:(lia)) as Hdiv.
    pose proof (Nat.mod_upper_bound (total_content_height + N - 1) N ltac:(lia)) as Hmod.
    (* By cases on whether max(1, ceil) is 1 or ceil *)
    destruct (Nat.max_dec 1 ((total_content_height + N - 1) / N)) as [Hmax1 | Hmax2];
      rewrite Hmax1 in Hlt || rewrite Hmax2 in Hlt; nia.
  Qed.

  (** Corollary: Complete Specification Soundness *)
  Corollary blink_column_fill_balance_sound : forall (total_content_height N : nat),
    N >= 1 ->
    let H_col := balanced_col_height total_content_height N in
    is_sufficient_height total_content_height N H_col /\
    (forall h : nat, is_sufficient_height total_content_height N h -> H_col <= h).
  Proof.
    intros total_content_height N HN H_col.
    split.
    - split.
      + apply balanced_col_height_pos.
      + apply balanced_col_height_sufficient; exact HN.
    - intros h Hsuff.
      apply balanced_col_height_minimal; assumption.
  Qed.

End BlinkMulticolColumnFillSemantics.
```