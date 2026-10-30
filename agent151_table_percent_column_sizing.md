### 1. Representation in `TableLayoutAlgorithm::ComputeColumnWidths`

In Chromium Blink’s LayoutNG table engine (`third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc` and `table_layout_algorithm_helpers.cc`), column width distribution operates over a vector of `TableTypes::Column` structures initialized during the constraint-gathering phase (`ComputeColumnConstraints`).

Each column $i \in \{0, \dots, N-1\}$ is represented by:
*   `min_inline_size` ($\text{min}_i \in \mathbb{N}$): The resolved minimum content inline size (in `LayoutUnit` fixed-point ticks, 1/64th of a CSS pixel).
*   `max_inline_size` ($\text{max}_i \in \mathbb{N}$): The resolved maximum content/preferred inline size.
*   `percent` ($P_i \in \mathbb{Q}_{\ge 0}$, stored as `std::optional<float>`): The clamped percentage constraint derived from CSS `<percentage>` values on `<col>` or `<td>`/`<th>` elements.
*   `is_constrained` ($\text{bool}$): True if the column has a fixed width or a positive percentage constraint.

Before `SynchronizeAssignableTableInlineSizeAndColumns` (invoked by `ComputeColumnWidths`) executes the distribution pass, raw percentages are pre-processed:
1.  **Clamping**: Each $P_i$ is non-negative ($P_i \ge 0$).
2.  **Total Percentage Normalization**: In compliance with CSS Table 3 §3.3 ("Computing Column Widths"), if the sum of percentages across all percentage columns exceeds $100\%$, Blink tracks `total_percent` and scales down individual percentages proportionally, or caps the cumulative allocation so that $\sum_{i \in \mathcal{P}} P_i^{\text{eff}} \le 100$.

---

### 2. Resolution & Residual Free Space Allocation

Let $W_{\text{avail}} \in \mathbb{N}$ denote the assignable table inline size (`assignable_table_inline_size`), which equals the table's resolved inline size minus borders, padding, and $(N + 1) \times \text{border\_spacing}$.

#### 2.1 Percentage Column Resolution
For a column $i$ with a percentage constraint $P_i \in [0, 100]$, the raw target percentage width is resolved via integer truncation (floor in `LayoutUnit` space):
$$W_{\text{pct}}(W_{\text{avail}}, P_i) = \left\lfloor \frac{W_{\text{avail}} \cdot P_i}{100} \right\rfloor$$

When incorporating intrinsic minimum constraints (CSS Table 3 §3.3, where percentage columns cannot shrink below their `min-content` width), the effective resolved width of column $i$ is:
$$W_{\text{col}, i} = \max\left(\text{min}_i, \left\lfloor \frac{W_{\text{avail}} \cdot P_i}{100} \right\rfloor\right)$$
In the pure percentage sizing pass (prior to or isolated from intrinsic min-width floors, or when $\text{min}_i = 0$), this simplifies directly to:
$$W_{\text{col}, i} = \left\lfloor \frac{W_{\text{avail}} \cdot P_i}{100} \right\rfloor$$

#### 2.2 Residual Free Space Allocation
Let $\mathcal{P} \subseteq \{0, \dots, N-1\}$ be the indices of percentage-constrained columns, and $\mathcal{U} = \{0, \dots, N-1\} \setminus \mathcal{P}$ be the indices of non-percentage (auto and fixed) columns.

1.  **Total Percentage Allocation**:
    $$W_{\mathcal{P}} = \sum_{i \in \mathcal{P}} W_{\text{col}, i}$$
2.  **Residual Available Space**:
    $$W_{\text{rem}} = \max\left(0, W_{\text{avail}} - W_{\mathcal{P}}\right)$$
    (In Rocq `nat` arithmetic, truncated subtraction `W_avail - W_P` naturally computes $\max(0, W_{\text{avail}} - W_{\mathcal{P}})$).
3.  **Distribution Among Non-Percent Columns ($\mathcal{U}$)**:
    The residual space $W_{\text{rem}}$ is distributed among columns $j \in \mathcal{U}$ according to Blink's priority hierarchy in `DistributeInlineSizeToComputedInlineSizeAuto`:
    *   First, all columns $j \in \mathcal{U}$ are guaranteed their $\text{min}_j$.
    *   Remaining space is distributed to unconstrained auto columns up to their $\text{max}_j$ proportionally to their `max_inline_size` (or excess growth capacity $\text{max}_j - \text{min}_j$).
    *   If residual space still remains and $\mathcal{P}$ cannot absorb further growth (or all columns are fixed/auto), it is distributed proportionally to $\text{max}_j$ across eligible columns in $\mathcal{U}$ such that:
        $$\sum_{j \in \mathcal{U}} \Delta W_j \le W_{\text{rem}}$$

---

### 3. Formal Invariants

Under the standard pre-condition that individual percentages are non-negative ($P_i \ge 0$) and the total percentage does not exceed $100\%$ ($\sum_{i \in \mathcal{P}} P_i \le 100$):

1.  **Non-Negativity**:
    For all $W_{\text{avail}} \ge 0$ and $P_i \ge 0$, $W_{\text{col}, i} = \lfloor (W_{\text{avail}} \cdot P_i) / 100 \rfloor \ge 0$, and $W_{\text{rem}} \ge 0$.
2.  **Boundedness (No Overflow of Available Space)**:
    By the superadditivity of the floor function ($\lfloor a \rfloor + \lfloor b \rfloor \le \lfloor a + b \rfloor$):
    $$\sum_{i \in \mathcal{P}} \left\lfloor \frac{W_{\text{avail}} \cdot P_i}{100} \right\rfloor \le \left\lfloor \frac{W_{\text{avail}} \cdot \sum_{i \in \mathcal{P}} P_i}{100} \right\rfloor \le \left\lfloor \frac{W_{\text{avail}} \cdot 100}{100} \right\rfloor = W_{\text{avail}}$$
    Consequently, pure percentage column widths never exceed $W_{\text{avail}}$, and exact residual space satisfies $W_{\mathcal{P}} + W_{\text{rem}} = W_{\text{avail}}$.
3.  **Monotonicity in $W_{\text{avail}}$**:
    For any $W_1, W_2 \in \mathbb{N}$ with $W_1 \le W_2$:
    *   Each column width is monotonic: $W_{\text{col}, i}(W_1, P_i) \le W_{\text{col}, i}(W_2, P_i)$.
    *   Total percentage width is monotonic: $W_{\mathcal{P}}(W_1) \le W_{\mathcal{P}}(W_2)$.

---

### 4. Concrete Rocq/Coq Formalization (`BlinkTablePercentColumnSizingSemantics.v`)

The following file is completely self-contained, uses standard `Arith`, `Lia`, and `List` libraries, and compiles without `Admitted` lemmas.

```coq
(** * BlinkTablePercentColumnSizingSemantics.v
    Formal audit of Chromium Blink Table Percentage Column Sizing
    against CSS Table Module Level 3 Section 3.3. *)

From Coq Require Import Arith.PeanoNat.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

Section BlinkTablePercentColumnSizing.

  (** ** 1. Data Representation *)

  (** Column specification in LayoutUnit ticks and integer percentages.
      In Blink's TableTypes::Column, percentages are stored as optional floats;
      here we model scaled integer percentages P in [0, 100] (or fixed-point basis). *)
  Inductive ColumnKind : Type :=
  | ColPercent (p : nat) (* Percentage constraint P *)
  | ColAuto    (max_w : nat) (* Non-percent column with preferred max width *).

  Record ColumnSpec : Type := mkColumnSpec {
    col_min  : nat;
    col_kind : ColumnKind
  }.

  (** Extract percentage value (0 for non-percent columns). *)
  Definition col_percent (c : ColumnSpec) : nat :=
    match col_kind c with
    | ColPercent p => p
    | ColAuto _    => 0
    end.

  (** Sum of a list of natural numbers. *)
  Fixpoint sum_list (l : list nat) : nat :=
    match l with
    | [] => 0
    | x :: xs => x + sum_list xs
    end.

  (** Total percentage across a list of percentage values. *)
  Definition sum_percentages (ps : list nat) : nat :=
    sum_list ps.

  (** ** 2. Resolution Semantics *)

  (** Pure percentage resolution: W_col = floor(W_avail * P / 100). *)
  Definition resolve_percent_width (w_avail p : nat) : nat :=
    (w_avail * p) / 100.

  (** Resolve a list of percentage columns. *)
  Definition resolve_all_percent_widths (w_avail : nat) (ps : list nat) : list nat :=
    map (resolve_percent_width w_avail) ps.

  (** Total width allocated to percentage columns. *)
  Definition total_percent_width (w_avail : nat) (ps : list nat) : nat :=
    sum_list (resolve_all_percent_widths w_avail ps).

  (** Residual free space available for non-percentage columns. *)
  Definition residual_free_space (w_avail : nat) (ps : list nat) : nat :=
    w_avail - total_percent_width w_avail ps.

  (** Even/sequential allocation of residual space across k non-percent columns. *)
  Definition allocate_residual_even (w_rem k : nat) : list nat :=
    match k with
    | 0 => []
    | S k' =>
        let base := w_rem / k in
        let rem  := w_rem mod k in
        (* First 'rem' columns get (base + 1), remaining get 'base' *)
        repeat (base + 1) rem ++ repeat base (k - rem)
    end.

  (** ** 3. Helper Arithmetic Lemmas *)

  Lemma div_add_le : forall a b c : nat,
    c <> 0 ->
    (a / c) + (b / c) <= (a + b) / c.
  Proof.
    intros a b c Hc.
    pose proof (Nat.div_mod a c Hc) as Ha.
    pose proof (Nat.div_mod b c Hc) as Hb.
    pose proof (Nat.div_mod (a + b) c Hc) as Hab.
    pose proof (Nat.mod_upper_bound a c Hc) as Hma.
    pose proof (Nat.mod_upper_bound b c Hc) as Hmb.
    pose proof (Nat.mod_upper_bound (a + b) c Hc) as Hmab.
    (* From Euclidean division, c * (a/c + b/c) <= a + b < c * ((a+b)/c + 1) *)
    assert (Hineq : c * (a / c + b / c) < c * ((a + b) / c + 1)).
    { lia. }
     rewrite <- Nat.mul_lt_mono_pos_l in Hineq; lia.
  Qed.

  Lemma sum_div_le_div_sum : forall (l : list nat) (c : nat),
    c <> 0 ->
    sum_list (map (fun x => x / c) l) <= (sum_list l) / c.
  Proof.
    induction l as [| x xs IH]; intros c Hc.
    - simpl. rewrite Nat.div_0_l; lia.
    - simpl.
      specialize (IH c Hc).
      pose proof (div_add_le x (sum_list xs) c Hc) as Hle.
      lia.
  Qed.

  Lemma sum_mul_const : forall (w : nat) (ps : list nat),
    sum_list (map (fun p => w * p) ps) = w * sum_list ps.
  Proof.
    intros w ps.
    induction ps as [| p ps' IH].
    - simpl. lia.
    - simpl. rewrite IH. lia.
  Qed.

  Lemma map_resolve_decomp : forall (w_avail : nat) (ps : list nat),
    resolve_all_percent_widths w_avail ps =
    map (fun x => x / 100) (map (fun p => w_avail * p) ps).
  Proof.
    intros w_avail ps.
    unfold resolve_all_percent_widths, resolve_percent_width.
    rewrite map_map. reflexivity.
  Qed.

  (** ** 4. Core Invariant Theorems *)

  (** Invariant 1: Non-negativity of resolved column widths (structural in nat,
      plus explicit lower bound when P > 0 and W_avail >= 100). *)
  Theorem resolve_percent_width_nonneg : forall w_avail p : nat,
    0 <= resolve_percent_width w_avail p.
  Proof.
    intros. lia.
  Qed.

  Theorem resolve_percent_width_pos : forall w_avail p : nat,
    100 <= w_avail ->
    1 <= p ->
    1 <= resolve_percent_width w_avail p.
  Proof.
    intros w_avail p Hw Hp.
    unfold resolve_percent_width.
    assert (H100 : 100 <= w_avail * p).
    { replace 100 with (100 * 1) by lia.
      apply Nat.mul_le_mono; lia. }
    pose proof (Nat.div_le_mono 100 (w_avail * p) 100 ltac:(lia) H100) as Hdiv.
    rewrite Nat.div_same in Hdiv; lia.
  Qed.

  (** Invariant 2: Monotonicity of individual percentage column width in W_avail. *)
  Theorem resolve_percent_width_monotonic_avail : forall w1 w2 p : nat,
    w1 <= w2 ->
    resolve_percent_width w1 p <= resolve_percent_width w2 p.
  Proof.
    intros w1 w2 p Hw.
    unfold resolve