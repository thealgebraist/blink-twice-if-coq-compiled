### Audit Report: Agent 195 — Chromium Blink Multicol Column Count vs. CSS Multi-column Layout Level 1 §3.4

#### 1. Column Count Formula & Spec Alignment
Per **CSS Multi-column Layout Module Level 1 §3.4 (Pseudo-algorithm)**, when `column-width` ($W_{\text{col}} > 0$) is specified and `column-count` is `auto`, the resolved number of columns $N$ is determined by:
$$N = \max\left(1, \left\lfloor \frac{W_{\text{avail}} + G}{W_{\text{col}} + G} \right\rfloor\right)$$
where:
* $W_{\text{avail}} \ge 0$ is the available inline size of the multicol container (`used_width`).
* $G \ge 0$ is the resolved `column-gap` (`gap`).
* $W_{\text{col}} > 0$ is the specified `column-width` (`col_width`).

**Chromium Blink Implementation (`third_party/blink/renderer/core/layout/column_layout_algorithm.cc` / `LayoutMultiColumnFlowThread`):**
Blink computes the column count in fixed-point `LayoutUnit` arithmetic using integer truncation division:
```cpp
int computed_count = ((available_width + column_gap) / (column_width + column_gap)).ToInt();
int actual_count = std::max(1, computed_count);
```
Because `LayoutUnit` stores values as multiples of $\frac{1}{64}$ px (integer representation), integer division `a / b` on non-negative `LayoutUnit`s directly computes $\lfloor \frac{a}{b} \rfloor$. The condition $W_{\text{col}} > 0$ and $G \ge 0$ guarantees the denominator $W_{\text{col}} + G \ge 1\text{ LayoutUnit} > 0$, preventing division by zero.

---

#### 2. Key Invariants
1. **Strict Positivity of Column Count ($N \ge 1$):**
   Regardless of how narrow $W_{\text{avail}}$ is (even $W_{\text{avail}} = 0$), the outer $\max(1, \dots)$ ensures a multicol container always generates at least 1 column.
2. **Container Overflow Bound ($N \cdot W_{\text{col}} + (N - 1) \cdot G \le W_{\text{avail}}$ when $W_{\text{avail}} \ge W_{\text{col}}$):**
   When the available width can fit at least one column ($W_{\text{avail}} \ge W_{\text{col}}$), we have $W_{\text{avail}} + G \ge W_{\text{col}} + G$, which implies $\lfloor \frac{W_{\text{avail}} + G}{W_{\text{col}} + G} \rfloor \ge 1$.
   Thus $N = \lfloor \frac{W_{\text{avail}} + G}{W_{\text{col}} + G} \rfloor$. By definition of integer division:
   $$N \cdot (W_{\text{col}} + G) \le W_{\text{avail}} + G \iff N \cdot W_{\text{col}} + (N - 1) \cdot G \le W_{\text{avail}}$$
   This guarantees that the minimum required inline space for $N$ columns of width $W_{\text{col}}$ separated by $N - 1$ gaps of width $G$ never exceeds $W_{\text{avail}}$ before column width stretching ($\text{used } W_{\text{col}} = \lfloor \frac{W_{\text{avail}} - (N-1)G}{N} \rfloor$) is applied.

---

#### 3. Concrete Rocq / Coq Formalization (`BlinkMulticolBalancingSemantics.v`)

```coq
(** * BlinkMulticolBalancingSemantics.v
    Formal Audit of Chromium Blink Multicol Column Count vs. CSS Multi-column 1 §3.4
    Agent 195 *)

From Coq Require Import ZArith Lia.
Open Scope Z_scope.

Section MulticolColumnCount.

  (** ** 1. Definitions *)

  (** Compute resolved column count N per CSS Multi-column 1 §3.4:
      N = max(1, floor((W_avail + gap) / (col_width + gap))) *)
  Definition resolve_column_count (W_avail col_width gap : Z) : Z :=
    Z.max 1 ((W_avail + gap) / (col_width + gap)).

  (** Total minimum inline space occupied by N columns of width [col_width]
      and (N - 1) inter-column gaps of width [gap]. *)
  Definition used_column_space (N col_width gap : Z) : Z :=
    N * col_width + (N - 1) * gap.

  (** ** 2. Invariant Theorems *)

  (** Invariant 1: Resolved column count is always at least 1. *)
  Theorem resolve_column_count_ge_1 :
    forall W_avail col_width gap : Z,
      1 <= resolve_column_count W_avail col_width gap.
  Proof.
    intros W_avail col_width gap.
    unfold resolve_column_count.
    lia.
  Qed.

  (** Helper lemma: When W_avail >= col_width, the quotient is at least 1. *)
  Lemma div_ge_1_when_avail_ge_col :
    forall W_avail col_width gap : Z,
      0 < col_width ->
      0 <= gap ->
      col_width <= W_avail ->
      1 <= (W_avail + gap) / (col_width + gap).
  Proof.
    intros W_avail col_width gap Hcol Hgap Hfit.
    assert (Hdenom : 0 < col_width + gap) by lia.
    replace 1 with ((col_width + gap) / (col_width + gap)).
    - apply Z.div_le_mono; lia.
    - apply Z.div_same; lia.
  Qed.

  (** Invariant 2: When W_avail >= col_width, the used column space
      N * col_width + (N - 1) * gap never exceeds W_avail. *)
  Theorem used_column_space_le_avail :
    forall W_avail col_width gap : Z,
      0 < col_width ->
      0 <= gap ->
      col_width <= W_avail ->
      let N := resolve_column_count W_avail col_width gap in
      used_column_space N col_width gap <= W_avail.
  Proof.
    intros W_avail col_width gap Hcol Hgap Hfit N.
    unfold N, resolve_column_count, used_column_space.
    pose proof (div_ge_1_when_avail_ge_col W_avail col_width gap Hcol Hgap Hfit) as Hq_ge_1.
    set (q := (W_avail + gap) / (col_width + gap)) in *.
    assert (Hmax : Z.max 1 q = q) by lia.
    rewrite Hmax.
    assert (Hdenom : col_width + gap > 0) by lia.
    pose proof (Z.mul_div_le (W_avail + gap) (col_width + gap) Hdenom) as Hmul.
    fold q in Hmul.
    (* Ring rearrangement: q * col_width + (q - 1) * gap = q * (col_width + gap) - gap *)
    assert (Hrew : q * col_width + (q - 1) * gap = q * (col_width + gap) - gap) by lia.
    lia.
  Qed.

  (** Invariant 3: Maximality of N — adding one more column strictly exceeds W_avail. *)
  Theorem next_column_count_exceeds_avail :
    forall W_avail col_width gap : Z,
      0 < col_width ->
      0 <= gap ->
      col_width <= W_avail ->
      let N := resolve_column_count W_avail col_width gap in
      W_avail < used_column_space (N + 1) col_width gap.
  Proof.
    intros W_avail col_width gap Hcol Hgap Hfit N.
    unfold N, resolve_column_count, used_column_space.
    pose proof (div_ge_1_when_avail_ge_col W_avail col_width gap Hcol Hgap Hfit) as Hq_ge_1.
    set (q := (W_avail + gap) / (col_width + gap)) in *.
    assert (Hmax : Z.max 1 q = q) by lia.
    rewrite Hmax.
    assert (Hdenom : col_width + gap > 0) by lia.
    pose proof (Z.div_mod (W_avail + gap) (col_width + gap) (Z.gt_lt_iff _ _ |-> Hdenom)) as Hdivmod.
    pose proof (Z.mod_pos_bound (W_avail + gap) (col_width + gap) (Z.gt_lt _ _ Hdenom)) as Hmod.
    fold q in Hdivmod.
    lia.
  Qed.

End MulticolColumnCount.
```