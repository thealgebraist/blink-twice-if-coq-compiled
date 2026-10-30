### Audit Report: Agent 196 — Blink Column Rule Placement vs. CSS Multi-column Layout Level 1 §4

---

### 1. Rule Placement Semantics (Blink vs. CSS Multi-column 1 §4)

According to **CSS Multi-column Layout Level 1 §4 (Column Gaps and Rules)**, a column rule is drawn in the middle of the column gap between two adjacent columns. If a column rule is wider than its gap, the adjacent column boxes will overlap the rule, and the rule may extend outside the box of the multicol container. Column rules are painted in the inline content layer (specifically, just above the border of the multicol element, below the content of the columns).

In Chromium Blink (`ng_box_fragment_painter.cc` / `ColumnRulePainter`), for a horizontal writing mode with left-to-right inline progression:
- Let `col_end_x` be the inline-end (right) edge coordinate of column $i$.
- Let `gap` be the computed `column-gap` ($\ge 0$).
- Let `rule_width` be the computed width of the `column-rule` ($\ge 0$).
- The next column $i+1$ starts at `next_col_start_x` = `col_end_x + gap`.
- The column rule box has inline-start (left) position:
  $$\text{rule\_x} = \text{col\_end\_x} + \frac{\text{gap} - \text{rule\_width}}{2}$$
- The column rule box has inline-end (right) position:
  $$\text{rule\_end\_x} = \text{rule\_x} + \text{rule\_width} = \text{col\_end\_x} + \frac{\text{gap} + \text{rule\_width}}{2}$$

*(Note: In layout pixels/subpixels `LayoutUnit`, division by 2 may suffer from 1-subpixel truncation, which is modeled cleanly in real/rational arithmetic first before quantization).*

---

### 2. Core Invariants

1. **Centering Invariant (`rule_centered_in_gap`)**:
   - The midpoint of the column rule (`rule_x + rule_width / 2`) is strictly equal to the midpoint of the column gap (`col_end_x + gap / 2`).
   - Equivalently, the distance from the previous column's end edge to the rule's start edge equals the distance from the rule's end edge to the next column's start edge:
     $$\text{rule\_x} - \text{col\_end\_x} = \text{next\_col\_start\_x} - \text{rule\_end\_x}$$

2. **Non-Overlap Invariant (`rule_no_overlap_when_narrow`)**:
   - When `0 <= rule_width <= gap`, the column rule is wholly contained within the column gap interval $[\text{col\_end\_x}, \text{col\_end\_x} + \text{gap}]$.
   - Specifically, `col_end_x <= rule_x` and `rule_end_x <= next_col_start_x`, guaranteeing that the painted rule does not overlap the content area of either adjacent column.

3. **Symmetric Overlap Invariant (`rule_symmetric_overlap_when_wide`)**:
   - When `rule_width > gap`, the rule bleeds equally into both adjacent columns by `(rule_width - gap) / 2`.

---

### 3. Concrete Rocq / Coq Formalization (`BlinkMulticolColumnRuleSemantics.v`)

```coq
(** * BlinkMulticolColumnRuleSemantics.v
    Formal audit of Chromium Blink Column Rule Placement
    against CSS Multi-column Layout Module Level 1, Section 4.
    Agent 196 *)

From Coq Require Import Reals Lra.
Open Scope R_scope.

Section ColumnRulePlacement.

  (** Geometry parameters for a pair of adjacent columns in inline axis *)
  Record ColumnGapGeometry := mkGapGeom {
    col_end_x : R;       (* Inline-end edge of column i *)
    gap : R;             (* Computed column-gap *)
    rule_width : R;      (* Computed column-rule-width *)
    gap_nonneg : 0 <= gap;
    rule_width_nonneg : 0 <= rule_width
  }.

  (** Inline-start edge of column (i + 1) *)
  Definition next_col_start_x (g : ColumnGapGeometry) : R :=
    col_end_x g + gap g.

  (** Blink placement formula: rule_x = col_end_x + (gap - rule_width) / 2 *)
  Definition rule_start_x (g : ColumnGapGeometry) : R :=
    col_end_x g + (gap g - rule_width g) / 2.

  (** Inline-end edge of the column rule *)
  Definition rule_end_x (g : ColumnGapGeometry) : R :=
    rule_start_x g + rule_width g.

  (** Geometric midpoint of an interval [a, b] *)
  Definition midpoint (a b : R) : R :=
    (a + b) / 2.

  (** ** Invariant 1a: Midpoint Centering
      The center of the column rule coincides exactly with the center of the column gap. *)
  Theorem rule_midpoint_centered_in_gap :
    forall (g : ColumnGapGeometry),
      midpoint (rule_start_x g) (rule_end_x g) =
      midpoint (col_end_x g) (next_col_start_x g).
  Proof.
    intros g.
    unfold midpoint, rule_end_x, rule_start_x, next_col_start_x.
    lra.
  Qed.

  (** ** Invariant 1b: Equidistant Margins
      The clearance between column i and the rule equals the clearance
      between the rule and column (i + 1). *)
  Theorem rule_equidistant_from_columns :
    forall (g : ColumnGapGeometry),
      rule_start_x g - col_end_x g = next_col_start_x g - rule_end_x g.
  Proof.
    intros g.
    unfold rule_end_x, rule_start_x, next_col_start_x.
    lra.
  Qed.

  (** ** Invariant 2: Non-Overlap under Standard Rule Width
      When rule_width <= gap, the rule stays strictly within the gap boundaries
      and does not overlap adjacent column content boxes. *)
  Theorem rule_no_overlap_when_narrow :
    forall (g : ColumnGapGeometry),
      rule_width g <= gap g ->
      col_end_x g <= rule_start_x g /\
      rule_start_x g <= rule_end_x g /\
      rule_end_x g <= next_col_start_x g.
  Proof.
    intros g H_narrow.
    pose proof (gap_nonneg g) as H_gap.
    pose proof (rule_width_nonneg g) as H_rw.
    unfold rule_end_x, rule_start_x, next_col_start_x.
    lra.
  Qed.

  (** ** Invariant 3: Symmetric Bleed under Wide Rule
      When rule_width > gap, the rule extends beyond the gap into both
      adjacent columns by the exact same positive amount. *)
  Theorem rule_symmetric_overlap_when_wide :
    forall (g : ColumnGapGeometry),
      gap g < rule_width g ->
      rule_start_x g < col_end_x g /\
      next_col_start_x g < rule_end_x g /\
      (col_end_x g - rule_start_x g) = (rule_end_x g - next_col_start_x g).
  Proof.
    intros g H_wide.
    unfold rule_end_x, rule_start_x, next_col_start_x.
    lra.
  Qed.

End ColumnRulePlacement.
```