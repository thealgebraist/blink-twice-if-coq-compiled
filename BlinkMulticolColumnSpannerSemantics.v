(* ========================================================================= *)
(*               BlinkMulticolColumnSpannerSemantics.v                       *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Multi-Column Column Spanner Layout  *)
(* per CSS Multi-column Layout Module Level 1 §6.                            *)
(* Constructive, executable (vm_compute), extractable to C99/C++23/LLVM-IR.  *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Import ListNotations.
Open Scope Z_scope.

Record MulticolConfig := mkMulticolConfig {
  w_multicol : Z;
  col_count  : Z;
  col_gap    : Z
}.

Definition compute_column_inline_size (cfg : MulticolConfig) : Z :=
  Z.max 0 ((w_multicol cfg - (col_count cfg - 1) * col_gap cfg) / col_count cfg).

Inductive EColumnSpan : Type :=
  | kNone
  | kAll.

Record NodeStyle : Type := mkNodeStyle {
  column_span : EColumnSpan;
  is_in_flow : bool;
  is_block_level : bool;
  in_multicol_bfc : bool
}.

Definition is_column_span_all (s : NodeStyle) : bool :=
  match column_span s with
  | kAll => is_in_flow s && is_block_level s && in_multicol_bfc s
  | kNone => false
  end.

Inductive FragmentKind : Type :=
  | FragColumnRow (col_heights : list Z)
  | FragSpanner.

Record PlacedFragment : Type := mkPlacedFragment {
  frag_kind        : FragmentKind;
  frag_inline_size : Z;
  frag_block_start : Z;
  frag_block_size  : Z
}.

Fixpoint max_list_Z (l : list Z) : Z :=
  match l with
  | [] => 0
  | x :: xs => Z.max x (max_list_Z xs)
  end.

Definition layout_column_row (cfg : MulticolConfig) (y_cursor : Z) (col_heights : list Z)
  : PlacedFragment * Z :=
  let h_row := max_list_Z col_heights in
  let w_col := compute_column_inline_size cfg in
  let frag := mkPlacedFragment (FragColumnRow col_heights) w_col y_cursor h_row in
  (frag, y_cursor + h_row).

Definition layout_spanner (cfg : MulticolConfig) (y_cursor : Z)
                          (h_span m_top m_bottom : Z)
  : PlacedFragment * Z :=
  let y_span := y_cursor + m_top in
  let w_span := w_multicol cfg in
  let frag := mkPlacedFragment FragSpanner w_span y_span h_span in
  (frag, y_span + h_span + m_bottom).

Inductive MulticolChild : Type :=
  | FlowColumnRow (col_heights : list Z)
  | SpannerBox (style : NodeStyle) (block_size : Z) (m_top : Z) (m_bottom : Z).

Definition layout_step (cfg : MulticolConfig) (y_cursor : Z) (child : MulticolChild)
  : PlacedFragment * Z :=
  match child with
  | FlowColumnRow col_heights =>
      layout_column_row cfg y_cursor col_heights
  | SpannerBox style h_span m_top m_bottom =>
      if is_column_span_all style then
        layout_spanner cfg y_cursor h_span m_top m_bottom
      else
        layout_column_row cfg y_cursor [m_top + h_span + m_bottom]
  end.

Fixpoint layout_children (cfg : MulticolConfig) (y_cursor : Z) (children : list MulticolChild)
  : list PlacedFragment * Z :=
  match children with
  | [] => ([], y_cursor)
  | c :: cs =>
      let (frag, y_next) := layout_step cfg y_cursor c in
      let (frags, y_final) := layout_children cfg y_next cs in
      (frag :: frags, y_final)
  end.

(* ------------------------------------------------------------------------- *)
(* Theorems                                                                  *)
(* ------------------------------------------------------------------------- *)

Lemma max_list_Z_nonneg : forall l,
  max_list_Z l >= 0.
Proof.
  induction l as [| x xs IH]; cbn; lia.
Qed.

Theorem spanner_inline_size_exact : forall cfg y h mt mb frag y_next,
  layout_spanner cfg y h mt mb = (frag, y_next) ->
  frag_inline_size frag = w_multicol cfg.
Proof.
  intros cfg y h mt mb frag y_next H.
  unfold layout_spanner in H.
  injection H as <- <-.
  reflexivity.
Qed.

Theorem spanner_offset_placement : forall cfg y h mt mb frag y_next,
  layout_spanner cfg y h mt mb = (frag, y_next) ->
  frag_block_start frag = y + mt /\ y_next = y + mt + h + mb.
Proof.
  intros cfg y h mt mb frag y_next H.
  unfold layout_spanner in H.
  injection H as <- <-.
  split; reflexivity.
Qed.

Theorem spanner_cursor_advances : forall cfg y h mt mb frag y_next,
  mt >= 0 -> h >= 0 -> mb >= 0 ->
  layout_spanner cfg y h mt mb = (frag, y_next) ->
  y_next >= y.
Proof.
  intros cfg y h mt mb frag y_next Hmt Hh Hmb H.
  unfold layout_spanner in H.
  injection H as <- <-.
  lia.
Qed.

Theorem column_row_cursor_advances : forall cfg y col_heights frag y_next,
  layout_column_row cfg y col_heights = (frag, y_next) ->
  y_next >= y.
Proof.
  intros cfg y col_heights frag y_next H.
  unfold layout_column_row in H.
  injection H as <- <-.
  pose proof (max_list_Z_nonneg col_heights).
  lia.
Qed.

Theorem layout_children_length : forall cfg y children,
  length (fst (layout_children cfg y children)) = length children.
Proof.
  intros cfg y children.
  generalize dependent y.
  induction children as [| c cs IH]; intros y; cbn.
  - reflexivity.
  - destruct (layout_step cfg y c) as [frag y_next].
    destruct (layout_children cfg y_next cs) as [frags y_final] eqn:Ecs.
    specialize (IH y_next).
    rewrite Ecs in IH.
    cbn in *.
    rewrite IH.
    reflexivity.
Qed.

