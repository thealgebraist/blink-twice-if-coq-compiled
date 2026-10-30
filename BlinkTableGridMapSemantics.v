(* =========================================================================
   BlinkTableGridMapSemantics.v
   Formalization of Chromium Blink Table Structural Grid & Cell Map Resolution
   Source: third_party/blink/renderer/core/layout/table/table_node.cc
           third_party/blink/renderer/core/layout/table/table_layout_algorithm_types.cc
   Specification: HTML Standard §4.9.11 Forming a table & CSS 2.1 §17.5
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

Definition kMaxColSpan : Z := 1000.
Definition kMaxRowSpan : Z := 65534.

Definition clamp_colspan (cs : Z) : Z :=
  Z.min kMaxColSpan (Z.max 1 cs).

Definition clamp_rowspan (rs : Z) : Z :=
  Z.min kMaxRowSpan (Z.max 0 rs).

Record TableCellDesc : Type := mkTableCellDesc {
  tc_id : nat;
  tc_raw_colspan : Z;
  tc_raw_rowspan : Z
}.

Record ResolvedCellPlacement : Type := mkResolvedCellPlacement {
  rcp_id : nat;
  rcp_start_row : Z;
  rcp_start_col : Z;
  rcp_colspan : Z;
  rcp_rowspan : Z
}.

Definition resolve_cell_placement
    (cell : TableCellDesc) (cur_row : Z) (cur_col : Z) : ResolvedCellPlacement :=
  let eff_cs := clamp_colspan cell.(tc_raw_colspan) in
  let eff_rs := clamp_rowspan cell.(tc_raw_rowspan) in
  let rs := if eff_rs =? 0 then 1 else eff_rs in
  mkResolvedCellPlacement cell.(tc_id) cur_row cur_col eff_cs rs.

Theorem colspan_clamped_bounds :
  forall cs,
    1 <= clamp_colspan cs <= kMaxColSpan.
Proof.
  intros cs.
  unfold clamp_colspan, kMaxColSpan.
  lia.
Qed.

Theorem rowspan_clamped_bounds :
  forall rs,
    0 <= clamp_rowspan rs <= kMaxRowSpan.
Proof.
  intros rs.
  unfold clamp_rowspan, kMaxRowSpan.
  lia.
Qed.

Theorem cell_cursor_advances_strictly :
  forall cell cur_row cur_col,
    cur_col < cur_col + (resolve_cell_placement cell cur_row cur_col).(rcp_colspan).
Proof.
  intros cell cur_row cur_col.
  unfold resolve_cell_placement. simpl.
  pose proof (colspan_clamped_bounds cell.(tc_raw_colspan)) as [Hge _].
  lia.
Qed.

Theorem resolve_cell_placement_deterministic :
  forall cell r c p1 p2,
    p1 = resolve_cell_placement cell r c ->
    p2 = resolve_cell_placement cell r c ->
    p1 = p2.
Proof.
  intros cell r c p1 p2 H1 H2.
  subst. reflexivity.
Qed.
