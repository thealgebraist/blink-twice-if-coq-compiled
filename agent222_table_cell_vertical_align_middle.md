### 1. Middle Alignment Specification (CSS 2.1 §17.5.3 vs. Chromium Blink)

In CSS 2.1 §17.5.3 ("Table height algorithms"), the `vertical-align: middle` property on a table cell specifies that the center of the cell is aligned with the center of the row it spans. When the computed row height exceeds the intrinsic content box and existing vertical padding of the cell, User Agents achieve this alignment by adding extra intrinsic top and bottom padding (or an equivalent layout y-offset) to the cell.

In Chromium Blink (`ng_table_layout_algorithm_utils.cc` / `table_row_layout_algorithm.cc`), the extra vertical space in a row is distributed equally above and below the cell's content box:

$$\text{y\_offset} = \max\left(0, \left\lfloor \frac{\text{row\_height} - \text{cell\_height}}{2} \right\rfloor\right)$$

Where:
* $\text{row\_height}$ is the final computed height of the table row spanned by the cell.
* $\text{cell\_height}$ is the total intrinsic height of the cell, defined as $\text{padding\_top} + \text{content\_height} + \text{padding\_bottom}$ (including borders in border-box adjustments).

---

### 2. Core Layout Invariants

To guarantee absence of vertical layout underflow or cell overflow within the row box during vertical alignment calculations, Blink enforces the following invariants:

1. **Non-Negativity Invariant**: When $\text{row\_height} \ge \text{cell\_height}$ (guaranteed after the row height distribution phase in §17.5.3), the computed alignment offset satisfies $\text{y\_offset} \ge 0$.
2. **Row Containment Invariant**: The offset combined with the intrinsic cell height never overflows the allocated row height:
   $$\text{y\_offset} + \text{cell\_height} \le \text{row\_height}$$
   Expanding $\text{cell\_height}$ into its constituent components ($\text{padding\_top} + \text{content\_height} + \text{padding\_bottom}$ where all components are $\ge 0$), this directly implies the boundary safety invariant:
   $$\text{padding\_top} + \text{y\_offset} + \text{content\_height} \le \text{row\_height}$$
   And in the specific case where $\text{cell\_height}$ represents the unpadded content box and $\text{row\_height} \ge \text{cell\_height} + 2 \cdot \text{padding\_top}$:
   $$\text{padding\_top} + \text{y\_offset} + \text{cell\_height} \le \text{row\_height}$$

---

### 3. Concrete Rocq / Coq Formalization

Below is the complete, self-contained formalization for `BlinkTableCellVerticalAlignMiddleSemantics.v` using `ZArith` and `Lia`, containing zero `Admitted` statements.

```coq
(** * BlinkTableCellVerticalAlignMiddleSemantics.v
    Formal verification of Chromium Blink Table Cell Vertical-Align Middle
    against CSS 2.1 Section 17.5.3 (Table height algorithms).
    Agent 222 Audit Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Section TableCellVerticalAlignMiddle.

  (** ** 1. Definitions *)

  (** Computes the vertical alignment y-offset for a table cell with 
      [vertical-align: middle] inside a table row.
      Corresponds to: (row_height - cell_height) / 2 in integer layout units. *)
  Definition compute_middle_y_offset (row_height cell_height : Z) : Z :=
    (row_height - cell_height) / 2.

  (** Clamped version used in Blink layout algorithms to prevent negative offsets
      prior to row-sizing stabilization. *)
  Definition compute_middle_y_offset_clamped (row_height cell_height : Z) : Z :=
    Z.max 0 (compute_middle_y_offset row_height cell_height).

  (** Total intrinsic cell box height composed of top padding, content, and bottom padding. *)
  Definition total_cell_height (padding_top content_height padding_bottom : Z) : Z :=
    padding_top + content_height + padding_bottom.

  (** ** 2. Helper Lemmas for Integer Division by 2 *)

  Lemma div2_nonneg : forall x : Z,
    0 <= x -> 0 <= x / 2.
  Proof.
    intros x Hx.
    apply Z.div_pos; lia.
  Qed.

  Lemma div2_le_self : forall x : Z,
    0 <= x -> x / 2 <= x.
  Proof.
    intros x Hx.
     assert (H: x = 2 * (x / 2) + x mod 2) by (apply Z.div_mod; lia).
    assert (Hmod: 0 <= x mod 2 < 2) by (apply Z.mod_pos_bound; lia).
    lia.
  Qed.

  Lemma twice_div2_le : forall x : Z,
    0 <= x -> 2 * (x / 2) <= x.
  Proof.
    intros x Hx.
    assert (H: x = 2 * (x / 2) + x mod 2) by (apply Z.div_mod; lia).
    assert (Hmod: 0 <= x mod 2 < 2) by (apply Z.mod_pos_bound; lia).
    lia.
  Qed.

  (** ** 3. Primary Audit Theorems & Invariants *)

  (** Invariant 1: y_offset >= 0 when row_height >= cell_height. *)
  Theorem middle_y_offset_nonneg : forall row_height cell_height : Z,
    row_height >= cell_height ->
    compute_middle_y_offset row_height cell_height >= 0.
  Proof.
    intros row_height cell_height Hge.
    unfold compute_middle_y_offset.
    apply Z.le_ge.
    apply div2_nonneg.
    lia.
  Qed.

  (** Equivalence of clamped and unclamped offsets when row_height >= cell_height. *)
  Theorem clamped_eq_unclamped_when_valid : forall row_height cell_height : Z,
    row_height >= cell_height ->
    compute_middle_y_offset_clamped row_height cell_height =
    compute_middle_y_offset row_height cell_height.
  Proof.
    intros row_height cell_height Hge.
    unfold compute_middle_y_offset_clamped.
    rewrite Z.max_r.
    - reflexivity.
    - apply Z.ge_le. apply middle_y_offset_nonneg. exact Hge.
  Qed.

  (** Invariant 2a (Total Cell Box Containment):
      y_offset + cell_height <= row_height when row_height >= cell_height. *)
  Theorem middle_y_offset_cell_containment : forall row_height cell_height : Z,
    row_height >= cell_height ->
    compute_middle_y_offset row_height cell_height + cell_height <= row_height.
  Proof.
    intros row_height cell_height Hge.
    unfold compute_middle_y_offset.
    assert (Hdiff: 0 <= row_height - cell_height) by lia.
    pose proof (div2_le_self (row_height - cell_height) Hdiff) as Hle.
    lia.
  Qed.

  (** Invariant 2b (Symmetric Top/Bottom Offset Containment):
      2 * y_offset + cell_height <= row_height. *)
  Theorem middle_y_offset_symmetric_containment : forall row_height cell_height : Z,
    row_height >= cell_height ->
    2 * compute_middle_y_offset row_height cell_height + cell_height <= row_height.
  Proof.
    intros row_height cell_height Hge.
    unfold compute_middle_y_offset.
    assert (Hdiff: 0 <= row_height - cell_height) by lia.
    pose proof (twice_div2_le (row_height - cell_height) Hdiff) as Hle.
    lia.
  Qed.

  (** Invariant 2c (Explicit Top Padding + y_offset + Content Height Containment):
      When cell_height includes padding_top, content_height, and padding_bottom,
      top_padding + y_offset + content_height <= row_height. *)
  Theorem top_padding_offset_content_le_row_height :
    forall row_height padding_top content_height padding_bottom : Z,
      padding_top >= 0 ->
      content_height >= 0 ->
      padding_bottom >= 0 ->
      let cell_height := total_cell_height padding_top content_height padding_bottom in
      row_height >= cell_height ->
      padding_top + compute_middle_y_offset row_height cell_height + content_height <= row_height.
  Proof.
    intros row_height padding_top content_height padding_bottom Hpt Hch Hpb cell_height Hge.
    pose proof (middle_y_offset_cell_containment row_height cell_height Hge) as Hcontain.
    unfold cell_height, total_cell_height in Hcontain.
    lia.
  Qed.

  (** Invariant 2d (Literal Unpadded Cell Height Formulation):
      If cell_height is the unpadded content height and the row accommodates both
      symmetric top padding and the cell height (row_height >= cell_height + 2 * top_padding),
      then top_padding + y_offset + cell_height <= row_height. *)
  Theorem top_padding_plus_y_offset_plus_cell_le_row_height :
    forall row_height cell_height top_padding : Z,
      top_padding >= 0 ->
      row_height >= cell_height + 2 * top_padding ->
      top_padding + compute_middle_y_offset row_height cell_height + cell_height <= row_height.
  Proof.
    intros row_height cell_height top_padding Htp Hge.
    unfold compute_middle_y_offset.
    assert (Hdiff: 0 <= row_height - cell_height) by lia.
    pose proof (twice_div2_le (row_height - cell_height) Hdiff) as Hle.
    lia.
  Qed.

End TableCellVerticalAlignMiddle.
```