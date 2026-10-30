# Audit Report: Chromium Blink Multi-Line Flexbox Wrapping vs. CSS Flexbox 1 (§8.4 & §9.4)
**Agent ID:** Agent 145  
**Target:** Chromium Blink LayoutNG (`third_party/blink/renderer/core/layout/flex/`)  
**Specification:** W3C CSS Flexible Box Layout Module Level 1 (§8.4 Packing Flex Lines: the `align-content` property, §9.4 Cross Size Determination)

---

## 1. Core Data Structures in Blink LayoutNG Flex Layout

Blink's LayoutNG implements multi-line flexbox layout through a pipeline managed primarily by `NGFlexLayoutAlgorithm` (now `FlexLayoutAlgorithm` in modern Blink namespaces) and `FlexLineBreaker`.

### 1.1 `FlexItem` and `NGSizedFlexItem`
Before line breaking, Blink constructs an array of `FlexItem` representations from the layout children:
* **`NGSizedFlexItem` / `FlexItem`:** Encapsulates a single in-flow flex child along with its pre-calculated sizing metrics:
  * `flex_base_content_size`: The item's flex base size $B_i$, resolved according to §9.2.
  * `hypothetical_main_content_size`: The item's hypothetical main size $H_i = \text{clamp}(B_i, \text{min\_main}_i, \text{max\_main}_i)$.
  * `main_axis_margin`: Sum of physical/logical margins along the main axis ($M_{\text{main}, i}$).
  * `cross_axis_margin`: Sum of margins along the cross axis ($M_{\text{cross}, i}$).
  * `min_max_main_sizes` and `min_max_cross_sizes`: Resolved min/max constraints.
  * ` HypotheticalOuterMainSize()` computes $H_{\text{outer}, i} = H_i + M_{\text{main}, i} + \text{border\_padding}_{\text{main}, i}$.

### 1.2 `FlexLine` (`NGFlexLine`)
During and after §9.3 (Main Size Determination), items are grouped into `FlexLine` structures:
* `line_items`: A contiguous slice/vector of `FlexItem` objects belonging to this line.
* `sum_hypothetical_main_size`: $\sum_{i \in \text{line}} H_{\text{outer}, i} + (| \text{line} | - 1) \cdot G_{\text{main}}$.
* `main_axis_free_space`: Remaining main space after flexible lengths are resolved (§9.7).
* `cross_axis_extent` (`cross_size`): The line's cross size $C_{\text{line}}$, determined in §9.4 Step 8 by taking the maximum of the outer hypothetical cross sizes of its items (and baseline-aligned ascents/descents).
* `cross_axis_offset`: The resolved logical cross-axis position of the line within the flex container.

### 1.3 `align-content` Resolution (`StyleContentAlignmentData`)
Blink resolves the `align-content` property via `ComputedStyle::ResolvedAlignContent`, normalizing `normal` to `stretch` for flex containers. The distribution logic is executed in `FlexLayoutAlgorithm::GiveLinesAndItemsFinalPositionAndSize()`:
* `ContentPosition`: `kFlexStart`, `kFlexEnd`, `kCenter`, `kBaseline`, etc.
* `ContentDistributionType`: `kStretch`, `kSpaceBetween`, `kSpaceAround`, `kSpaceEvenly`.
* When available cross space $F_{\text{cross}} = S_{\text{cross}} - \sum C_{\text{line}} - (N_{\text{lines}} - 1) \cdot G_{\text{cross}}$ is negative, fallback alignment applies per CSS Box Alignment Level 3 (`stretch` $\to$ `flex-start`, `space-between` $\to$ `flex-start`, `space-around` $\to$ `center`, `space-evenly` $\to$ `center`).

---

## 2. Line Breaking Mechanics (CSS Flexbox §9.3 Step 5)

In Blink, line breaking is handled by `FlexLineBreaker::BreakIntoLines()` (or `FlexLayoutAlgorithm::ConstructAndAppendFlexItems` + line collection loop).

### 2.1 Algorithmic Invariants
Given a sequence of items $I = [i_0, i_1, \dots, i_{n-1}]$, available container main size $W_{\text{main}}$, and main-axis gap $G_{\text{main}}$:
1. **Initialization:** Start a new `FlexLine` $L_k$ with `accumulated_main_size` $= 0$.
2. **Iteration:** For each item $i$:
   * Let $s_i = H_{\text{outer}, i}$ be the item's outer hypothetical main size.
   * Let $g = G_{\text{main}}$ if $L_k$ is non-empty, else $0$.
   * **Line Break Condition:** If `is_multi_line` (`flex-wrap: wrap` or `wrap-reverse`) is true, **and** $L_k$ is **not empty**, **and** $\text{accumulated\_main\_size} + g + s_i > W_{\text{main}}$:
     * Commit $L_k$ to the list of lines.
     * Initialize a new line $L_{k+1}$ containing item $i$, with $\text{accumulated\_main\_size} = s_i$.
   * **Continuation Condition:** Otherwise (including when $L_k$ is empty and $s_i > W_{\text{main}}$):
     * Append $i$ to $L_k$.
     * Update $\text{accumulated\_main\_size} \gets \text{accumulated\_main\_size} + g + s_i$.

*Audit Note:* Blink uses `LayoutUnit` (fixed-point 1/64th pixel arithmetic) for `accumulated_main_size` and $W_{\text{main}}$. The non-empty guard (`!line_items.empty()`) strictly enforces the CSS Flexbox §9.3 rule that a single item wider than the container never breaks before itself, preventing infinite empty-line loops and ensuring progress.

---

## 3. Cross-Size Distribution & Offset Accumulation (§9.4 & §8.4)

Once lines $L_0, \dots, L_{m-1}$ are formed and their initial cross sizes $c_0, \dots, c_{m-1}$ are computed from the maximum outer cross size of their constituent items:

### 3.1 `align-content: stretch` (§9.4 Step 9)
If the container has a definite cross size $S_{\text{cross}}$, `align-content` is `stretch`, and the leftover free cross space $F_{\text{cross}} = S_{\text{cross}} - \sum_{k=0}^{m-1} c_k - (m - 1) G_{\text{cross}} > 0$:
* The free space is distributed equally: $\Delta c = \frac{F_{\text{cross}}}{m}$.
* Each line's cross size is updated: $c'_k = c_k + \Delta c$.

### 3.2 Cross Offset Monotonic Accumulation (§8.4)
Let $F'_{\text{cross}} = S_{\text{cross}} - \sum_{k=0}^{m-1} c'_k - (m - 1) G_{\text{cross}}$ be the remaining free space after potential stretching. Blink computes the initial offset $y_0$ and inter-line spacing $\Delta_{\text{between}}$:
* **`flex-start`:** $y_0 = 0$, $\Delta_{\text{between}} = G_{\text{cross}}$.
* **`flex-end`:** $y_0 = F'_{\text{cross}}$, $\Delta_{\text{between}} = G_{\text{cross}}$.
* **`center`:** $y_0 = \frac{F'_{\text{cross}}}{2}$, $\Delta_{\text{between}} = G_{\text{cross}}$.
* **`space-between`:** If $F'_{\text{cross}} > 0$ and $m > 1$, $y_0 = 0$ and $\Delta_{\text{between}} = G_{\text{cross}} + \frac{F'_{\text{cross}}}{m - 1}$. Otherwise, falls back to `flex-start`.
* **`space-around`:** If $F'_{\text{cross}} > 0$ and $m \ge 1$, $y_0 = \frac{F'_{\text{cross}}}{2m}$ and $\Delta_{\text{between}} = G_{\text{cross}} + \frac{F'_{\text{cross}}}{m}$.

The cross offset $Y_k$ for line $k$ is accumulated monotonically:
$$Y_0 = \text{border\_padding}_{\text{cross\_start}} + y_0$$
$$Y_{k+1} = Y_k + c'_k + \Delta_{\text{between}}$$
Because $c'_k \ge 0$, $G_{\text{cross}} \ge 0$, and the added distribution spacing is non-negative, the sequence of line offsets $\{Y_k\}_{k=0}^{m-1}$ is strictly non-decreasing ($Y_k \le Y_{k+1}$), and lines never overlap along the cross axis ($Y_k + c'_k \le Y_{k+1}$).

---

## 4. Formal Verification in Rocq/Coq (`BlinkFlexMultiLineWrapSemantics.v`)

Below is the complete, self-contained Rocq (Coq) formalization verifying the line-breaking progress, item conservation, capacity bounds, `align-content` stretching, and monotonic cross-offset accumulation.

```coq
(** * BlinkFlexMultiLineWrapSemantics.v
    Formal verification of Chromium Blink LayoutNG Multi-Line Flexbox Wrapping
    and Cross-Axis Line Packing against W3C CSS Flexbox Level 1 (§8.4 & §9.4).
    Agent 145 Audit Artifact. *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

Open Scope nat_scope.

(** ** 1. Core Data Structures *)

(** Represents a pre-sized flex item (NGSizedFlexItem / FlexItem) *)
Record FlexItem := mkFlexItem {
  item_id : nat;
  outer_main_size : nat;  (* Hypothetical outer main size H_outer *)
  outer_cross_size : nat  (* Hypothetical outer cross size C_outer *)
}.

(** Represents a constructed flex line (NGFlexLine / FlexLine) *)
Record FlexLine := mkFlexLine {
  line_items : list FlexItem;
  used_main_size : nat;
  line_cross_size : nat;
  line_cross_offset : nat
}.

(** CSS align-content modes audited in §8.4 & §9.4 *)
Inductive AlignContent :=
  | AC_FlexStart
  | AC_FlexEnd
  | AC_Center
  | AC_SpaceBetween
  | AC_Stretch.

(** ** 2. Multi-Line Breaking Algorithm (§9.3 Step 5) *)

(** Compute the maximum outer cross size of a list of items (§9.4 Step 8) *)
Fixpoint max_cross_size (items : list FlexItem) : nat :=
  match items with
  | [] => 0
  | i :: rest => Nat.max (outer_cross_size i) (max_cross_size rest)
  end.

(** Helper to finalize a non-empty list of items into a FlexLine *)
Definition make_flex_line (items : list FlexItem) (used_main : nat) : FlexLine :=
  mkFlexLine items used_main (max_cross_size items) 0.

(** Tail-recursive worker for Blink's FlexLineBreaker::BreakIntoLines.
    - [rem_items]: remaining items to place
    - [cur_items]: items in the current open line (stored in normal order)
    - [cur_main]: accumulated main size of the current open line
    - [max_main]: container available main size
    - [main_gap]: main-axis gap between items *)
Fixpoint break_lines_aux
  (rem_items : list FlexItem)
  (cur_items : list FlexItem)
  (cur_main : nat)
  (max_main : nat)
  (main_gap : nat) : list FlexLine :=
  match rem_items with
  | [] =>
      match cur_items with
      | [] => []
      | _ => [make_flex_line cur_items cur_main]
      end
  | item :: rest =>
      let item_main := outer_main_size item in
      match cur_items with
      | [] =>
          (* Line is empty: item MUST be placed on this line even if item_main > max_main *)
          break_lines_aux rest [item] item_main max_main main_gap
      | _ =>
          let next_main := cur_main + main_gap + item_main in
          if max_main <? next_main then
            (* Exceeds remaining line space and line is non-empty -> wrap to new FlexLine *)
            (make_flex_line cur_items cur_main) ::
            break_lines_aux rest [item] item_main max_main main_gap
          else
            (* Fits in current line -> advance along main axis *)
            break_lines_aux rest (cur_items ++ [item]) next_main max_main main_gap
      end
  end.

Definition break_into_lines (items : list FlexItem) (max_main main_gap : nat) : list FlexLine :=
  break_lines_aux items [] 0 max_main main_gap.

(** ** 3. Line Breaking Theorems *)

(** Theorem 1: Every produced FlexLine is strictly non-empty. *)
Lemma break_lines_aux_non_empty :
  forall rem cur_items cur_main max_main main_gap line,
    In line (break_lines_aux rem cur_items cur_main max_main main_gap) ->
    line_items line <> [].
Proof.
  induction rem as [| item rest IH]; intros cur_items cur_main max_main main_gap line HIn.
  - simpl in HIn. destruct cur_items as [| c cs].
    + contradiction.
    + destruct HIn as [Heq | HFalse]; [| contradiction].
      subst line. simpl. discriminate.
  - simpl in HIn. destruct cur_items as [| c cs].
    + apply IH in HIn. exact HIn.
    + destruct (max_main <? cur_main + main_gap + outer_main_size item) eqn:Hlt.
      * destruct HIn as [Heq | HInRest].
        -- subst line. simpl. discriminate.
        -- apply IH in HInRest. exact HInRest.
      * apply IH in HIn. exact HIn.
Qed.

Theorem break_into_lines_non_empty :
  forall items max_main main_gap line,
    In line (break_into_lines items max_main main_gap) ->
    line_items line <> [].
Proof.
  intros items max_main main_gap line HIn.
  unfold break_