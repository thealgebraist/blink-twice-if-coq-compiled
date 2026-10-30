From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §17.4 Table Caption Formatting Boundary *)
Record TableWrapperLayout := {
  tw_caption_margin_top : Z;
  tw_caption_height : Z;
  tw_caption_margin_bottom : Z;
  tw_grid_border_padding_top : Z;
  tw_grid_height : Z;
  tw_grid_border_padding_bottom : Z
}.

Definition caption_margin_box (tw : TableWrapperLayout) : Z :=
  tw_caption_margin_top tw + tw_caption_height tw + tw_caption_margin_bottom tw.

Definition grid_margin_box (tw : TableWrapperLayout) : Z :=
  tw_grid_border_padding_top tw + tw_grid_height tw + tw_grid_border_padding_bottom tw.

Definition total_table_wrapper_height (tw : TableWrapperLayout) : Z :=
  caption_margin_box tw + grid_margin_box tw.

Theorem caption_margin_does_not_collapse_with_grid : forall tw,
  tw_caption_margin_top tw >= 0 ->
  tw_caption_height tw >= 0 ->
  tw_caption_margin_bottom tw >= 0 ->
  tw_grid_border_padding_top tw >= 0 ->
  tw_grid_height tw >= 0 ->
  tw_grid_border_padding_bottom tw >= 0 ->
  total_table_wrapper_height tw >= caption_margin_box tw /\
  total_table_wrapper_height tw >= grid_margin_box tw.
Proof.
  intros tw H1 H2 H3 H4 H5 H6.
  unfold total_table_wrapper_height, caption_margin_box, grid_margin_box.
  destruct tw; cbn in *.
  lia.
Qed.
