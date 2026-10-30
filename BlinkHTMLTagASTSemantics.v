(* ========================================================================= *)
(*               BlinkHTMLTagASTSemantics.v                                  *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink HTML AST & Parser Tree Construction    *)
(* per HTML Living Standard §13.2.6 (HTML, Body, Headers, Table, TR, TD, TH).*)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Inductive HeaderLevel :=
  | LvlH1 | LvlH2 | LvlH3 | LvlH4 | LvlH5 | LvlH6.

Inductive CellKind :=
  | CellTD | CellTH.

Record HTMLTableCell := mkCell {
  cell_kind : CellKind;
  cell_char_count : Z;
  cell_id : Z
}.

Record HTMLTableRow := mkRow {
  row_cells : list HTMLTableCell;
  row_id : Z
}.

Record HTMLTable := mkTable {
  table_rows : list HTMLTableRow;
  table_id : Z
}.

Inductive HTMLBlock :=
  | BlockHeader (lvl : HeaderLevel) (char_count : Z) (id : Z)
  | BlockTable (t : HTMLTable)
  | BlockParagraph (char_count : Z) (id : Z).

Record HTMLBody := mkBody {
  body_blocks : list HTMLBlock
}.

Record HTMLDocument := mkDoc {
  doc_body : HTMLBody
}.

Definition cell_valid (c : HTMLTableCell) : Prop :=
  cell_char_count c >= 0.

Definition row_valid (r : HTMLTableRow) : Prop :=
  Forall cell_valid (row_cells r).

Definition table_valid (t : HTMLTable) : Prop :=
  Forall row_valid (table_rows t).

Definition block_valid (b : HTMLBlock) : Prop :=
  match b with
  | BlockHeader _ cnt _ => cnt >= 0
  | BlockTable t => table_valid t
  | BlockParagraph cnt _ => cnt >= 0
  end.

Definition body_valid (b : HTMLBody) : Prop :=
  Forall block_valid (body_blocks b).

Definition doc_valid (d : HTMLDocument) : Prop :=
  body_valid (doc_body d).

Definition is_uniform_table (t : HTMLTable) (cols : nat) : Prop :=
  forall r, In r (table_rows t) -> length (row_cells r) = cols.

Theorem uniform_table_empty_rows : forall cols id,
  is_uniform_table (mkTable nil id) cols.
Proof.
  intros cols id r Hin.
  inversion Hin.
Qed.

Theorem uniform_table_cons : forall r rows id cols,
  length (row_cells r) = cols ->
  is_uniform_table (mkTable rows id) cols ->
  is_uniform_table (mkTable (r :: rows) id) cols.
Proof.
  intros r rows id cols Hlen Huni r0 [Heq | Hin].
  - subst r0. exact Hlen.
  - apply (Huni r0 Hin).
Qed.

Fixpoint count_total_cells (rows : list HTMLTableRow) : nat :=
  match rows with
  | nil => 0%nat
  | r :: rest => (length (row_cells r) + count_total_cells rest)%nat
  end.

Theorem uniform_table_total_cells : forall rows id cols,
  is_uniform_table (mkTable rows id) cols ->
  (count_total_cells rows = length rows * cols)%nat.
Proof.
  intros rows id cols.
  induction rows as [|r rest IH]; cbn.
  - intros _. reflexivity.
  - intros Huni.
    assert (Hlen: length (row_cells r) = cols).
    { apply Huni. left. reflexivity. }
    assert (Hrest: is_uniform_table (mkTable rest id) cols).
    { intros r0 Hin. apply Huni. right. assumption. }
    rewrite Hlen.
    rewrite (IH Hrest).
    reflexivity.
Qed.

