(* =========================================================================
   BlinkRubyLayoutSemantics.v
   Formalization of Chromium Blink Ruby Annotation Layout & Column Sizing
   Source: third_party/blink/renderer/core/layout/inline/ruby_layout_algorithm.cc
           third_party/blink/renderer/core/layout/inline/ruby_utils.cc
   Specification: W3C CSS Ruby Layout Module Level 1 §3 & §4
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

Inductive RubyPosition : Type :=
  | RubyOver
  | RubyUnder.

Record RubyColumnMetrics : Type := mkRubyColumnMetrics {
  rcm_base_inline_size : Z;
  rcm_annotation_inline_size : Z;
  rcm_position : RubyPosition
}.

Definition resolve_ruby_column_width (base_w : Z) (anno_w : Z) : Z :=
  Z.max base_w anno_w.

Definition compute_ruby_center_offset (col_w : Z) (child_w : Z) : Z :=
  (Z.max 0 (col_w - child_w)) / 2.

Theorem ruby_column_bounds_base :
  forall base_w anno_w,
    base_w <= resolve_ruby_column_width base_w anno_w.
Proof.
  intros base_w anno_w.
  unfold resolve_ruby_column_width.
  lia.
Qed.

Theorem ruby_column_bounds_annotation :
  forall base_w anno_w,
    anno_w <= resolve_ruby_column_width base_w anno_w.
Proof.
  intros base_w anno_w.
  unfold resolve_ruby_column_width.
  lia.
Qed.

Theorem ruby_column_width_nonneg :
  forall base_w anno_w,
    0 <= base_w ->
    0 <= anno_w ->
    0 <= resolve_ruby_column_width base_w anno_w.
Proof.
  intros base_w anno_w Hb Ha.
  unfold resolve_ruby_column_width.
  lia.
Qed.

Theorem ruby_center_offset_contained :
  forall col_w child_w,
    0 <= child_w ->
    child_w <= col_w ->
    compute_ruby_center_offset col_w child_w + child_w <= col_w.
Proof.
  intros col_w child_w Hpos Hle.
  unfold compute_ruby_center_offset.
  assert (Hmax : Z.max 0 (col_w - child_w) = col_w - child_w) by (apply Z.max_r; lia).
  rewrite Hmax.
  assert (Hdiv : (col_w - child_w) / 2 <= col_w - child_w).
  { apply Z.div_le_upper_bound; lia. }
  lia.
Qed.

Theorem resolve_ruby_column_width_deterministic :
  forall bw aw w1 w2,
    w1 = resolve_ruby_column_width bw aw ->
    w2 = resolve_ruby_column_width bw aw ->
    w1 = w2.
Proof.
  intros bw aw w1 w2 H1 H2.
  subst. reflexivity.
Qed.

