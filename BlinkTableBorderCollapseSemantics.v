(* =========================================================================
   BlinkTableBorderCollapseSemantics.v
   Formalization of Chromium Blink Collapsed Table Border Conflict Resolution
   Source: third_party/blink/renderer/core/layout/table/table_borders.cc
   Specification: W3C CSS 2.1 §17.6.2 The Border-Conflict Resolution Algorithm
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Arith.Arith.
From Coq Require Import Lia.
Open Scope Z_scope.

Inductive TableBorderStyle : Type :=
  | BorderHidden
  | BorderDouble
  | BorderSolid
  | BorderDashed
  | BorderDotted
  | BorderRidge
  | BorderOutset
  | BorderGroove
  | BorderInset
  | BorderNone.

Definition style_priority (s : TableBorderStyle) : Z :=
  match s with
  | BorderDouble => 8
  | BorderSolid => 7
  | BorderDashed => 6
  | BorderDotted => 5
  | BorderRidge => 4
  | BorderOutset => 3
  | BorderGroove => 2
  | BorderInset => 1
  | BorderNone => 0
  | BorderHidden => 0 (* Handled before style priority *)
  end.

Record TableBorderEdge : Type := mkTableBorderEdge {
  tbe_style : TableBorderStyle;
  tbe_width : Z;
  tbe_box_order : nat
}.

Definition resolve_border_conflict (a b : TableBorderEdge) : TableBorderEdge :=
  match a.(tbe_style), b.(tbe_style) with
  | BorderHidden, _ => mkTableBorderEdge BorderHidden 0 a.(tbe_box_order)
  | _, BorderHidden => mkTableBorderEdge BorderHidden 0 b.(tbe_box_order)
  | BorderNone, _ => b
  | _, BorderNone => a
  | _, _ =>
      if a.(tbe_width) >? b.(tbe_width) then a
      else if a.(tbe_width) <? b.(tbe_width) then b
      else
        let pa := style_priority a.(tbe_style) in
        let pb := style_priority b.(tbe_style) in
        if pa >? pb then a
        else if pa <? pb then b
        else
          if (a.(tbe_box_order) <=? b.(tbe_box_order))%nat then a else b
  end.

Definition distribute_border_halves (w : Z) : Z * Z :=
  let h1 := w / 2 in
  let h2 := w - h1 in
  (h1, h2).

Theorem half_width_sum_conservation :
  forall w,
    let (h1, h2) := distribute_border_halves w in
    h1 + h2 = w.
Proof.
  intros w.
  unfold distribute_border_halves.
  lia.
Qed.

Theorem hidden_border_dominates_left :
  forall b bo,
    resolve_border_conflict (mkTableBorderEdge BorderHidden 10 bo) b =
    mkTableBorderEdge BorderHidden 0 bo.
Proof.
  intros b bo.
  unfold resolve_border_conflict.
  destruct (tbe_style b); reflexivity.
Qed.

Theorem hidden_border_dominates_right :
  forall a bo,
    a.(tbe_style) <> BorderHidden ->
    resolve_border_conflict a (mkTableBorderEdge BorderHidden 10 bo) =
    mkTableBorderEdge BorderHidden 0 bo.
Proof.
  intros a bo Hnot.
  unfold resolve_border_conflict.
  destruct (tbe_style a); try reflexivity.
  contradiction Hnot. reflexivity.
Qed.

Theorem resolve_border_conflict_deterministic :
  forall a b r1 r2,
    r1 = resolve_border_conflict a b ->
    r2 = resolve_border_conflict a b ->
    r1 = r2.
Proof.
  intros a b r1 r2 H1 H2.
  subst. reflexivity.
Qed.

Theorem resolve_border_conflict_width_nonneg :
  forall a b,
    0 <= a.(tbe_width) ->
    0 <= b.(tbe_width) ->
    0 <= (resolve_border_conflict a b).(tbe_width).
Proof.
  intros a b Ha Hb.
  unfold resolve_border_conflict.
  destruct (tbe_style a) eqn:Ea; destruct (tbe_style b) eqn:Eb; simpl;
    try lia;
    try (destruct (tbe_width a >? tbe_width b); simpl; [lia |]);
    try (destruct (tbe_width a <? tbe_width b); simpl; [lia |]);
    try (destruct (style_priority (tbe_style a) >? style_priority (tbe_style b)); simpl; [lia |]);
    try (destruct (style_priority (tbe_style a) <? style_priority (tbe_style b)); simpl; [lia |]);
    try (destruct (tbe_box_order a <=? tbe_box_order b)%nat; simpl; lia).
Qed.

