### 1. Core Data Structures in Blink Table Cell Layout

In Chromium’s Blink rendering engine (specifically within LayoutNG), table cell layout and vertical alignment are governed by `TableCellLayoutAlgorithm` and its surrounding geometry structures.

*   **`TableCellLayoutAlgorithm`**: Inherits from `LayoutAlgorithm`. It orchestrates the formatting context of a `<td>` or `<th>` element. During the row and section layout passes, the table algorithm calculates the final resolved row height $H$ (`table_row_height`) and the row's shared baseline (`row_baseline`). It passes these constraints down into the cell’s `ConstraintSpace`.
*   **`EVerticalAlign`**: Represents the computed `vertical-align` CSS property. For table cells (per CSS 2.1 §17.5.3), all values other than `baseline`, `top`, `middle`, and `bottom` (such as `sub`, `super`, `text-top`, `text-bottom`, or `<length>`) are mapped to `baseline`.
    ```cpp
    enum class EVerticalAlign : unsigned {
      kBaseline, kMiddle, kSub, kSuper, kTextTop, kTextBottom, kTop, kBottom, kBaselineMiddle, kLength
    };
    ```
*   **`BoxStrut`**: Represents the physical dimensions of borders (`border_top`, `border_bottom`, etc.) and paddings (`padding_top`, `padding_bottom`, etc.). In LayoutNG, these are combined into `border_padding = borders + padding` prior to child layout.
*   **`LogicalOffset` / `LayoutUnit`**: Fixed-point arithmetic units (typically $1/64\text{th}$ of a pixel) used to represent the computed block-start offset of the cell's inflow children, intrinsic block size, and final fragment block size.

---

### 2. Vertical Offset Computation for Cell Content

Let a table cell have a final resolved block size (height) $H$ determined by the enclosing row's height. Let the cell's box model metrics be:
*   $B_t, B_b$: `border_top`, `border_bottom`
*   $P_t, P_b$: `padding_top`, `padding_bottom`
*   $C_h$: `content_height` (the intrinsic block size of the cell's inflow content excluding $B_t, B_b, P_t, P_b$).
*   $BP_t = B_t + P_t$ and $BP_b = B_b + P_b$.

The intrinsic block size of the cell is $I_h = BP_t + C_h + BP_b$. By definition of CSS 2.1 table layout, the row height $H$ is at least as large as the intrinsic height of the tallest cell in the row, so under normal (unclamped) layout conditions:
$$H \ge BP_t + C_h + BP_b$$

The available free space inside the content box is:
$$\Delta = \max(0, H - (BP_t + BP_b + C_h))$$

Blink computes the vertical offset $O_y$ from the top border edge of the cell to the top of the cell's content box as follows:

1.  **`Top` (`EVerticalAlign::kTop`)**:
    Content is flush with the top of the content box.
    $$O_y = B_t + P_t$$

2.  **`Bottom` (`EVerticalAlign::kBottom`)**:
    Content is pushed down by the entirety of the free space $\Delta$.
    $$O_y = B_t + P_t + \Delta = H - (B_b + P_b + C_h)$$

3.  **`Middle` (`EVerticalAlign::kMiddle`)**:
    The free space $\Delta$ is bisected.
    $$O_y = B_t + P_t + \left\lfloor \frac{\Delta}{2} \right\rfloor = B_t + P_t + \left\lfloor \frac{H - B_t - B_b - P_t - P_b - C_h}{2} \right\rfloor$$

4.  **`Baseline` (`EVerticalAlign::kBaseline`)**:
    Let $L_{\text{cell}}$ be the distance from the top border edge of the cell to the cell's first in-flow line box baseline (as computed during an unshifted initial layout pass where content starts at $BP_t$). Thus, the baseline relative to the content top is $L_{\text{content}} = L_{\text{cell}} - BP_t$.
    Let $L_{\text{row}}$ be the maximum baseline among all `baseline`-aligned cells in the row ($L_{\text{row}} \ge L_{\text{cell}}$).
    The content is shifted down so that the cell's baseline coincides with the row's baseline:
    $$\Delta_{\text{base}} = \max(0, L_{\text{row}} - L_{\text{cell}})$$
    $$O_y = B_t + P_t + \Delta_{\text{base}}$$
    *(Note: In CSS 2.1 §17.5.3, the row height $H$ is already expanded during row layout to accommodate the maximum baseline ascent plus the maximum baseline descent across all baseline-aligned cells in the row).*

---

### 3. Padding, Border Box Clamping, and Minimum Content Height

In Blink's `NGTableLayoutAlgorithm` and `TableCellLayoutAlgorithm`, edge cases arise when fixed heights are smaller than intrinsic heights, or when subpixel layout arithmetic threatens to push content outside the padding box.

1.  **Minimum Content Height Preservation**:
    Before alignment offsets are computed, the row height $H$ is resolved as:
    $$H = \max\left(H_{\text{css}}, \max_{i \in \text{cells}} (BP_{t,i} + C_{h,i} + BP_{b,i}), H_{\text{baseline\_span}}\right)$$
    A table cell *cannot* shrink below its intrinsic content height plus borders and padding. CSS `height` on a table cell acts as a minimum height constraint (`min-height`).

2.  **Padding and Border Box Clamping**:
    Even if artificial constraints (e.g., layout engine bugs, integer overflow saturation in `LayoutUnit`, or forced fragment slicing in fragmentation/pagination) produce a state where $H < BP_t + BP_b + C_h$, Blink clamps the free-space shift $\Delta$ to be non-negative:
    $$\Delta_{\text{clamped}} = \max(0, H - BP_t - BP_b - C_h)$$
    This guarantees that `Middle` and `Bottom` alignment **never** pull the cell content upward into the top border or top padding ($O_y \ge B_t + P_t$). If content overflows (e.g., due to fragmentation constraints), it overflows downward out of the bottom edge, matching CSS block progression invariants.

3.  **Baseline Fallback**:
    If a cell has `vertical-align: baseline` but contains no in-flow line boxes or baseline-capable children, Blink synthesizes its baseline at the bottom of its content box ($L_{\text{cell}} = BP_t + C_h$), ensuring well-defined deterministic behavior.

---

### 4. Mathematical Invariants

Across all valid inputs where $B_t, B_b, P_t, P_b, C_h \ge 0$, the vertical alignment offset function $O_y$ satisfies the following invariants:

1.  **Top Border-Padding Lower Bound (Clamping Invariant)**:
    $$O_y \ge B_t + P_t$$
2.  **Offset Non-Negativity**:
    Since $B_t \ge 0$ and $P_t \ge 0$, it strictly follows that:
    $$O_y \ge 0$$
3.  **Content Containment (Box Fit Invariant)**:
    When the resolved cell height $H$ satisfies the CSS 2.1 row-sizing invariant ($H \ge B_t + P_t + C_h + P_b + B_b$, and for baseline alignment, $H - (L_{\text{row}} - L_{\text{cell}}) \ge B_t + P_t + C_h + P_b + B_b$), the cell's content box is completely contained within the cell's padding box:
    $$O_y + C_h \le H - B_b - P_b \implies O_y + C_h \le H$$
4.  **Determinism**:
    For any fixed layout state $\mathcal{S} = (v, H, B_t, B_b, P_t, P_b, C_h, L_{\text{cell}}, L_{\text{row}})$, the computed offset $O_y$ is unique.

---

### 5. Rocq / Coq Formalization (`BlinkTableCellAlignSemantics.v`)

The following complete, self-contained Rocq (Coq) script formalizes the Blink table cell vertical alignment semantics and proves the required invariants using `Z` (arbitrary-precision integers, modeling `LayoutUnit` ticks).

```coq
(** * BlinkTableCellAlignSemantics.v
    Formalization of Chromium Blink Table Cell Vertical Alignment
    against CSS 2.1 Section 17.5.3. *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** CSS 2.1 §17.5.3 vertical-align values applicable to table-cell boxes.
    All other CSS values (sub, super, text-top, text-bottom, <length>, <percentage>)
    compute/map to Baseline in table cells. *)
Inductive EVerticalAlign : Type :=
  | VA_Top
  | VA_Middle
  | VA_Bottom
  | VA_Baseline.

(** Box geometry and layout metrics for a single table cell (in LayoutUnits). *)
Record CellLayoutState : Type := mkCellState {
  cell_height    : Z; (* H: Resolved height of the cell (equals row height) *)
  border_top     : Z; (* B_t *)
  border_bottom  : Z; (* B_b *)
  padding_top    : Z; (* P_t *)
  padding_bottom : Z; (* P_b *)
  content_height : Z; (* C_h: Intrinsic block size of inflow content *)
  cell_baseline  : Z; (* L_cell: Distance from cell top border edge to cell baseline *)
  row_baseline   : Z  (* L_row: Shared row baseline distance from row top edge *)
}.

(** Well-formedness predicate for physical dimensions (non-negativity). *)
Definition wf_dimensions (s : CellLayoutState) : Prop :=
  border_top s >= 0 /\
  border_bottom s >= 0 /\
  padding_top s >= 0 /\
  padding_bottom s >= 0 /\
  content_height s >= 0 /\
  cell_height s >= 0.

(** Predicate stating that the cell height H is large enough to contain
    its borders, paddings, and content (CSS 2.1 minimum row height invariant),
    including baseline shift when aligned to baseline. *)
Definition content_fits (va : EVerticalAlign) (s : CellLayoutState) : Prop :=
  let bp_t := border_top s + padding_top s in
  let bp_b := border_bottom s + padding_bottom s in
  match va with
  | VA_Baseline =>
      let baseline_shift := Z.max 0 (row_baseline s - cell_baseline s) in
      bp_t + baseline_shift + content_height s + bp_b <= cell_height s
  | _ =>
      bp_t + content_height s + bp_b <= cell_height s
  end.

(** ** 2. Vertical Offset Computation *)

(** Clamped available free space inside the cell's content box.
    Matches Blink's clamping to prevent content from encroaching into border/padding. *)
Definition free_content_space (s : CellLayoutState) : Z :=
  let bp_t := border_top s + padding_top s in
  let bp_b := border_bottom s + padding_bottom s in
  Z.max 0 (cell_height s - (bp_t + bp_b + content_height s)).

(** Functional specification of TableCellLayoutAlgorithm vertical offset computation. *)
Definition compute_vertical_offset (va : EVerticalAlign) (s : CellLayoutState) : Z :=
  let bp_t := border_top s + padding_top s in
  let delta := free_content_space s in
  match va with
  | VA_Top      => bp_t
  | VA_Bottom   => bp_t + delta
  | VA_Middle   => bp_t + (delta / 2)
  | VA_Baseline => bp_t + Z.max 0 (row_baseline s - cell_baseline s)
  end.

(** Relational (Inductive) specification of vertical offset semantics. *)
Inductive BlinkCellOffsetSemantics : EVerticalAlign -> CellLayoutState -> Z -> Prop :=
  | Sem_Top : forall s,
      BlinkCellOffsetSemantics VA_Top s (border_top s + padding_top s)
  | Sem_Bottom : forall s delta,
      delta = free_content_space s ->
      BlinkCellOffsetSemantics VA_Bottom s (border_top s + padding_top s + delta)
  | Sem_Middle : forall s delta,
      delta = free_content_space s ->
      BlinkCellOffsetSemantics VA_Middle s (border_top s + padding_top s + (delta / 2))
  | Sem_Baseline : forall s shift,
      shift = Z.max 0 (row_baseline s - cell_baseline s) ->
      BlinkCellOffsetSemantics VA_Baseline s (border_top s + padding_top s + shift).

(** ** 3. Equivalence and Determinism Theorems *)

(** Theorem: The functional computation and relational semantics coincide. *)
Theorem compute_offset_sound_complete :
  forall (va : EVerticalAlign) (s : CellLayoutState) (offset : Z),
    BlinkCellOffsetSemantics va s offset <-> compute_vertical_offset va s = offset.
Proof.
  intros va s offset; split; intro H.
  - destruct H; subst; simpl; reflexivity.
  - subst. destruct va; simpl.
    + apply Sem_Top.
    + apply Sem_Middle; reflexivity.
    + apply Sem_Bottom; reflexivity.
    + apply Sem_Baseline; reflexivity.
Qed.

(** Theorem: Offset computation is strictly deterministic. *)
Theorem offset_deterministic :
  forall (va : EVerticalAlign) (s : CellLayoutState) (o1 o2 : Z),
    BlinkCellOffsetSemantics va s o1 ->
    BlinkCellOffsetSemantics va s o2 ->
    o1 = o2.
Proof.
  intros va s o1 o2 H1 H2.
  apply compute_offset_sound_complete in H1.
  apply compute_offset_sound_complete in H2.
  congruence.
Qed.

(** ** 4. Clamping and Box-Model Invariants *)

(** Lemma: Free content space is always non-negative