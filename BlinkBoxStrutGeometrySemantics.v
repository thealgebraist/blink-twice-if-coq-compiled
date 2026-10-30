(**
  BlinkBoxStrutGeometrySemantics.v
  Formal specification of Chromium Blink flow-relative box strut and box model algebra
  derived from third_party/blink/renderer/core/layout/geometry/box_strut.h and box_sides.h
  according to W3C CSS Box Model Module Level 3 (§3) & CSS Writing Modes Level 3 (§4).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Record BoxStrut := {
  inline_start : Z;
  inline_end : Z;
  block_start : Z;
  block_end : Z
}.

Record LogicalSize := {
  inline_size : Z;
  block_size : Z
}.

Definition strut_inline_sum (s : BoxStrut) : Z :=
  s.(inline_start) + s.(inline_end).

Definition strut_block_sum (s : BoxStrut) : Z :=
  s.(block_start) + s.(block_end).

Definition add_struts (s1 s2 : BoxStrut) : BoxStrut := {|
  inline_start := s1.(inline_start) + s2.(inline_start);
  inline_end := s1.(inline_end) + s2.(inline_end);
  block_start := s1.(block_start) + s2.(block_start);
  block_end := s1.(block_end) + s2.(block_end)
|}.

Definition expand_size (sz : LogicalSize) (s : BoxStrut) : LogicalSize := {|
  inline_size := sz.(inline_size) + strut_inline_sum s;
  block_size := sz.(block_size) + strut_block_sum s
|}.

(** 1. Box Strut Monoid Properties *)

Theorem add_struts_comm :
  forall s1 s2 : BoxStrut,
    add_struts s1 s2 = add_struts s2 s1.
Proof.
  intros [is1 ie1 bs1 be1] [is2 ie2 bs2 be2].
  unfold add_struts.
  simpl.
  f_equal; lia.
Qed.

Theorem add_struts_assoc :
  forall s1 s2 s3 : BoxStrut,
    add_struts (add_struts s1 s2) s3 = add_struts s1 (add_struts s2 s3).
Proof.
  intros [is1 ie1 bs1 be1] [is2 ie2 bs2 be2] [is3 ie3 bs3 be3].
  unfold add_struts.
  simpl.
  f_equal; lia.
Qed.

(** 2. Concentric Box Model Expansion Associativity *)

Theorem expand_size_composition :
  forall (sz : LogicalSize) (s1 s2 : BoxStrut),
    expand_size (expand_size sz s1) s2 = expand_size sz (add_struts s1 s2).
Proof.
  intros [i b] s1 s2.
  unfold expand_size, add_struts, strut_inline_sum, strut_block_sum.
  simpl.
  f_equal; lia.
Qed.

(** 3. Non-negativity Preservation *)

Theorem size_expansion_monotonic :
  forall (sz : LogicalSize) (s : BoxStrut),
    0 <= s.(inline_start) ->
    0 <= s.(inline_end) ->
    0 <= s.(block_start) ->
    0 <= s.(block_end) ->
    sz.(inline_size) <= (expand_size sz s).(inline_size) /\
    sz.(block_size) <= (expand_size sz s).(block_size).
Proof.
  intros sz s His Hie Hbs Hbe.
  unfold expand_size, strut_inline_sum, strut_block_sum.
  simpl.
  split; lia.
Qed.

(** 4. Physical to Logical Perimeter Conservation *)

Record PhysicalBoxStrut := {
  phys_top : Z;
  phys_right : Z;
  phys_bottom : Z;
  phys_left : Z
}.

Definition transpose_htb_ltr (p : PhysicalBoxStrut) : BoxStrut := {|
  inline_start := p.(phys_left);
  inline_end := p.(phys_right);
  block_start := p.(phys_top);
  block_end := p.(phys_bottom)
|}.

Definition transpose_vrl_ltr (p : PhysicalBoxStrut) : BoxStrut := {|
  inline_start := p.(phys_top);
  inline_end := p.(phys_bottom);
  block_start := p.(phys_right);
  block_end := p.(phys_left)
|}.

Theorem htb_perimeter_conserved :
  forall p : PhysicalBoxStrut,
    let s := transpose_htb_ltr p in
    s.(inline_start) + s.(inline_end) + s.(block_start) + s.(block_end) =
    p.(phys_top) + p.(phys_right) + p.(phys_bottom) + p.(phys_left).
Proof.
  intros p s.
  unfold s, transpose_htb_ltr.
  simpl. lia.
Qed.

Theorem vrl_perimeter_conserved :
  forall p : PhysicalBoxStrut,
    let s := transpose_vrl_ltr p in
    s.(inline_start) + s.(inline_end) + s.(block_start) + s.(block_end) =
    p.(phys_top) + p.(phys_right) + p.(phys_bottom) + p.(phys_left).
Proof.
  intros p s.
  unfold s, transpose_vrl_ltr.
  simpl. lia.
Qed.

