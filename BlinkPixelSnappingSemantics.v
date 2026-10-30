(** * BlinkPixelSnappingSemantics.v
    Formal verification of Chromium Blink Pixel Snapping vs CSS Subpixel Rendering.
*)

From Stdlib Require Import ZArith.ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import micromega.Lia.
Import ListNotations.
Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** LayoutUnit is 26.6 fixed-point arithmetic with denominator 64 *)
Definition LayoutUnit := Z.
Definition kFixedPointDenominator : Z := 64.
Definition kHalfDenominator : Z := 32.

Record SubpixelInterval : Type := mkInterval {
  sub_loc  : LayoutUnit;
  sub_size : LayoutUnit
}.

Record SnappedInterval : Type := mkSnappedInterval {
  snap_loc  : Z;
  snap_size : Z
}.

Record SubpixelRect : Type := mkSubpixelRect {
  sub_x : LayoutUnit;
  sub_y : LayoutUnit;
  sub_w : LayoutUnit;
  sub_h : LayoutUnit
}.

Record SnappedRect : Type := mkSnappedRect {
  snap_x : Z;
  snap_y : Z;
  snap_w : Z;
  snap_h : Z
}.

(** ** 2. Pixel Snapping Algorithms *)

Definition round_to_pixel (v : LayoutUnit) : Z :=
  (v + kHalfDenominator) / kFixedPointDenominator.

Definition snap_size_to_pixel (size loc : LayoutUnit) : Z :=
  round_to_pixel (loc + size) - round_to_pixel loc.

Definition snap_interval (i : SubpixelInterval) : SnappedInterval :=
  mkSnappedInterval (round_to_pixel (sub_loc i)) (snap_size_to_pixel (sub_size i) (sub_loc i)).

Definition snap_rect (r : SubpixelRect) : SnappedRect :=
  mkSnappedRect
    (round_to_pixel (sub_x r))
    (round_to_pixel (sub_y r))
    (snap_size_to_pixel (sub_w r) (sub_x r))
    (snap_size_to_pixel (sub_h r) (sub_y r)).

(** ** 3. Mathematical Invariants & Verification *)

Lemma round_to_pixel_monotonic : forall v1 v2 : LayoutUnit,
  v1 <= v2 ->
  round_to_pixel v1 <= round_to_pixel v2.
Proof.
  intros v1 v2 Hle.
  unfold round_to_pixel, kHalfDenominator, kFixedPointDenominator.
  apply Z.div_le_mono; lia.
Qed.

(** Invariant 1: Exact Adjacency Preservation (No Gaps, No Overlaps) *)
Theorem snapped_interval_adjacency_preserved :
  forall (i1 i2 : SubpixelInterval),
    sub_loc i1 + sub_size i1 = sub_loc i2 ->
    snap_loc (snap_interval i1) + snap_size (snap_interval i1) = snap_loc (snap_interval i2).
Proof.
  intros [x1 w1] [x2 w2] Habut.
  unfold snap_interval, snap_size_to_pixel.
  simpl in *.
  rewrite Habut.
  lia.
Qed.

(** Invariant 2: Non-negative Size Preservation *)
Theorem snap_size_nonneg :
  forall (size loc : LayoutUnit),
    0 <= size ->
    0 <= snap_size_to_pixel size loc.
Proof.
  intros size loc Hsz.
  unfold snap_size_to_pixel.
  assert (Hle : loc <= loc + size) by lia.
  pose proof (round_to_pixel_monotonic loc (loc + size) Hle) as Hround.
  lia.
Qed.

(** Invariant 3: Telescoping Sum Conservation over Abutting Chains *)
Fixpoint sum_snapped_sizes (chain : list SubpixelInterval) : Z :=
  match chain with
  | [] => 0
  | i :: rest => snap_size (snap_interval i) + sum_snapped_sizes rest
  end.

Fixpoint sum_sub_sizes (chain : list SubpixelInterval) : LayoutUnit :=
  match chain with
  | [] => 0
  | i :: rest => sub_size i + sum_sub_sizes rest
  end.

Theorem telescoping_sum_abutting_chain :
  forall (chain : list SubpixelInterval) (start_loc : LayoutUnit),
    (forall i : nat, (i + 1 < length chain)%nat ->
      sub_loc (nth i chain (mkInterval 0 0)) + sub_size (nth i chain (mkInterval 0 0)) =
      sub_loc (nth (i + 1) chain (mkInterval 0 0))) ->
    (match chain with
     | [] => True
     | i0 :: _ => sub_loc i0 = start_loc
     end) ->
    chain <> [] ->
    let last_i := nth (length chain - 1)%nat chain (mkInterval 0 0) in
    sum_snapped_sizes chain =
    round_to_pixel (sub_loc last_i + sub_size last_i) - round_to_pixel start_loc.
Proof.
  intros chain.
  induction chain as [| i0 rest IH]; intros start_loc Habut Hstart Hnotempty.
  - contradiction.
  - destruct rest as [| i1 rest'].
    + simpl.
      unfold snap_size_to_pixel.
      simpl in Hstart. subst start_loc.
      lia.
    + assert (Hfirst_abut : sub_loc i0 + sub_size i0 = sub_loc i1).
        { specialize (Habut 0%nat).
          simpl in Habut.
          apply Habut. lia. }
        assert (Habut_rest : forall i : nat, (i + 1 < length (i1 :: rest'))%nat ->
          sub_loc (nth i (i1 :: rest') (mkInterval 0 0)) + sub_size (nth i (i1 :: rest') (mkInterval 0 0)) =
          sub_loc (nth (i + 1) (i1 :: rest') (mkInterval 0 0))).
        { intros i Hi.
          specialize (Habut (S i)).
          simpl in Habut.
          apply Habut.
          simpl in Hi. lia. }
        assert (Hstart_rest : sub_loc i1 = sub_loc i1) by reflexivity.
        assert (Hnotempty_rest : (i1 :: rest') <> []) by discriminate.
        pose proof (IH (sub_loc i1) Habut_rest Hstart_rest Hnotempty_rest) as Hih.
        assert (Hlast : nth (length (i0 :: i1 :: rest') - 1) (i0 :: i1 :: rest') (mkInterval 0 0) =
                        nth (length (i1 :: rest') - 1) (i1 :: rest') (mkInterval 0 0)).
        { simpl. rewrite Nat.sub_0_r. reflexivity. }
        rewrite Hlast.
        change (sum_snapped_sizes (i0 :: i1 :: rest')) with
          (snap_size (snap_interval i0) + sum_snapped_sizes (i1 :: rest')).
        rewrite Hih.
        unfold snap_interval, snap_size_to_pixel.
        simpl snap_size.
        simpl in Hstart. subst start_loc.
        rewrite Hfirst_abut.
        lia.
Qed.

(** Invariant 4: 2D Horizontal Rect Adjacency *)
Theorem snapped_rect_horizontal_adjacency :
  forall r1 r2,
    sub_x r1 + sub_w r1 = sub_x r2 ->
    snap_x (snap_rect r1) + snap_w (snap_rect r1) = snap_x (snap_rect r2).
Proof.
  intros [x1 y1 w1 h1] [x2 y2 w2 h2] Habut.
  unfold snap_rect, snap_size_to_pixel.
  simpl in *.
  rewrite Habut.
  lia.
Qed.

(** Invariant 5: 2D Vertical Rect Adjacency *)
Theorem snapped_rect_vertical_adjacency :
  forall r1 r2,
    sub_y r1 + sub_h r1 = sub_y r2 ->
    snap_y (snap_rect r1) + snap_h (snap_rect r1) = snap_y (snap_rect r2).
Proof.
  intros [x1 y1 w1 h1] [x2 y2 w2 h2] Habut.
  unfold snap_rect, snap_size_to_pixel.
  simpl in *.
  rewrite Habut.
  lia.
Qed.
