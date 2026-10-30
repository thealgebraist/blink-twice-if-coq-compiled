(******************************************************************************)
(* BlinkOutOfFlowSemantics.v                                                  *)
(* Sound Big-Step Semantics for CSS Out-of-Flow (Absolute/Fixed) Positioning   *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS 2.1 Section 9.3 (Absolute Positioning)                          *)
(* 2. W3C CSS 2.1 Section 10.3.7 & 10.6.4 (Non-replaced positioned elements)  *)
(* 3. Blink LayoutNG OutOfFlowLayoutPart (out_of_flow_layout_part.cc)         *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Open Scope Z_scope.

(** W3C Inset representation: Definite offset or 'auto' (Indefinite) *)
Inductive InsetValue : Type :=
  | InsetAuto
  | InsetPx (v : Z).

Record PositionedInsets := mkPositionedInsets {
  inset_left : InsetValue;
  inset_right : InsetValue;
  inset_top : InsetValue;
  inset_bottom : InsetValue
}.

Record ContainingBlock := mkContainingBlock {
  cb_width : Z;
  cb_height : Z
}.

Record PhysicalBox := mkPhysicalBox {
  box_x : Z;
  box_y : Z;
  box_w : Z;
  box_h : Z
}.

(** Blink/CSS 2.1 Section 10.3.7 1D Equation Solver:
    left + margin-left + border-padding + width + margin-right + right = containing_block_width.
    When width is specified and both left/right are auto, static_pos is used.
    When left is auto but right is specified: left = cb_width - right - width.
    When right is auto but left is specified: right = cb_width - left - width.
    When none are auto (over-constrained): right is solved / dropped in LTR. *)

Definition compute_positioned_1d (cb_size : Z) (static_pos : Z)
                                 (inset_start : InsetValue) (inset_end : InsetValue)
                                 (size : Z) : (Z * Z) :=
  match inset_start, inset_end with
  | InsetAuto, InsetAuto =>
      (* Rule: 'static-position' used for start offset *)
      (static_pos, cb_size - static_pos - size)
  | InsetPx s, InsetAuto =>
      (s, cb_size - s - size)
  | InsetAuto, InsetPx e =>
      (cb_size - e - size, e)
  | InsetPx s, InsetPx e =>
      (* Over-constrained in LTR: 'start' wins, 'end' is ignored/derived *)
      (s, cb_size - s - size)
  end.

Definition resolve_out_of_flow_box (cb : ContainingBlock) (static_x static_y : Z)
                                   (insets : PositionedInsets) (w h : Z) : PhysicalBox :=
  let (final_x, _) := compute_positioned_1d (cb_width cb) static_x (inset_left insets) (inset_right insets) w in
  let (final_y, _) := compute_positioned_1d (cb_height cb) static_y (inset_top insets) (inset_bottom insets) h in
  mkPhysicalBox final_x final_y (sat_clamp w) (sat_clamp h).

(******************************************************************************)
(* SOUNDNESS & INVARIANT THEOREMS                                             *)
(******************************************************************************)

(** Theorem 1: 1D Positioned Equation Conservation (W3C CSS 2.1 Sec 10.3.7)
    In all cases, start_offset + size + end_offset = cb_size *)
Theorem positioned_1d_conservation :
  forall cb_size static_pos inset_start inset_end size,
    let (s, e) := compute_positioned_1d cb_size static_pos inset_start inset_end size in
    s + size + e = cb_size.
Proof.
  intros cb_size static_pos inset_start inset_end size.
  unfold compute_positioned_1d.
  destruct inset_start; destruct inset_end; simpl; lia.
Qed.

(** Theorem 2: Determinism of Out-of-Flow Box Placement *)
Theorem out_of_flow_placement_deterministic :
  forall cb sx sy insets w h b1 b2,
    b1 = resolve_out_of_flow_box cb sx sy insets w h ->
    b2 = resolve_out_of_flow_box cb sx sy insets w h ->
    b1 = b2.
Proof.
  intros cb sx sy insets w h b1 b2 H1 H2.
  subst. reflexivity.
Qed.

(** Theorem 3: Width & Height Non-Negativity of Clamped Out-of-Flow Fragment *)
Theorem out_of_flow_fragment_size_nonneg :
  forall cb sx sy insets w h,
    0 <= w -> 0 <= h ->
    0 <= box_w (resolve_out_of_flow_box cb sx sy insets w h) /\
    0 <= box_h (resolve_out_of_flow_box cb sx sy insets w h).
Proof.
  intros cb sx sy insets w h Hw Hh.
  unfold resolve_out_of_flow_box.
  destruct (compute_positioned_1d (cb_width cb) sx (inset_left insets) (inset_right insets) w) as [fx rx].
  destruct (compute_positioned_1d (cb_height cb) sy (inset_top insets) (inset_bottom insets) h) as [fy ry].
  simpl.
  split; unfold sat_clamp.
  - destruct (Z.gtb_spec w kInt32Max).
    + unfold kInt32Max. lia.
    + destruct (Z.ltb_spec w kInt32Min).
      * unfold kInt32Min in *. lia.
      * lia.
  - destruct (Z.gtb_spec h kInt32Max).
    + unfold kInt32Max. lia.
    + destruct (Z.ltb_spec h kInt32Min).
      * unfold kInt32Min in *. lia.
      * lia.
Qed.
