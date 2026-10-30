(* ========================================================================= *)
(*               BlinkLayoutBoxGenerationSemantics.v                         *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Layout Box Generation from Styled      *)
(* HTML Elements per W3C CSS Display Module Level 3 §2.                      *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Require Import BlinkHTMLTagASTSemantics.
Open Scope Z_scope.

Record LayoutTableCellBox := mkCellBox {
  cell_box_kind : CellKind;
  cell_box_char_count : Z;
  cell_box_font_size : Z;
  cell_box_id : Z
}.

Record LayoutTableRowBox := mkRowBox {
  row_box_cells : list LayoutTableCellBox;
  row_box_id : Z
}.

Record LayoutTableBox := mkTableBox {
  table_box_rows : list LayoutTableRowBox;
  table_box_border_spacing : Z;
  table_box_id : Z
}.

Record LayoutHeaderBox := mkHeaderBox {
  header_box_level : HeaderLevel;
  header_box_char_count : Z;
  header_box_font_size : Z;
  header_box_margin_top : Z;
  header_box_margin_bottom : Z;
  header_box_id : Z
}.

Definition generate_cell_box (c : HTMLTableCell) (font_size : Z) : LayoutTableCellBox :=
  {| cell_box_kind := cell_kind c;
     cell_box_char_count := cell_char_count c;
     cell_box_font_size := font_size;
     cell_box_id := cell_id c |}.

Definition generate_row_box (r : HTMLTableRow) (font_size : Z) : LayoutTableRowBox :=
  {| row_box_cells := map (fun c => generate_cell_box c font_size) (row_cells r);
     row_box_id := row_id r |}.

Definition generate_table_box (t : HTMLTable) (border_spacing : Z) (font_size : Z) : LayoutTableBox :=
  {| table_box_rows := map (fun r => generate_row_box r font_size) (table_rows t);
     table_box_border_spacing := border_spacing;
     table_box_id := table_id t |}.

Definition generate_header_box
  (lvl : HeaderLevel) (char_count : Z) (font_size : Z)
  (m_top : Z) (m_bot : Z) (id : Z) : LayoutHeaderBox :=
  {| header_box_level := lvl;
     header_box_char_count := char_count;
     header_box_font_size := font_size;
     header_box_margin_top := m_top;
     header_box_margin_bottom := m_bot;
     header_box_id := id |}.

Theorem generate_row_preserves_cell_count : forall r f,
  length (row_box_cells (generate_row_box r f)) = length (row_cells r).
Proof.
  intros r f.
  unfold generate_row_box; cbn.
  apply length_map.
Qed.

Theorem generate_table_preserves_row_count : forall t sp f,
  length (table_box_rows (generate_table_box t sp f)) = length (table_rows t).
Proof.
  intros t sp f.
  unfold generate_table_box; cbn.
  apply length_map.
Qed.

Theorem generate_cell_preserves_metrics : forall c f,
  cell_box_char_count (generate_cell_box c f) = cell_char_count c /\
  cell_box_font_size (generate_cell_box c f) = f.
Proof.
  intros.
  unfold generate_cell_box; cbn.
  split; reflexivity.
Qed.

Theorem generate_header_preserves_metrics : forall lvl cnt f mt mb id,
  header_box_char_count (generate_header_box lvl cnt f mt mb id) = cnt /\
  header_box_font_size (generate_header_box lvl cnt f mt mb id) = f /\
  header_box_margin_top (generate_header_box lvl cnt f mt mb id) = mt /\
  header_box_margin_bottom (generate_header_box lvl cnt f mt mb id) = mb.
Proof.
  intros.
  unfold generate_header_box; cbn.
  repeat split; reflexivity.
Qed.
