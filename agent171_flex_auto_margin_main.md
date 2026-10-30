### Agent 171 Audit Report: Blink Flex Main Axis Auto Margins vs. CSS Flexbox 1 §8.1

#### 1. Free Space Absorption Mechanics
Per **CSS Flexible Box Layout Module Level 1 §8.1 (Aligning with `auto` margins)**, prior to alignment via `justify-content`, any positive free space on the main axis is distributed equally among all `auto` margins on that line:
* **Free Space Calculation:** Let $W_{\text{line}}$ be the main-axis inner size of the flex container, and for each flex item $i \in \{1 \dots n\}$ on the line, let $S_i = w_i + m_{i,\text{start}}^{\text{fixed}} + m_{i,\text{end}}^{\text{fixed}}$ be its total outer main size (treating `auto` margins as $0$). The remaining free space is:
  $$\text{free\_space} = W_{\text{line}} - \sum_{i=1}^n S_i$$
* **Absorption Rule:** Let $C_{\text{auto}}$ be the total count of `auto` main-axis margins (`margin-left`/`margin-right` in horizontal writing modes) across all items on the line.
  * If $\text{free\_space} > 0$ and $C_{\text{auto}} > 0$:
    Each `auto` margin receives $\lfloor \text{free\_space} / C_{\text{auto}} \rfloor$ (in Blink `LayoutUnit` fixed-point arithmetic, `remaining_free_space / number_of_auto_margins`), and $\text{free\_space}$ is reduced to $0$ (or the integer division remainder in pure discrete models before subpixel accumulation).
  * If $\text{free\_space} \le 0$ or $C_{\text{auto}} = 0$:
    All `auto` margins resolve to $0$, and $\text{free\_space}$ remains unchanged for subsequent `justify-content` processing.

---

#### 2. Core Invariants
1. **Conservation of Positive Free Space (Modulo Remainder):**
   When $\text{free\_space} > 0$ and $C_{\text{auto}} > 0$, the sum of all allocated main-axis `auto` margins plus the residual integer remainder equals the initial $\text{free\_space}$:
   $$\sum_{m \in M_{\text{auto}}} \text{alloc}(m) = \text{free\_space} - (\text{free\_space} \bmod C_{\text{auto}})$$
2. **`justify-content` Neutralization Invariant:**
   When $C_{\text{auto}} > 0$ and $\text{free\_space} > 0$, all distributable free space is absorbed by the `auto` margins ($\text{free\_space}' = 0$). Consequently, the `justify-content` property has **zero effect** on item positioning—any value of `justify-content` (`flex-start`, `center`, `space-between`, etc.) produces the exact same main-axis offsets.

---

#### 3. Concrete Rocq / Coq Formalization (`BlinkFlexAutoMarginMainSemantics.v`)

```coq
(** * BlinkFlexAutoMarginMainSemantics.v
    Formalization of Chromium Blink Flex Main Axis Auto Margin distribution
    against CSS Flexbox Level 1 §8.1. *)

From Coq Require Import Arith ZArith List Bool Lia.
Import ListNotations.
Open Scope Z_scope.

(** ** 1. Data Types and Line Representation *)

Inductive MarginSpec : Type :=
  | Fixed (v : Z)
  | Auto.

Record FlexItem : Type := mkFlexItem {
  item_main_size : Z;
  margin_start   : MarginSpec;
  margin_end     : MarginSpec
}.

Inductive JustifyContent : Type :=
  | JC_FlexStart
  | JC_FlexEnd
  | JC_Center
  | JC_SpaceBetween
  | JC_SpaceAround
  | JC_SpaceEvenly.

(** Extract fixed margin contribution (Auto is treated as 0 initially) *)
Definition fixed_margin_val (m : MarginSpec) : Z :=
  match m with
  | Fixed v => v
  | Auto    => 0
  end.

Definition is_auto (m : MarginSpec) : Z :=
  match m with
  | Fixed _ => 0
  | Auto    => 1
  end.

Definition item_base_outer_size (it : FlexItem) : Z :=
  item_main_size it + fixed_margin_val (margin_start it) + fixed_margin_val (margin_end it).

Definition item_auto_count (it : FlexItem) : Z :=
  is_auto (margin_start it) + is_auto (margin_end it).

Fixpoint sum_base_sizes (items : list FlexItem) : Z :=
  match items with
  | [] => 0
  | it :: rest => item_base_outer_size it + sum_base_sizes rest
  end.

Fixpoint count_auto_margins (items : list FlexItem) : Z :=
  match items with
  | [] => 0
  | it :: rest => item_auto_count it + count_auto_margins rest
  end.

(** ** 2. Free Space & Auto Margin Allocation Semantics *)

Definition initial_free_space (W_line : Z) (items : list FlexItem) : Z :=
  W_line - sum_base_sizes items.

(** Per-margin allocation for `Auto` margins in Blink *)
Definition single_auto_margin_alloc (free_space auto_count : Z) : Z :=
  if (free_space >? 0) && (auto_count >? 0) then
    free_space / auto_count
  else
    0.

(** Resolve a MarginSpec to its concrete Z value *)
Definition resolve_margin (m : MarginSpec) (auto_unit : Z) : Z :=
  match m with
  | Fixed v => v
  | Auto    => auto_unit
  end.

(** Remaining free space passed to `justify-content` after auto margin absorption *)
Definition post_auto_free_space (free_space auto_count : Z) : Z :=
  if (free_space >? 0) && (auto_count >? 0) then
    0
  else
    free_space.

(** Sum of allocated auto margins across the line *)
Fixpoint sum_allocated_auto_margins (items : list FlexItem) (auto_unit : Z) : Z :=
  match items with
  | [] => 0
  | it :: rest =>
      (is_auto (margin_start it) * auto_unit) +
      (is_auto (margin_end it) * auto_unit) +
      sum_allocated_auto_margins rest auto_unit
  end.

(** Justify-content offset calculation (simplified model parameterized by remaining free space) *)
Definition compute_jc_initial_offset (jc : JustifyContent) (rem_free_space : Z) : Z :=
  if rem_free_space <=? 0 then
    match jc with
    | JC_FlexEnd => rem_free_space
    | JC_Center  => rem_free_space / 2
    | _          => 0
    end
  else
    match jc with
    | JC_FlexStart    => 0
    | JC_FlexEnd      => rem_free_space
    | JC_Center       => rem_free_space / 2
    | JC_SpaceBetween => 0
    | JC_SpaceAround  => rem_free_space / 2
    | JC_SpaceEvenly  => rem_free_space / 2
    end.

(** ** 3. Formal Verification of Invariants *)

Lemma sum_allocated_factors : forall (items : list FlexItem) (u : Z),
  sum_allocated_auto_margins items u = count_auto_margins items * u.
Proof.
  induction items as [| it rest IH]; intros u; simpl.
  - lia.
  - rewrite IH. unfold item_auto_count. lia.
Qed.

(** Theorem 1: Conservation of Positive Free Space (Modulo Integer Remainder).
    When free_space > 0 and auto_count > 0, the sum of allocated auto margins
    equals free_space minus the Euclidean remainder (free_space mod auto_count). *)
Theorem auto_margin_free_space_conservation :
  forall (W_line : Z) (items : list FlexItem),
    let fs := initial_free_space W_line items in
    let ac := count_auto_margins items in
    fs > 0 ->
    ac > 0 ->
    let u := single_auto_margin_alloc fs ac in
    sum_allocated_auto_margins items u = fs - (fs mod ac).
Proof.
  intros W_line items fs ac Hfs Hac u.
  rewrite sum_allocated_factors.
  unfold u, single_auto_margin_alloc.
  assert (Hcond : (fs >? 0) && (ac >? 0) = true).
  { apply andb_true_iff. split; apply Z.gtb_lt; lia. }
  rewrite Hcond.
  pose proof (Z_div_mod_eq_full fs ac) as Hdiv.
  lia.
Qed.

(** Theorem 2: Non-positive Free Space Yields Zero Auto Margin Allocation. *)
Theorem non_positive_free_space_zero_auto :
  forall (W_line : Z) (items : list FlexItem),
    let fs := initial_free_space W_line items in
    let ac := count_auto_margins items in
    fs <= 0 ->
    let u := single_auto_margin_alloc fs ac in
    sum_allocated_auto_margins items u = 0.
Proof.
  intros W_line items fs ac Hfs u.
  rewrite sum_allocated_factors.
  unfold u, single_auto_margin_alloc.
  destruct (fs >? 0) eqn:Efs.
  - apply Z.gtb_lt in Efs. lia.
  - simpl. lia.
Qed.

(** Theorem 3: Justify-Content Neutralization Invariant.
    When positive free space exists and at least one auto margin is present,
    `justify-content` has no effect on alignment offsets. *)
Theorem justify_content_neutralized_by_auto_margins :
  forall (W_line : Z) (items : list FlexItem) (jc1 jc2 : JustifyContent),
    let fs := initial_free_space W_line items in
    let ac := count_auto_margins items in
    fs > 0 ->
    ac > 0 ->
    let rem_fs := post_auto_free_space fs ac in
    compute_jc_initial_offset jc1 rem_fs = compute_jc_initial_offset jc2 rem_fs.
Proof.
  intros W_line items jc1 jc2 fs ac Hfs Hac rem_fs.
  unfold rem_fs, post_auto_free_space.
  assert (Hcond : (fs >? 0) && (ac >? 0) = true).
  { apply andb_true_iff. split; apply Z.gtb_lt; lia. }
  rewrite Hcond.
  unfold compute_jc_initial_offset. simpl.
  destruct jc1, jc2; reflexivity.
Qed.
```