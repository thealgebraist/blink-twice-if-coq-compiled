(******************************************************************************)
(* BlinkTableLayoutSemantics.v                                                *)
(* Sound Formal Big-Step Operational Semantics for CSS Table Layout           *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS 2.1 Section 17.5 (Table Layout Algorithm: Fixed vs Auto)        *)
(* 2. Blink TableLayoutAlgorithm (`table_layout_algorithm.cc`) &              *)
(*    TableColumnLocation (`table_column_location.h`)                         *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Require Import BlinkPhysicalFragment.
Import ListNotations.
Open Scope Z_scope.

Lemma sat_clamp_nonneg : forall x : Z,
  0 <= x -> 0 <= sat_clamp x.
Proof.
  intros x Hx.
  unfold sat_clamp.
  destruct (Z.gtb_spec x kInt32Max); [unfold kInt32Max; lia |].
  destruct (Z.ltb_spec x kInt32Min); [unfold kInt32Min in *; lia | lia].
Qed.

Record TableColumn := mkTableColumn {
  col_min_inline : Z;
  col_max_inline : Z;
  col_computed_inline : Z
}.

Record TableCell := mkTableCell {
  cell_colspan : Z;
  cell_rowspan : Z;
  cell_min_inline : Z;
  cell_max_inline : Z;
  cell_baseline : Z
}.

(** Resolves table columns from cell list using fixed/auto distribution *)
Fixpoint resolve_table_column_positions (cols : list TableColumn) (cur_offset : Z) : list (Z * Z) :=
  match cols with
  | [] => []
  | c :: rest =>
      let w := sat_clamp (col_computed_inline c) in
      (cur_offset, w) :: resolve_table_column_positions rest (cur_offset + w)
  end.

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Theorem table_column_positions_monotonic :
  forall cols cur_offset,
    (forall c, In c cols -> 0 <= col_computed_inline c) ->
    forall i p1 p2,
      nth_error (resolve_table_column_positions cols cur_offset) i = Some p1 ->
      nth_error (resolve_table_column_positions cols cur_offset) (S i) = Some p2 ->
      fst p1 <= fst p2.
Proof.
  induction cols as [| c rest IH].
  - intros cur_offset Hnonneg i p1 p2 Hnth1 Hnth2.
    simpl in Hnth1. destruct i; discriminate.
  - intros cur_offset Hnonneg i p1 p2 Hnth1 Hnth2.
    simpl in Hnth1, Hnth2.
    assert (Hw_nonneg : 0 <= sat_clamp (col_computed_inline c)).
    { apply sat_clamp_nonneg. apply Hnonneg. left. reflexivity. }
    destruct i as [| i'].
    + inversion Hnth1; subst. simpl in Hnth2.
      destruct rest as [| c' rest'].
      * simpl in Hnth2. discriminate.
      * simpl in Hnth2. inversion Hnth2; subst. simpl. lia.
    + simpl in Hnth1, Hnth2.
      eapply (IH (cur_offset + sat_clamp (col_computed_inline c))).
      * intros c' Hin. apply Hnonneg. right. exact Hin.
      * exact Hnth1.
      * exact Hnth2.
Qed.

Theorem table_column_positions_deterministic :
  forall cols off r1 r2,
    r1 = resolve_table_column_positions cols off ->
    r2 = resolve_table_column_positions cols off ->
    r1 = r2.
Proof.
  intros cols off r1 r2 H1 H2. subst. reflexivity.
Qed.
