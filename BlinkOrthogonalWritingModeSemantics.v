(** * BlinkOrthogonalWritingModeSemantics.v
    Formal Audit of Chromium Blink Orthogonal Writing Modes vs CSS Writing Modes Level 3 §7.
*)

From Stdlib Require Import Arith.PeanoNat.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import micromega.Lia.

(** ** 1. Core Data Structures *)

Inductive WritingMode : Type :=
  | HorizontalTB
  | VerticalRL
  | VerticalLR
  | SidewaysRL
  | SidewaysLR.

Inductive Axis : Type :=
  | HorizontalAxis
  | VerticalAxis.

Definition block_flow_axis (wm : WritingMode) : Axis :=
  match wm with
  | HorizontalTB => VerticalAxis
  | VerticalRL | VerticalLR | SidewaysRL | SidewaysLR => HorizontalAxis
  end.

Definition inline_base_axis (wm : WritingMode) : Axis :=
  match wm with
  | HorizontalTB => HorizontalAxis
  | VerticalRL | VerticalLR | SidewaysRL | SidewaysLR => VerticalAxis
  end.

Definition is_orthogonal (parent_wm child_wm : WritingMode) : bool :=
  match block_flow_axis parent_wm, block_flow_axis child_wm with
  | HorizontalAxis, VerticalAxis => true
  | VerticalAxis, HorizontalAxis => true
  | _, _ => false
  end.

Inductive MaybeSize : Type :=
  | Definite (n : nat)
  | Indefinite.

Record LogicalSize : Type := mkLogicalSize {
  inline_size : nat;
  block_size  : nat
}.

Record AvailableLogicalSize : Type := mkAvailSize {
  avail_inline : nat;
  avail_block  : MaybeSize
}.

Record MinMaxSizes : Type := mkMinMax {
  min_content : nat;
  max_content : nat
}.

Record ConstraintSpace : Type := mkConstraintSpace {
  cs_writing_mode  : WritingMode;
  cs_avail_size    : AvailableLogicalSize;
  cs_is_orthogonal : bool
}.

Record ICBSize : Type := mkICB {
  icb_width  : nat;
  icb_height : nat
}.

Definition icb_inline_fallback (wm : WritingMode) (icb : ICBSize) : nat :=
  match inline_base_axis wm with
  | HorizontalAxis => icb_width icb
  | VerticalAxis   => icb_height icb
  end.

(** ** 2. Sizing Transformations *)

Definition transpose_size (s : LogicalSize) : LogicalSize :=
  mkLogicalSize (block_size s) (inline_size s).

Definition resolve_with_fallback (ms : MaybeSize) (fallback : nat) : nat :=
  match ms with
  | Definite n => n
  | Indefinite => fallback
  end.

Definition build_child_constraint_space
  (parent_cs : ConstraintSpace) (child_wm : WritingMode) (icb : ICBSize) : ConstraintSpace :=
  if is_orthogonal (cs_writing_mode parent_cs) child_wm then
    let inline_val := resolve_with_fallback (avail_block (cs_avail_size parent_cs))
                                            (icb_inline_fallback child_wm icb) in
    let block_val := Definite (avail_inline (cs_avail_size parent_cs)) in
    mkConstraintSpace child_wm (mkAvailSize inline_val block_val) true
  else
    mkConstraintSpace child_wm (cs_avail_size parent_cs) false.

Definition resolve_fit_content (mm : MinMaxSizes) (avail : nat) : nat :=
  Nat.min (max_content mm) (Nat.max (min_content mm) avail).

Definition child_to_parent_fragment_size (child_size : LogicalSize) : LogicalSize :=
  transpose_size child_size.

(** ** 3. Mathematical Invariants & Verification *)

(** Invariant 1: Involution of Logical Transposition — T(T(s)) = s *)
Theorem transpose_involution : forall s,
  transpose_size (transpose_size s) = s.
Proof.
  intros [i b].
  unfold transpose_size.
  simpl. reflexivity.
Qed.

(** Invariant 2: Orthogonality Symmetry *)
Theorem is_orthogonal_sym : forall w1 w2,
  is_orthogonal w1 w2 = is_orthogonal w2 w1.
Proof.
  intros w1 w2.
  unfold is_orthogonal.
  destruct (block_flow_axis w1); destruct (block_flow_axis w2); reflexivity.
Qed.

(** Invariant 3: Orthogonality Anti-Reflexivity *)
Theorem is_orthogonal_irrefl : forall w,
  is_orthogonal w w = false.
Proof.
  intros w.
  unfold is_orthogonal.
  destruct (block_flow_axis w); reflexivity.
Qed.

(** Invariant 4: Parallelism of Double Orthogonality (w1 ⊥ w2 ∧ w2 ⊥ w3 => w1 ∥ w3) *)
Theorem orthogonal_transitivity_parallel : forall w1 w2 w3,
  is_orthogonal w1 w2 = true ->
  is_orthogonal w2 w3 = true ->
  block_flow_axis w1 = block_flow_axis w3.
Proof.
  intros w1 w2 w3 H12 H23.
  unfold is_orthogonal in *.
  destruct (block_flow_axis w1); destruct (block_flow_axis w2); destruct (block_flow_axis w3);
  try discriminate; reflexivity.
Qed.

(** Invariant 5: Child inline constraint is always definite *)
Theorem child_inline_space_definite : forall parent_cs child_wm icb,
  exists d : nat, avail_inline (cs_avail_size (build_child_constraint_space parent_cs child_wm icb)) = d.
Proof.
  intros parent_cs child_wm icb.
  unfold build_child_constraint_space.
  destruct (is_orthogonal (cs_writing_mode parent_cs) child_wm).
  - simpl. eexists. reflexivity.
  - simpl. eexists. reflexivity.
Qed.

(** Invariant 6: Fit-content inline size is bounded between min_content and max_content *)
Theorem fit_content_bounded : forall mm avail,
  min_content mm <= max_content mm ->
  min_content mm <= resolve_fit_content mm avail <= max_content mm.
Proof.
  intros [min_c max_c] avail Hle.
  unfold resolve_fit_content.
  simpl in *.
  split.
  - apply Nat.min_glb_iff. split.
    + exact Hle.
    + apply Nat.le_max_l.
  - apply Nat.le_min_l.
Qed.

