### Audit Report: Agent 221
**Target:** Chromium Blink Table Row Percentage Height vs. CSS 2.1 §17.5.3  
**Module:** `BlinkTableRowPercentHeightSemantics.v`  

---

### 1. Specification & Engine Resolution Analysis

In CSS 2.1 §17.5.3 (*Table height algorithms*), the specification notes: *"CSS 2.1 does not define the meaning of 'height' on table rows and row groups when specified as a percentage."* 

To ensure web compatibility and deterministic layout, Chromium Blink (`third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc` and `table_layout_utils.cc`) implements a concrete resolution mechanism for percentage-based heights on `<tr>` (`LayoutTableRow`) elements when the parent `<table>` has a resolvable height:

1. **Resolution Formula:**
   $$\text{row\_height} = \max\left(\text{row\_min\_content}, \left\lfloor\frac{\text{table\_height} \times \text{pct}}{100}\right\rfloor\right)$$
   - `row_min_content`: The intrinsic minimum content height required by the row's cells (including borders and padding).
   - `table_height`: The resolved block-size of the containing table.
   - `pct`: The non-negative percentage value specified on the table row.

2. **Core Layout Invariants:**
   - **Content Floor Invariant:** A table row can never shrink below the height required by its content: $\text{row\_height} \ge \text{row\_min\_content}$.
   - **Table Monotonicity Invariant:** Increasing the containing table's height will never cause a percentage-height row to shrink: $\text{table\_height}_1 \le \text{table\_height}_2 \implies \text{row\_height}_1 \le \text{row\_height}_2$.

---

### 2. Formal Verification in Rocq (Coq)

Below is the complete, self-contained formalization for `BlinkTableRowPercentHeightSemantics.v`. It uses standard integer arithmetic (`ZArith`) to model Blink's `LayoutUnit` fixed-point representation and verifies all invariants with **0 admits**.

```coq
(** * BlinkTableRowPercentHeightSemantics.v
    Formalization of Chromium Blink Table Row Percentage Height Resolution
    against CSS 2.1 Section 17.5.3.
    Agent 221 Audit Artifact. *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.

Open Scope Z_scope.

Section BlinkTableRowPercentHeight.

  (** ** 1. Definitions *)

  (** Resolves the percentage contribution against the table's height.
      Models integer / fixed-point LayoutUnit truncation. *)
  Definition resolve_percent (table_height pct : Z) : Z :=
    (table_height * pct) / 100.

  (** Computes the final table row height as the maximum of its minimum
      content height and the resolved percentage height. *)
  Definition compute_row_height (row_min_content table_height pct : Z) : Z :=
    Z.max row_min_content (resolve_percent table_height pct).


  (** ** 2. Invariant Proofs *)

  (** Invariant 1: The computed row height is always at least the row's
      minimum content height, preventing content overflow/clipping. *)
  Theorem row_height_ge_min_content :
    forall (row_min_content table_height pct : Z),
      compute_row_height row_min_content table_height pct >= row_min_content.
  Proof.
    intros row_min_content table_height pct.
    unfold compute_row_height.
    apply Z.le_ge.
    apply Z.le_max_l.
  Qed.

  (** Helper Lemma: Percentage resolution is monotonic with respect to
      table height for non-negative percentages. *)
  Lemma resolve_percent_monotonic_table_height :
    forall (th1 th2 pct : Z),
      0 <= pct ->
      th1 <= th2 ->
      resolve_percent th1 pct <= resolve_percent th2 pct.
  Proof.
    intros th1 th2 pct Hpct Hth.
    unfold resolve_percent.
    apply Z.div_le_mono.
    - lia.
    - apply Z.mul_le_mono_nonneg_r; assumption.
  Qed.

  (** Invariant 2: The computed row height is monotonic in table_height
      when the percentage is non-negative. *)
  Theorem row_height_monotonic_in_table_height :
    forall (row_min_content th1 th2 pct : Z),
      0 <= pct ->
      th1 <= th2 ->
      compute_row_height row_min_content th1 pct <=
      compute_row_height row_min_content th2 pct.
  Proof.
    intros row_min_content th1 th2 pct Hpct Hth.
    unfold compute_row_height.
    pose proof (resolve_percent_monotonic_table_height th1 th2 pct Hpct Hth) as Hres.
    lia.
  Qed.

  (** Additional Invariant 3: The computed row height is monotonic in the
      specified percentage when table_height is non-negative. *)
  Theorem row_height_monotonic_in_pct :
    forall (row_min_content table_height pct1 pct2 : Z),
      0 <= table_height ->
      pct1 <= pct2 ->
      compute_row_height row_min_content table_height pct1 <=
      compute_row_height row_min_content table_height pct2.
  Proof.
    intros row_min_content table_height pct1 pct2 Hth Hpct.
    unfold compute_row_height, resolve_percent.
    assert (Hmul: table_height * pct1 <= table_height * pct2).
    { apply Z.mul_le_mono_nonneg_l; assumption. }
    assert (Hdiv: (table_height * pct1) / 100 <= (table_height * pct2) / 100).
    { apply Z.div_le_mono; [lia | exact Hmul]. }
    lia.
  Qed.

  (** Additional Invariant 4: Zero percent collapses to row_min_content
      assuming non-negative row_min_content. *)
  Theorem row_height_zero_pct :
    forall (row_min_content table_height : Z),
      0 <= row_min_content ->
      compute_row_height row_min_content table_height 0 = row_min_content.
  Proof.
    intros row_min_content table_height Hmin.
    unfold compute_row_height, resolve_percent.
    rewrite Z.mul_0_r.
    change (0 / 100) with 0.
    lia.
  Qed.

End BlinkTableRowPercentHeight.
```