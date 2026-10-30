(* =========================================================================
   BlinkTableRowSpanDistributionSemantics.v
   Formalization of Chromium Blink Rowspan Height Distribution across Rows
   Source: third_party/blink/renderer/core/layout/table/table_row_height_tracker.cc
   Specification: W3C CSS 2.1 §17.5.3 Multi-row Cell Height Distribution
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

Definition distribute_rowspan_deficit_2rows
    (h1 : Z) (h2 : Z) (required_cell_height : Z) : Z * Z :=
  let current_h := h1 + h2 in
  let delta := Z.max 0 (required_cell_height - current_h) in
  let d1 := delta / 2 in
  let d2 := delta - d1 in
  (h1 + d1, h2 + d2).

Theorem rowspan_distribution_non_decreasing :
  forall h1 h2 req_h,
    let (h1', h2') := distribute_rowspan_deficit_2rows h1 h2 req_h in
    h1 <= h1' /\ h2 <= h2'.
Proof.
  intros h1 h2 req_h.
  unfold distribute_rowspan_deficit_2rows.
  set (delta := Z.max 0 (req_h - (h1 + h2))).
  assert (Hdelta_pos : 0 <= delta) by (apply Z.le_max_l).
  assert (Hd1_pos : 0 <= delta / 2) by (apply Z.div_pos; lia).
  assert (Hd2_pos : 0 <= delta - delta / 2).
  { assert (delta / 2 <= delta) by (apply Z.div_le_upper_bound; lia). lia. }
  split; lia.
Qed.

Theorem rowspan_distribution_satisfies_requirement :
  forall h1 h2 req_h,
    0 <= h1 ->
    0 <= h2 ->
    let (h1', h2') := distribute_rowspan_deficit_2rows h1 h2 req_h in
    req_h <= h1' + h2'.
Proof.
  intros h1 h2 req_h H1 H2.
  unfold distribute_rowspan_deficit_2rows.
  set (delta := Z.max 0 (req_h - (h1 + h2))).
  assert (Hsum : (h1 + delta / 2) + (h2 + (delta - delta / 2)) = (h1 + h2) + delta) by lia.
  rewrite Hsum.
  pose proof (Z.le_max_r 0 (req_h - (h1 + h2))) as Hdef.
  lia.
Qed.

Theorem rowspan_distribution_deficit_conservation :
  forall h1 h2 req_h,
    let current_h := h1 + h2 in
    let delta := Z.max 0 (req_h - current_h) in
    let (h1', h2') := distribute_rowspan_deficit_2rows h1 h2 req_h in
    (h1' + h2') - current_h = delta.
Proof.
  intros h1 h2 req_h.
  unfold distribute_rowspan_deficit_2rows.
  lia.
Qed.

Theorem distribute_rowspan_deterministic :
  forall h1 h2 req_h r1 r2,
    r1 = distribute_rowspan_deficit_2rows h1 h2 req_h ->
    r2 = distribute_rowspan_deficit_2rows h1 h2 req_h ->
    r1 = r2.
Proof.
  intros h1 h2 req_h r1 r2 H1 H2.
  subst. reflexivity.
Qed.

