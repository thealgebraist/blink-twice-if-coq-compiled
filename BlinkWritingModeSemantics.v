(******************************************************************************)
(* BlinkWritingModeSemantics.v                                               *)
(* Sound Formal Specification for CSS Writing Modes & Logical Coordinate      *)
(* Transformations (W3C CSS Writing Modes Level 3 & Blink WritingModeConverter*)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Open Scope Z_scope.

Inductive WritingMode : Type :=
  | HorizontalTb
  | VerticalRl
  | VerticalLr
  | SidewaysRl
  | SidewaysLr.

Inductive TextDirection : Type :=
  | Ltr
  | Rtl.

Record LogicalOffset := mkLogicalOffset {
  log_inline : Z;
  log_block : Z
}.

Record PhysicalOffset := mkPhysicalOffset {
  phys_x : Z;
  phys_y : Z
}.

Record LogicalSize := mkLogicalSize {
  ls_inline : Z;
  ls_block : Z
}.

Record PhysicalSize := mkPhysicalSize {
  ps_w : Z;
  ps_h : Z
}.

(** Maps Logical Coordinates to Physical Coordinates based on container size *)
Definition logical_to_physical_offset (wm : WritingMode) (dir : TextDirection)
                                      (outer_size : PhysicalSize) (inner_size : PhysicalSize)
                                      (offset : LogicalOffset) : PhysicalOffset :=
  let ow := ps_w outer_size in
  let oh := ps_h outer_size in
  let iw := ps_w inner_size in
  let ih := ps_h inner_size in
  let i := log_inline offset in
  let b := log_block offset in
  match wm with
  | HorizontalTb =>
      match dir with
      | Ltr => mkPhysicalOffset i b
      | Rtl => mkPhysicalOffset (ow - i - iw) b
      end
  | VerticalRl =>
      match dir with
      | Ltr => mkPhysicalOffset (ow - b - iw) i
      | Rtl => mkPhysicalOffset (ow - b - iw) (oh - i - ih)
      end
  | VerticalLr =>
      match dir with
      | Ltr => mkPhysicalOffset b i
      | Rtl => mkPhysicalOffset b (oh - i - ih)
      end
  | SidewaysRl =>
      match dir with
      | Ltr => mkPhysicalOffset (ow - b - iw) i
      | Rtl => mkPhysicalOffset (ow - b - iw) (oh - i - ih)
      end
  | SidewaysLr =>
      match dir with
      | Ltr => mkPhysicalOffset b (oh - i - ih)
      | Rtl => mkPhysicalOffset b i
      end
  end.

(** Maps Physical Coordinates back to Logical Coordinates *)
Definition physical_to_logical_offset (wm : WritingMode) (dir : TextDirection)
                                      (outer_size : PhysicalSize) (inner_size : PhysicalSize)
                                      (offset : PhysicalOffset) : LogicalOffset :=
  let ow := ps_w outer_size in
  let oh := ps_h outer_size in
  let iw := ps_w inner_size in
  let ih := ps_h inner_size in
  let x := phys_x offset in
  let y := phys_y offset in
  match wm with
  | HorizontalTb =>
      match dir with
      | Ltr => mkLogicalOffset x y
      | Rtl => mkLogicalOffset (ow - x - iw) y
      end
  | VerticalRl =>
      match dir with
      | Ltr => mkLogicalOffset y (ow - x - iw)
      | Rtl => mkLogicalOffset (oh - y - ih) (ow - x - iw)
      end
  | VerticalLr =>
      match dir with
      | Ltr => mkLogicalOffset y x
      | Rtl => mkLogicalOffset (oh - y - ih) x
      end
  | SidewaysRl =>
      match dir with
      | Ltr => mkLogicalOffset y (ow - x - iw)
      | Rtl => mkLogicalOffset (oh - y - ih) (ow - x - iw)
      end
  | SidewaysLr =>
      match dir with
      | Ltr => mkLogicalOffset (oh - y - ih) x
      | Rtl => mkLogicalOffset y x
      end
  end.

(******************************************************************************)
(* SOUNDNESS & BIJECTION THEOREMS (0 admits)                                  *)
(******************************************************************************)

(** Theorem 1: Involution / Bijection Property
    For all writing modes and text directions, physical_to_logical(logical_to_physical(L)) == L *)
Theorem writing_mode_offset_involution :
  forall wm dir outer inner l_off,
    physical_to_logical_offset wm dir outer inner
      (logical_to_physical_offset wm dir outer inner l_off) = l_off.
Proof.
  intros wm dir outer inner [i b].
  unfold logical_to_physical_offset, physical_to_logical_offset. simpl.
  destruct wm; destruct dir; simpl;
  repeat (f_equal; lia).
Qed.

Theorem logical_to_physical_deterministic :
  forall wm dir outer inner l_off r1 r2,
    r1 = logical_to_physical_offset wm dir outer inner l_off ->
    r2 = logical_to_physical_offset wm dir outer inner l_off ->
    r1 = r2.
Proof.
  intros wm dir outer inner l_off r1 r2 H1 H2.
  subst. reflexivity.
Qed.
