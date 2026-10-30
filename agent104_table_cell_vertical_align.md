### 1. Core Data Structures in Blink Table Cell Layout

In Chromium’s Blink LayoutNG engine, table cell vertical alignment is governed by the interaction between the row/section layout pass (which determines the row height $R$ and the row baseline) and the cell layout algorithm (which shifts the cell's inflow children to achieve vertical alignment).

#### `EVerticalAlign` (`third_party/blink/renderer/core/style/computed_style_constants.h`)
An enumeration representing the computed value of the CSS `vertical-align` property. In the context of table cells (CSS 2.1 §17.5.3), only four values are directly operative on the cell box itself (others like `sub`, `super`, `text-top`, `text-bottom` fall back to `baseline` when applied to table cells):
```cpp
enum class EVerticalAlign : unsigned {
  kBaseline,
  kMiddle,
  kSub,
  kSuper,
  kTextTop,
  kTextBottom,
  kTop,
  kBottom,
  kBaselineMiddle,
  kLength
};
```

#### `LogicalRect` and `LayoutUnit` (`third_party/blink/renderer/core/layout/geometry/logical_rect.h`)
Blink computes layout in flow-relative logical coordinates before converting to physical coordinates. A `LogicalRect` consists of a `LogicalOffset` (`inline_offset`, `block_offset`) and a `LogicalSize` (`inline_size`, `block_size`), all quantized to `LayoutUnit` (a 32-bit fixed-point value with 6 fractional bits, i.e., $1/64\text{th}$ of a pixel).
```cpp
struct LogicalRect {
  LogicalOffset offset; // {inline_offset, block_offset}
  LogicalSize size;     // {inline_size, block_size}
};
```

#### `TableCellLayoutAlgorithm` (`third_party/blink/renderer/core/layout/table/table_cell_layout_algorithm.cc`)
In LayoutNG, a table cell's border-box always stretches to match the row height $R$. Vertical alignment is implemented inside the cell by shifting the cell's child fragments downward in the block direction (effectively inflating the intrinsic top padding).
* **Input (`ConstraintSpace`)**: Receives the target row block-size (`ConstraintSpace().AvailableSize().block_size`, which is $R$ when `IsFixedBlockSize()` is true) and `ConstraintSpace().TableCellAlignmentBaseline()` (which corresponds to `max_row_ascent`).
* **Execution**: During `TableCellLayoutAlgorithm::Layout()`, the algorithm first lays out the cell's contents unconstrained to compute the intrinsic content block-size ($H_{\text{cell}}$) and the cell's first-line baseline ($A_{\text{cell}}$). It then computes the vertical alignment shift $\Delta y$ and translates the `LogicalOffset.block_offset` of all inflow child fragments by $\Delta y$.

---

### 2. Alignment Formula Within Row Height $R$

Let:
* $R \in \mathbb{Z}_{\ge 0}$ be the resolved row height (`row_block_size`).
* $H_{\text{cell}} \in \mathbb{Z}_{\ge 0}$ be the intrinsic block-size of the cell's content box plus its CSS borders and paddings (`cell_height`). By CSS 2.1 §17.5.3, the row height $R$ is at least as large as the maximum $H_{\text{cell}}$ in the row: $R \ge H_{\text{cell}}$.
* $A_{\text{row}} \in \mathbb{Z}_{\ge 0}$ be the maximum cell ascent among all `baseline`-aligned cells in the row (`max_row_ascent`).
* $A_{\text{cell}} \in \mathbb{Z}_{\ge 0}$ be the distance from the top of the cell's border box to its first inflow baseline (`cell_ascent`). By definition of the row baseline computation, $A_{\text{row}} \ge A_{\text{cell}}$ for all baseline-aligned cells in the row.

The vertical alignment block-offset $y$ (applied as an internal block-start shift to the cell's content) is defined by CSS 2.1 §17.5.3 and implemented in Blink as:

1. **Top (`EVerticalAlign::kTop`)**:
   $$y = 0$$

2. **Middle (`EVerticalAlign::kMiddle`)**:
   $$y = \left\lfloor \frac{R - H_{\text{cell}}}{2} \right\rfloor$$
   *(Note: In Blink `LayoutUnit`, integer division `(R - cell_height) / 2` truncates towards zero. Since $R \ge H_{\text{cell}}$, this is equivalent to floor division).*

3. **Bottom (`EVerticalAlign::kBottom`)**:
   $$y = R - H_{\text{cell}}$$

4. **Baseline (`EVerticalAlign::kBaseline`, and fallback values `kSub`, `kSuper`, `kTextTop`, `kTextBottom`, `kLength`)**:
   $$y = A_{\text{row}} - A_{\text{cell}}$$

---

### 3. Mathematical Invariants

Under the structural preconditions guaranteed by the table row sizing pass (`TableLayoutUtils::ComputeRowissez` / `TableRowLayoutAlgorithm`):
1. **Row Sizing Invariant**: $R \ge H_{\text{cell}} \ge 0$.
2. **Baseline Sizing Invariant**: If the cell participates in baseline alignment, then $A_{\text{row}} \ge A_{\text{cell}} \ge 0$, and the row height accommodates both the maximum ascent and maximum descent: $R \ge A_{\text{row}} + (H_{\text{cell}} - A_{\text{cell}})$.

From these preconditions, three core mathematical invariants hold for the computed offset $y$:

1. **Non-Negativity (`cell_vertical_offset_non_negative`)**:
   $$y \ge 0$$
   * *Proof Sketch*: For `top`, $0 \ge 0$. For `middle` and `bottom`, $R \ge H_{\text{cell}} \implies R - H_{\text{cell}} \ge 0 \implies \lfloor(R - H_{\text{cell}})/2\rfloor \ge 0$. For `baseline`, $A_{\text{row}} \ge A_{\text{cell}} \implies A_{\text{row}} - A_{\text{cell}} \ge 0$. (In Blink, this is also defensively enforced via `.ClampNegativeToZero()`).

2. **Containment / Bounding (`cell_plus_offset_le_row_height`)**:
   $$H_{\text{cell}} + y \le R$$
   * *Proof Sketch*: 
     * `top`: $H_{\text{cell}} + 0 = H_{\text{cell}} \le R$.
     * `middle`: $H_{\text{cell}} + \lfloor(R - H_{\text{cell}})/2\rfloor \le H_{\text{cell}} + (R - H_{\text{cell}}) = R$.
     * `bottom`: $H_{\text{cell}} + (R - H_{\text{cell}}) = R \le R$.
     * `baseline`: $H_{\text{cell}} + (A_{\text{row}} - A_{\text{cell}}) = A_{\text{row}} + (H_{\text{cell}} - A_{\text{cell}}) \le R$ (by the Baseline Sizing Invariant).

3. **Determinism (`vertical_align_deterministic`)**:
   For any given cell parameters and row constraint space, the vertical alignment function is a pure total function yielding a unique offset $y$.

---

### 4. Concrete Rocq / Coq Formalization

Below is the complete, self-contained Rocq (Coq) formalization for `BlinkTableCellVerticalAlignSemantics.v`. It uses `Z` (integers) to faithfully model Blink's signed 32-bit fixed-point `LayoutUnit` arithmetic and proves all required invariants using `lia`.

```coq
(** * BlinkTableCellVerticalAlignSemantics.v
    Formalization of Chromium Blink Table Cell Vertical Alignment
    against CSS 2.1 §17.5.3.
    Agent 104 Audit Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** Representation of Blink's [EVerticalAlign] enum.
    CSS 2.1 §17.5.3 specifies that for table cells, values other than
    top, bottom, middle, and baseline fall back to baseline. *)
Inductive EVerticalAlign : Type :=
  | kBaseline
  | kMiddle
  | kSub
  | kSuper
  | kTextTop
  | kTextBottom
  | kTop
  | kBottom
  | kBaselineMiddle
  | kLength.

(** Blink [LayoutUnit] is modeled as an integer [Z] (representing 1/64px units). *)
Definition LayoutUnit := Z.

Record LogicalOffset : Type := mkLogicalOffset {
  inline_offset : LayoutUnit;
  block_offset  : LayoutUnit
}.

Record LogicalSize : Type := mkLogicalSize {
  inline_size : LayoutUnit;
  block_size  : LayoutUnit
}.

Record LogicalRect : Type := mkLogicalRect {
  rect_offset : LogicalOffset;
  rect_size   : LogicalSize
}.

(** Input parameters to [TableCellLayoutAlgorithm] for vertical alignment. *)
Record TableCellAlignInput : Type := mkTableCellAlignInput {
  align_mode     : EVerticalAlign;
  row_height     : LayoutUnit; (** R *)
  cell_height    : LayoutUnit; (** H_cell *)
  max_row_ascent : LayoutUnit; (** A_row *)
  cell_ascent    : LayoutUnit  (** A_cell *)
}.

(** ** 2. Alignment Formulas (CSS 2.1 §17.5.3 & Blink Implementation) *)

(** Helper predicate classifying whether an alignment value resolves to baseline
    in a table cell context. *)
Definition is_baseline_aligned (va : EVerticalAlign) : bool :=
  match va with
  | kTop | kMiddle | kBottom => false
  | _ => true
  end.

(** Computes the vertical alignment offset [y] within the row height [R]. *)
Definition compute_cell_vertical_offset (inp : TableCellAlignInput) : LayoutUnit :=
  match inp.(align_mode) with
  | kTop => 0
  | kMiddle => (inp.(row_height) - inp.(cell_height)) / 2
  | kBottom => inp.(row_height) - inp.(cell_height)
  | _ => inp.(max_row_ascent) - inp.(cell_ascent) (** Baseline & fallbacks *)
  end.

(** Positions the cell content box within the cell's stretched border box. *)
Definition compute_aligned_cell_rect
  (inp : TableCellAlignInput) (cell_inline_size : LayoutUnit) : LogicalRect :=
  let y := compute_cell_vertical_offset inp in
  mkLogicalRect
    (mkLogicalOffset 0 y)
    (mkLogicalSize cell_inline_size inp.(cell_height)).

(** ** 3. Structural Preconditions from Table Row Sizing Pass *)

(** CSS 2.1 §17.5.3 guarantees that the row height [R] is at least the height
    of every cell in the row, and for baseline-aligned cells, [max_row_ascent]
    is at least the cell's ascent, and [R] is at least [max_row_ascent] plus
    the cell's descent ([cell_height - cell_ascent]). *)
Record ValidRowCellConstraints (inp : TableCellAlignInput) : Prop := {
  cell_height_nonneg : 0 <= inp.(cell_height);
  row_fits_cell      : inp.(cell_height) <= inp.(row_height);
  baseline_valid     :
    is_baseline_aligned inp.(align_mode) = true ->
    0 <= inp.(cell_ascent) /\
    inp.(cell_ascent) <= inp.( cell_height) /\
    inp.(cell_ascent) <= inp.(max_row_ascent) /\
    inp.(max_row_ascent) + (inp.(cell_height) - inp.(cell_ascent)) <= inp.(row_height)
}.

(** ** 4. Mathematical Invariants & Theorems *)

(** Invariant 1: The computed vertical offset is always non-negative (y >= 0). *)
Theorem cell_vertical_offset_non_negative :
  forall (inp : TableCellAlignInput),
    ValidRowCellConstraints inp ->
    0 <= compute_cell_vertical_offset inp.
Proof.
  intros inp [H_c_nonneg H_r_fits H_base].
  unfold compute_cell_vertical_offset.
  destruct (align_mode inp) eqn:Hmode; try lia.
  - (* kBaseline *)
    destruct (H_base eq_refl) as [_ [_ [H_asc _]]]; lia.
  - (* kMiddle: (R - H_cell) / 2 >= 0 *)
    apply Z.div_pos; lia.
  - (* kSub *)
    destruct (H_base eq_refl) as [_ [_ [H_asc _]]]; lia.
  - (* kSuper *)
    destruct (H_base eq_refl) as [_ [_ [H_asc _]]]; lia.
  - (* kTextTop *)
    destruct (H_base eq_refl) as [_ [_ [H_asc _]]]; lia.
  - (* kTextBottom *)
    destruct (H_base eq_refl) as [_ [_ [H_asc _]]]; lia.
  - (* kBaselineMiddle *)
    destruct (H_base eq_refl) as [_ [_ [H_asc _]]]; lia.
  - (* kLength *)
    destruct (H_base eq_refl) as [_ [_ [H_asc _]]]; lia.
Qed.

(** Helper lemma for upper-bounding division by 2 on non-negative integers. *)
Lemma div_two_le_self :
  forall x : Z, 0 <= x -> x / 2 <= x.
Proof.
  intros x Hx.
  pose proof (Z.div_mod x 2 ltac:(lia)) as Hdiv.
  pose proof (Z.mod_pos_bound x 2 ltac:(lia)) as Hmod.
  lia.
Qed.

(** Invariant 2: The cell height plus vertical offset never exceeds row height
    (cell_height + y <= R). *)
Theorem cell_plus_offset_le_row_height :
  forall (inp : TableCellAlignInput),
    ValidRowCellConstraints inp ->
    inp.(cell_height) + compute_cell_vertical_offset inp <= inp.(row_height).
Proof.
  intros inp [H_c_nonneg H_r_fits H_base].
  unfold compute_cell_vertical_offset.
  destruct (align_mode inp) eqn:Hmode; try lia.
  - (* kBaseline *)
    destruct (H_base eq_refl) as [_ [_ [_ H_fit]]];