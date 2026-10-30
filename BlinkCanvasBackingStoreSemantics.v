(**
  BlinkCanvasBackingStoreSemantics.v
  Formal specification of Chromium Blink HTML canvas backing store layout and DPR buffer sizing
  derived from third_party/blink/renderer/core/html/canvas/canvas_rendering_context_host.cc
  and html_canvas_element.cc
  according to HTML Living Standard (§4.12.5 The canvas element) and CSSOM View DPR scaling.
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Definition kDefaultCanvasWidth : Z := 300.
Definition kDefaultCanvasHeight : Z := 150.
Definition kMaxTextureDimension : Z := 16384.
Definition kDprScale : Z := 1024.

Record CanvasIntrinsicSize := {
  attr_width : Z;
  attr_height : Z
}.

Definition default_canvas_size : CanvasIntrinsicSize := {|
  attr_width := kDefaultCanvasWidth;
  attr_height := kDefaultCanvasHeight
|}.

Definition compute_buffer_dimension (css_dim dpr max_dim : Z) : Z :=
  let scaled := css_dim * dpr / kDprScale in
  Z.max 0 (Z.min scaled max_dim).

Definition resolve_canvas_layout_dimension (spec_w spec_h : option Z) (intr : CanvasIntrinsicSize) : Z * Z :=
  match spec_w, spec_h with
  | Some w, Some h => (w, h)
  | Some w, None =>
      if intr.(attr_width) <=? 0 then (w, intr.(attr_height))
      else (w, w * intr.(attr_height) / intr.(attr_width))
  | None, Some h =>
      if intr.(attr_height) <=? 0 then (intr.(attr_width), h)
      else (h * intr.(attr_width) / intr.(attr_height), h)
  | None, None => (intr.(attr_width), intr.(attr_height))
  end.

(** 1. Backing Store Buffer Bounds Invariants *)

Theorem buffer_dimension_bounded_by_max :
  forall (css_dim dpr max_dim : Z),
    0 <= max_dim ->
    compute_buffer_dimension css_dim dpr max_dim <= max_dim.
Proof.
  intros css_dim dpr max_dim Hmax.
  unfold compute_buffer_dimension.
  apply Z.max_lub.
  - exact Hmax.
  - apply Z.le_min_r.
Qed.

Theorem buffer_dimension_nonneg :
  forall (css_dim dpr max_dim : Z),
    0 <= compute_buffer_dimension css_dim dpr max_dim.
Proof.
  intros css_dim dpr max_dim.
  unfold compute_buffer_dimension.
  apply Z.le_max_l.
Qed.

Theorem buffer_dimension_monotonic :
  forall (css_dim1 css_dim2 dpr max_dim : Z),
    0 <= dpr ->
    0 <= max_dim ->
    css_dim1 <= css_dim2 ->
    compute_buffer_dimension css_dim1 dpr max_dim <= compute_buffer_dimension css_dim2 dpr max_dim.
Proof.
  intros css_dim1 css_dim2 dpr max_dim Hdpr Hmax Hle.
  unfold compute_buffer_dimension, kDprScale.
  assert (Hprod : css_dim1 * dpr <= css_dim2 * dpr).
  { apply Z.mul_le_mono_nonneg_r; lia. }
  assert (Hdiv : css_dim1 * dpr / 1024 <= css_dim2 * dpr / 1024).
  { apply Z.div_le_mono; lia. }
  lia.
Qed.

(** 2. Replaced Element Aspect Ratio Resolution Theorems *)

Theorem canvas_both_auto_matches_intrinsic :
  forall intr : CanvasIntrinsicSize,
    resolve_canvas_layout_dimension None None intr = (intr.(attr_width), intr.(attr_height)).
Proof.
  intros intr.
  reflexivity.
Qed.

Theorem canvas_width_specified_aspect_preservation :
  forall (w : Z) (intr : CanvasIntrinsicSize),
    0 < intr.(attr_width) ->
    0 <= intr.(attr_height) ->
    0 <= w ->
    let (_, h_res) := resolve_canvas_layout_dimension (Some w) None intr in
    h_res * intr.(attr_width) <= w * intr.(attr_height).
Proof.
  intros w intr Hw Hh Hwpos.
  unfold resolve_canvas_layout_dimension.
  destruct (intr.(attr_width) <=? 0) eqn:Ew; [lia|].
  rewrite Z.mul_comm.
  apply Z.mul_div_le.
  exact Hw.
Qed.
