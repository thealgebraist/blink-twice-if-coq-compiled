(** * BlinkFragmentTreePropagationSemantics.v
    Formal verification of Chromium Blink LayoutNG Physical Fragment Trees
    and Scrollable/Ink Overflow Propagation vs CSS Display 3 and CSS Overflow 3.
*)

From Stdlib Require Import ZArith.ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import micromega.Lia.
Import ListNotations.
Open Scope Z_scope.

(** ** 1. Core Data Structures *)

Definition LayoutUnit := Z.

Record PhysicalOffset : Type := mkOffset {
  offset_x : LayoutUnit;
  offset_y : LayoutUnit
}.

Record PhysicalRect : Type := mkRect {
  rect_x : LayoutUnit;
  rect_y : LayoutUnit;
  rect_w : LayoutUnit;
  rect_h : LayoutUnit
}.

Definition rect_contains (outer inner : PhysicalRect) : Prop :=
  rect_x outer <= rect_x inner /\
  rect_y outer <= rect_y inner /\
  rect_x inner + rect_w inner <= rect_x outer + rect_w outer /\
  rect_y inner + rect_h inner <= rect_y outer + rect_h outer.

Definition rect_translate (r : PhysicalRect) (o : PhysicalOffset) : PhysicalRect :=
  mkRect (rect_x r + offset_x o)
         (rect_y r + offset_y o)
         (rect_w r)
         (rect_h r).

Definition rect_union (r1 r2 : PhysicalRect) : PhysicalRect :=
  let min_x := Z.min (rect_x r1) (rect_x r2) in
  let min_y := Z.min (rect_y r1) (rect_y r2) in
  let max_x := Z.max (rect_x r1 + rect_w r1) (rect_x r2 + rect_w r2) in
  let max_y := Z.max (rect_y r1 + rect_h r1) (rect_y r2 + rect_h r2) in
  mkRect min_x min_y (max_x - min_x) (max_y - min_y).

Record ChildLink : Type := mkLink {
  child_border_box      : PhysicalRect;
  child_scroll_overflow : PhysicalRect;
  child_offset          : PhysicalOffset;
  is_scroll_container   : bool
}.

(** ** 2. Overflow Propagation Functions *)

Definition compute_child_contribution (link : ChildLink) : PhysicalRect :=
  if is_scroll_container link then
    rect_translate (child_border_box link) (child_offset link)
  else
    rect_translate (rect_union (child_border_box link) (child_scroll_overflow link))
                   (child_offset link).

Fixpoint propagate_children_overflow
  (current_overflow : PhysicalRect) (children : list ChildLink) : PhysicalRect :=
  match children with
  | [] => current_overflow
  | c :: rest =>
      let child_contrib := compute_child_contribution c in
      let updated_overflow := rect_union current_overflow child_contrib in
      propagate_children_overflow updated_overflow rest
  end.

Definition compute_parent_scrollable_overflow
  (parent_border_box : PhysicalRect) (children : list ChildLink) : PhysicalRect :=
  propagate_children_overflow parent_border_box children.

(** ** 3. Mathematical Invariants & Verification *)

Lemma rect_contains_refl : forall r,
  rect_contains r r.
Proof.
  intros [x y w h].
  unfold rect_contains. simpl. lia.
Qed.

Lemma rect_contains_trans : forall r1 r2 r3,
  rect_contains r1 r2 ->
  rect_contains r2 r3 ->
  rect_contains r1 r3.
Proof.
  intros [x1 y1 w1 h1] [x2 y2 w2 h2] [x3 y3 w3 h3] H12 H23.
  unfold rect_contains in *. simpl in *. lia.
Qed.

Lemma rect_union_contains_l : forall r1 r2,
  rect_contains (rect_union r1 r2) r1.
Proof.
  intros [x1 y1 w1 h1] [x2 y2 w2 h2].
  unfold rect_contains, rect_union. simpl.
  split; [apply Z.le_min_l |].
  split; [apply Z.le_min_l |].
  split.
  - assert (Hmax : x1 + w1 <= Z.max (x1 + w1) (x2 + w2)) by apply Z.le_max_l.
    assert (Hmin : Z.min x1 x2 <= x1) by apply Z.le_min_l.
    lia.
  - assert (Hmax : y1 + h1 <= Z.max (y1 + h1) (y2 + h2)) by apply Z.le_max_l.
    assert (Hmin : Z.min y1 y2 <= y1) by apply Z.le_min_l.
    lia.
Qed.

Lemma rect_union_contains_r : forall r1 r2,
  rect_contains (rect_union r1 r2) r2.
Proof.
  intros [x1 y1 w1 h1] [x2 y2 w2 h2].
  unfold rect_contains, rect_union. simpl.
  split; [apply Z.le_min_r |].
  split; [apply Z.le_min_r |].
  split.
  - assert (Hmax : x2 + w2 <= Z.max (x1 + w1) (x2 + w2)) by apply Z.le_max_r.
    assert (Hmin : Z.min x1 x2 <= x2) by apply Z.le_min_r.
    lia.
  - assert (Hmax : y2 + h2 <= Z.max (y1 + h1) (y2 + h2)) by apply Z.le_max_r.
    assert (Hmin : Z.min y1 y2 <= y2) by apply Z.le_min_r.
    lia.
Qed.

Theorem rect_union_comm : forall r1 r2,
  rect_union r1 r2 = rect_union r2 r1.
Proof.
  intros [x1 y1 w1 h1] [x2 y2 w2 h2].
  unfold rect_union. simpl.
  rewrite (Z.min_comm x1 x2).
  rewrite (Z.min_comm y1 y2).
  rewrite (Z.max_comm (x1 + w1) (x2 + w2)).
  rewrite (Z.max_comm (y1 + h1) (y2 + h2)).
  reflexivity.
Qed.

Lemma propagate_contains_running : forall children current_overflow,
  rect_contains (propagate_children_overflow current_overflow children) current_overflow.
Proof.
  intros children.
  induction children as [| c rest IH]; intros current_overflow.
  - simpl. apply rect_contains_refl.
  - simpl.
    pose proof (IH (rect_union current_overflow (compute_child_contribution c))) as Hih.
    pose proof (rect_union_contains_l current_overflow (compute_child_contribution c)) as Hunion.
    apply (rect_contains_trans _ _ _ Hih Hunion).
Qed.

(** Invariant 1: Parent scrollable overflow contains its own initial border box *)
Theorem parent_overflow_contains_border_box :
  forall parent_bb children,
    rect_contains (compute_parent_scrollable_overflow parent_bb children) parent_bb.
Proof.
  intros parent_bb children.
  unfold compute_parent_scrollable_overflow.
  apply propagate_contains_running.
Qed.

(** Invariant 2: Parent scrollable overflow contains every child's contribution *)
Theorem parent_overflow_contains_child :
  forall children parent_bb c,
    In c children ->
    rect_contains (compute_parent_scrollable_overflow parent_bb children)
                  (compute_child_contribution c).
Proof.
  intros children.
  induction children as [| c0 rest IH]; intros parent_bb c Hin.
  - simpl in Hin. contradiction.
  - simpl in Hin.
    destruct Hin as [Heq | Hin_rest].
    + subst c0.
      unfold compute_parent_scrollable_overflow.
      simpl.
      pose proof (propagate_contains_running rest (rect_union parent_bb (compute_child_contribution c))) as Hih.
      pose proof (rect_union_contains_r parent_bb (compute_child_contribution c)) as Hright.
      apply (rect_contains_trans _ _ _ Hih Hright).
    + unfold compute_parent_scrollable_overflow.
      simpl.
      apply (IH (rect_union parent_bb (compute_child_contribution c0)) c Hin_rest).
Qed.

