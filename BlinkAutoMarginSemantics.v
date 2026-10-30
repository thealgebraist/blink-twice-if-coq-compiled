(** * BlinkAutoMarginSemantics.v
    Formal Verification of Chromium Blink LayoutNG Auto Margin Resolution
    against CSS 2.1 §10.3.3 and §10.6.4.
*)

From Stdlib Require Import ZArith.ZArith.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import micromega.Lia.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

Definition LayoutUnit := Z.

Inductive EBoxSizing : Type :=
  | kContentBox
  | kBorderBox.

Inductive MarginSpec : Type :=
  | MarginAuto
  | MarginFixed (val : LayoutUnit).

Inductive TextDirection : Type :=
  | LTR
  | RTL.

Record NGBoxStrut : Type := mkNGBoxStrut {
  inline_start : LayoutUnit;
  inline_end   : LayoutUnit;
  block_start  : LayoutUnit;
  block_end    : LayoutUnit
}.

Definition InlineSum (s : NGBoxStrut) : LayoutUnit :=
  inline_start s + inline_end s.

Definition BlockSum (s : NGBoxStrut) : LayoutUnit :=
  block_start s + block_end s.

Definition ResolveBorderBoxInlineSize
  (sizing : EBoxSizing)
  (specified_width : LayoutUnit)
  (border_padding : NGBoxStrut) : LayoutUnit :=
  let bp_sum := InlineSum border_padding in
  match sizing with
  | kContentBox => specified_width + bp_sum
  | kBorderBox  => Z.max specified_width bp_sum
  end.

Definition ProvisionalMargin (m : MarginSpec) : LayoutUnit :=
  match m with
  | MarginAuto => 0
  | MarginFixed v => v
  end.

(** ** 2. Inline and Block Auto Margin Resolution *)

Definition ResolveInlineMarginsLogical
  (available_inline_size : LayoutUnit)
  (child_inline_size : LayoutUnit)
  (m_start_spec m_end_spec : MarginSpec) : (LayoutUnit * LayoutUnit) :=
  let m_start_prov := ProvisionalMargin m_start_spec in
  let m_end_prov   := ProvisionalMargin m_end_spec in
  let delta := available_inline_size - (child_inline_size + m_start_prov + m_end_prov) in
  match m_start_spec, m_end_spec with
  | MarginAuto, MarginAuto =>
      if delta >=? 0 then
        let start_val := delta / 2 in
        let end_val := delta - start_val in
        (start_val, end_val)
      else
        (0, delta)
  | MarginAuto, MarginFixed v_end =>
      (delta, v_end)
  | MarginFixed v_start, MarginAuto =>
      (v_start, delta)
  | MarginFixed v_start, MarginFixed v_end =>
      (v_start, v_end + delta)
  end.

Definition ResolveBlockMarginsOOF
  (avail_block : LayoutUnit)
  (child_block_size : LayoutUnit)
  (top_inset bottom_inset : LayoutUnit)
  (m_top_spec m_bottom_spec : MarginSpec) : (LayoutUnit * LayoutUnit) :=
  let m_top_prov := ProvisionalMargin m_top_spec in
  let m_bottom_prov := ProvisionalMargin m_bottom_spec in
  let delta := avail_block - (top_inset + bottom_inset + child_block_size + m_top_prov + m_bottom_prov) in
  match m_top_spec, m_bottom_spec with
  | MarginAuto, MarginAuto =>
      let top_val := delta / 2 in
      let bottom_val := delta - top_val in
      (top_val, bottom_val)
  | MarginAuto, MarginFixed v_bottom =>
      (delta, v_bottom)
  | MarginFixed v_top, MarginAuto =>
      (v_top, delta)
  | MarginFixed v_top, MarginFixed v_bottom =>
      (v_top, v_bottom + delta)
  end.

(** ** 3. Mathematical Invariants & Verification *)

(** Invariant 1: Inline Space Conservation Across All Constraint Modes *)
Theorem inline_margins_space_conservation :
  forall avail child_w m_start_spec m_end_spec,
    let '(m_start, m_end) :=
      ResolveInlineMarginsLogical avail child_w m_start_spec m_end_spec in
    m_start + child_w + m_end = avail.
Proof.
  intros avail child_w m_start_spec m_end_spec.
  unfold ResolveInlineMarginsLogical.
  destruct m_start_spec as [| v_start]; destruct m_end_spec as [| v_end]; simpl;
  try destruct (_ >=? 0); lia.
Qed.

(** Invariant 2: Bounded Centering Symmetry Under Non-Negative Free Space *)
Theorem inline_margins_centering_bounds :
  forall avail child_w,
    let delta := avail - child_w in
    delta >= 0 ->
    let '(m_start, m_end) :=
      ResolveInlineMarginsLogical avail child_w MarginAuto MarginAuto in
    0 <= m_end - m_start <= 1.
Proof.
  intros avail child_w delta Hdelta.
  unfold ResolveInlineMarginsLogical.
  simpl.
  assert (Hgeb : (avail - (child_w + 0 + 0) >=? 0) = true).
  { apply Z.geb_le. lia. }
  rewrite Hgeb.
  set (d := avail - (child_w + 0 + 0)).
  assert (Hdiv : d - 2 * (d / 2) = d mod 2).
  { rewrite Z.mul_comm.
    pose proof (Z.div_mod d 2 (ltac:(lia))) as Hdm.
    lia. }
  pose proof (Z.mod_pos_bound d 2 (ltac:(lia))) as Hmod.
  lia.
Qed.

(** Invariant 3: OOF Block Margin Space Conservation *)
Theorem oof_block_margins_space_conservation :
  forall avail_block child_h top_inset bottom_inset m_top_spec m_bottom_spec,
    let '(m_top, m_bottom) :=
      ResolveBlockMarginsOOF avail_block child_h top_inset bottom_inset m_top_spec m_bottom_spec in
    top_inset + m_top + child_h + m_bottom + bottom_inset = avail_block.
Proof.
  intros avail_block child_h top_inset bottom_inset m_top_spec m_bottom_spec.
  unfold ResolveBlockMarginsOOF.
  destruct m_top_spec as [| v_top]; destruct m_bottom_spec as [| v_bottom]; simpl; lia.
Qed.
