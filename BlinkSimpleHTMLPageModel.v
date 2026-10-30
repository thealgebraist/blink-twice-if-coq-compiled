(* ========================================================================= *)
(*               BlinkSimpleHTMLPageModel.v                                  *)
(* ========================================================================= *)
(* Comprehensive End-to-End Rocq/Coq Formal Model of a Simple HTML Page with *)
(* Headers (H1, H2), Tables (TR, TH, TD), and Simple CSS per Chromium Blink. *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Require Import BlinkHTMLTagASTSemantics.
Require Import BlinkHTMLUASheetSemantics.
Require Import BlinkCSSUnitResolutionSemantics.
Require Import BlinkSimpleCSSCascadeSemantics.
Require Import BlinkLayoutBoxGenerationSemantics.
Require Import BlinkHeaderMarginCollapsingSemantics.
Require Import BlinkTableAutoColumnSizingSemantics.
Require Import BlinkTableCellVerticalAlignSemantics.
Require Import BlinkTableSeparatedGridSemantics.
Require Import BlinkInlineTextRunLayoutSemantics.
Require Import BlinkTextAlignGeometrySemantics.
Require Import BlinkTableCellNonOverlapSemantics.
Require Import BlinkViewportICBLayoutSemantics.
Require Import BlinkTableRowHeightAccumulationSemantics.
Require Import BlinkPageFragmentAssemblySemantics.
Require Import BlinkPhysicalFragment.
Open Scope Z_scope.

Record SimpleTable2x2 := mkSimpleTable2x2 {
  st_th1_len : Z;
  st_th2_len : Z;
  st_td1_len : Z;
  st_td2_len : Z;
  st_border_spacing : Z
}.

Record SimpleHTMLPage := mkSimplePage {
  page_h1_len : Z;
  page_h2_len : Z;
  page_table : SimpleTable2x2
}.

Record PageLayoutOutput := mkPageLayoutOutput {
  plo_page_fragment : PhysicalFragment;
  plo_body_width : Z;
  plo_h1_y : Z;
  plo_h1_h : Z;
  plo_h2_y : Z;
  plo_h2_h : Z;
  plo_table_y : Z;
  plo_table_w : Z;
  plo_table_h : Z;
  plo_cell_w0 : Z;
  plo_cell_w1 : Z;
  plo_row_h0 : Z;
  plo_row_h1 : Z
}.

Definition layout_simple_page_pipeline
  (viewport_w viewport_h : Z)
  (page : SimpleHTMLPage) : PageLayoutOutput :=
  let body_margin := 8 in
  let body_w := body_inline_size viewport_w body_margin in
  
  let h1_fs := ua_font_size (get_ua_style TagH1) in (* 32 *)
  let h1_mt := ua_margin_top (get_ua_style TagH1) in (* 21 *)
  let h1_mb := ua_margin_bottom (get_ua_style TagH1) in (* 21 *)
  let h1_h := text_run_line_height h1_fs in (* (32 * 12) / 10 = 38 *)
  let h1_w := text_run_advance (page_h1_len page) h1_fs in
  let h1_y := body_margin + h1_mt in
  
  let h2_fs := ua_font_size (get_ua_style TagH2) in (* 24 *)
  let h2_mt := ua_margin_top (get_ua_style TagH2) in (* 20 *)
  let h2_mb := ua_margin_bottom (get_ua_style TagH2) in (* 20 *)
  let h2_h := text_run_line_height h2_fs in (* (24 * 12) / 10 = 28 *)
  let h2_w := text_run_advance (page_h2_len page) h2_fs in
  let collapsed_h1_h2 := collapse_margins h1_mb h2_mt in
  let h2_y := h1_y + h1_h + collapsed_h1_h2 in
  
  let tbl := page_table page in
  let tbl_mt := ua_margin_top (get_ua_style TagTable) in (* 0 *)
  let collapsed_h2_tbl := collapse_margins h2_mb tbl_mt in
  let tbl_y := h2_y + h2_h + collapsed_h2_tbl in
  let sp := st_border_spacing tbl in
  
  let cell_fs := ua_font_size (get_ua_style TagTD) in (* 16 *)
  let row_h0 := text_run_line_height cell_fs + 2 in (* cell padding 1px top+bot = 2 *)
  let row_h1 := text_run_line_height cell_fs + 2 in
  
  let c00_w := text_run_advance (st_th1_len tbl) cell_fs + 2 in
  let c10_w := text_run_advance (st_td1_len tbl) cell_fs + 2 in
  let col0_min := Z.max c00_w c10_w in
  
  let c01_w := text_run_advance (st_th2_len tbl) cell_fs + 2 in
  let c11_w := text_run_advance (st_td2_len tbl) cell_fs + 2 in
  let col1_min := Z.max c01_w c11_w in
  
  let col_widths := distribute_2cols col0_min (col0_min + 50) col1_min (col1_min + 50) (body_w - 3 * sp) in
  let w0 := fst col_widths in
  let w1 := snd col_widths in
  
  let tbl_w := table_2x2_total_width w0 w1 sp in
  let tbl_h := table_2x2_total_height row_h0 row_h1 sp in
  
  let cell_00_f := mkPhysicalFragment (table_2x2_col_x 0 w0 w1 sp) (table_2x2_row_y 0 row_h0 row_h1 sp) w0 row_h0 nil in
  let cell_01_f := mkPhysicalFragment (table_2x2_col_x 1 w0 w1 sp) (table_2x2_row_y 0 row_h0 row_h1 sp) w1 row_h0 nil in
  let row_0_f := assemble_row_fragment (cell_00_f :: cell_01_f :: nil) 0 (table_2x2_row_y 0 row_h0 row_h1 sp) tbl_w row_h0 in
  
  let cell_10_f := mkPhysicalFragment (table_2x2_col_x 0 w0 w1 sp) (table_2x2_row_y 1 row_h0 row_h1 sp) w0 row_h1 nil in
  let cell_11_f := mkPhysicalFragment (table_2x2_col_x 1 w0 w1 sp) (table_2x2_row_y 1 row_h0 row_h1 sp) w1 row_h1 nil in
  let row_1_f := assemble_row_fragment (cell_10_f :: cell_11_f :: nil) 0 (table_2x2_row_y 1 row_h0 row_h1 sp) tbl_w row_h1 in
  
  let table_f := assemble_table_fragment (row_0_f :: row_1_f :: nil) body_margin tbl_y tbl_w tbl_h in
  let h1_f := mkPhysicalFragment body_margin h1_y h1_w h1_h nil in
  let h2_f := mkPhysicalFragment body_margin h2_y h2_w h2_h nil in
  
  let body_total_h := tbl_y + tbl_h + body_margin in
  let body_f := assemble_body_fragment (h1_f :: h2_f :: table_f :: nil) body_margin body_margin body_w body_total_h in
  let page_f := assemble_page_fragment body_f viewport_w viewport_h in
  
  {| plo_page_fragment := page_f;
     plo_body_width := body_w;
     plo_h1_y := h1_y;
     plo_h1_h := h1_h;
     plo_h2_y := h2_y;
     plo_h2_h := h2_h;
     plo_table_y := tbl_y;
     plo_table_w := tbl_w;
     plo_table_h := tbl_h;
     plo_cell_w0 := w0;
     plo_cell_w1 := w1;
     plo_row_h0 := row_h0;
     plo_row_h1 := row_h1 |}.

Definition sample_page : SimpleHTMLPage :=
  {| page_h1_len := 12;      (* "Hello World!" *)
     page_h2_len := 18;      (* "Section Overview" *)
     page_table :=
       {| st_th1_len := 6;   (* "Item #" *)
          st_th2_len := 12;  (* "Description" *)
          st_td1_len := 3;   (* "001" *)
          st_td2_len := 8;   (* "Keyboard" *)
          st_border_spacing := 2 |} |}.

Theorem page_layout_deterministic : forall vw vh p,
  layout_simple_page_pipeline vw vh p = layout_simple_page_pipeline vw vh p.
Proof.
  intros. reflexivity.
Qed.

Theorem page_root_dimensions_exact : forall vw vh p,
  pf_w (plo_page_fragment (layout_simple_page_pipeline vw vh p)) = vw /\
  pf_h (plo_page_fragment (layout_simple_page_pipeline vw vh p)) = vh.
Proof.
  intros vw vh p.
  unfold layout_simple_page_pipeline; cbn.
  split; reflexivity.
Qed.

Theorem page_headers_table_vertical_ordering : forall vw vh p,
  page_h1_len p >= 0 ->
  page_h2_len p >= 0 ->
  let out := layout_simple_page_pipeline vw vh p in
  plo_h1_y out < plo_h2_y out /\
  plo_h2_y out < plo_table_y out.
Proof.
  intros vw vh p Hh1 Hh2 out.
  unfold out, layout_simple_page_pipeline; cbn.
  split; lia.
Qed.

Theorem page_table_cells_pairwise_disjoint : forall vw vh p,
  st_border_spacing (page_table p) >= 0 ->
  let out := layout_simple_page_pipeline vw vh p in
  let w0 := plo_cell_w0 out in
  let w1 := plo_cell_w1 out in
  let h0 := plo_row_h0 out in
  let h1 := plo_row_h1 out in
  let sp := st_border_spacing (page_table p) in
  rect_disjoint_2d (table_2x2_col_x 0 w0 w1 sp) (table_2x2_row_y 0 h0 h1 sp) w0 h0
                   (table_2x2_col_x 1 w0 w1 sp) (table_2x2_row_y 0 h0 h1 sp) w1 h0 /\
  rect_disjoint_2d (table_2x2_col_x 0 w0 w1 sp) (table_2x2_row_y 0 h0 h1 sp) w0 h0
                   (table_2x2_col_x 0 w0 w1 sp) (table_2x2_row_y 1 h0 h1 sp) w0 h1 /\
  rect_disjoint_2d (table_2x2_col_x 1 w0 w1 sp) (table_2x2_row_y 0 h0 h1 sp) w1 h0
                   (table_2x2_col_x 1 w0 w1 sp) (table_2x2_row_y 1 h0 h1 sp) w1 h1 /\
  rect_disjoint_2d (table_2x2_col_x 0 w0 w1 sp) (table_2x2_row_y 1 h0 h1 sp) w0 h1
                   (table_2x2_col_x 1 w0 w1 sp) (table_2x2_row_y 1 h0 h1 sp) w1 h1.
Proof.
  intros vw vh p Hsp out w0 w1 h0 h1 sp.
  repeat split.
  - apply cell_00_and_01_disjoint; assumption.
  - apply cell_00_and_10_disjoint; assumption.
  - apply cell_01_and_11_disjoint; assumption.
  - apply cell_10_and_11_disjoint; assumption.
Qed.

Theorem sample_page_concrete_execution :
  let out := layout_simple_page_pipeline 800 600 sample_page in
  plo_body_width out = 784 /\
  plo_h1_y out = 29 /\
  plo_h1_h out = 38 /\
  plo_h2_y out = 88 /\
  plo_h2_h out = 28 /\
  plo_table_y out = 136 /\
  plo_table_w out = 784 /\
  plo_table_h out = 48 /\
  plo_cell_w0 out = 362 /\
  plo_cell_w1 out = 416 /\
  plo_row_h0 out = 21 /\
  plo_row_h1 out = 21.
Proof.
  vm_compute.
  repeat split; reflexivity.
Qed.
