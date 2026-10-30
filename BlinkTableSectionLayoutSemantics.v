(* =========================================================================
   BlinkTableSectionLayoutSemantics.v
   Formalization of Chromium Blink Table Section Ordering & Cumulative Offsets
   Source: third_party/blink/renderer/core/layout/table/table_section_layout_algorithm.cc
   Specification: W3C CSS 2.1 §17.5 Table Section Ordering (thead, tbody, tfoot)
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

Inductive TableSectionRole : Type :=
  | SectionHeader
  | SectionBody
  | SectionFooter.

Definition section_visual_rank (role : TableSectionRole) : Z :=
  match role with
  | SectionHeader => 0
  | SectionBody => 1
  | SectionFooter => 2
  end.

Definition advance_section_offset
    (prev_offset : Z) (prev_height : Z) (v_spacing : Z) : Z :=
  prev_offset + prev_height + v_spacing.

Theorem visual_rank_header_before_body :
  section_visual_rank SectionHeader < section_visual_rank SectionBody.
Proof.
  unfold section_visual_rank. lia.
Qed.

Theorem visual_rank_body_before_footer :
  section_visual_rank SectionBody < section_visual_rank SectionFooter.
Proof.
  unfold section_visual_rank. lia.
Qed.

Theorem visual_rank_header_before_footer :
  section_visual_rank SectionHeader < section_visual_rank SectionFooter.
Proof.
  unfold section_visual_rank. lia.
Qed.

Theorem advance_section_offset_monotonic :
  forall prev_offset prev_height v_spacing,
    0 <= prev_height ->
    0 <= v_spacing ->
    prev_offset <= advance_section_offset prev_offset prev_height v_spacing.
Proof.
  intros prev_offset prev_height v_spacing Hh Hv.
  unfold advance_section_offset.
  lia.
Qed.

Theorem advance_section_offset_strictly_monotonic :
  forall prev_offset prev_height v_spacing,
    0 < prev_height + v_spacing ->
    prev_offset < advance_section_offset prev_offset prev_height v_spacing.
Proof.
  intros prev_offset prev_height v_spacing Hsum.
  unfold advance_section_offset.
  lia.
Qed.

Theorem advance_section_offset_deterministic :
  forall po ph vs o1 o2,
    o1 = advance_section_offset po ph vs ->
    o2 = advance_section_offset po ph vs ->
    o1 = o2.
Proof.
  intros po ph vs o1 o2 H1 H2.
  subst. reflexivity.
Qed.

