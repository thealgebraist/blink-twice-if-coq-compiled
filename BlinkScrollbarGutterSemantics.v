(**
  BlinkScrollbarGutterSemantics.v
  Formal specification of Chromium Blink CSS scrollbar gutter and width reservation
  derived from third_party/blink/renderer/core/layout/scrollbars.cc and layout_box.cc
  according to W3C CSS Scrollbars Module Level 1 (§2 scrollbar-gutter & scrollbar-width).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Definition kDefaultScrollbarThickness : Z := 16.
Definition kThinScrollbarThickness : Z := 8.

Inductive ScrollbarWidth : Type :=
  | Scrollbar_Auto
  | Scrollbar_Thin
  | Scrollbar_None.

Inductive ScrollbarGutter : Type :=
  | Gutter_Auto
  | Gutter_Stable
  | Gutter_BothEdges.

Definition resolve_scrollbar_thickness (sw : ScrollbarWidth) : Z :=
  match sw with
  | Scrollbar_Auto => kDefaultScrollbarThickness
  | Scrollbar_Thin => kThinScrollbarThickness
  | Scrollbar_None => 0
  end.

Definition compute_reserved_gutters
    (sw : ScrollbarWidth) (sg : ScrollbarGutter) (is_scrolling : bool) : Z * Z :=
  let t := resolve_scrollbar_thickness sw in
  match sw with
  | Scrollbar_None => (0, 0)
  | _ =>
      match sg with
      | Gutter_BothEdges => (t, t)
      | Gutter_Stable    => (0, t)
      | Gutter_Auto      => if is_scrolling then (0, t) else (0, 0)
      end
  end.

Definition compute_content_inline_size
    (box_w padding_borders : Z) (gutters : Z * Z) : Z :=
  let '(g_start, g_end) := gutters in
  Z.max 0 (box_w - (padding_borders + g_start + g_end)).

(** 1. Gutter Bounds and Thickness Invariants *)

Theorem scrollbar_thickness_nonneg :
  forall sw : ScrollbarWidth,
    0 <= resolve_scrollbar_thickness sw.
Proof.
  destruct sw; unfold resolve_scrollbar_thickness, kDefaultScrollbarThickness, kThinScrollbarThickness; lia.
Qed.

Theorem reserved_gutters_nonneg :
  forall (sw : ScrollbarWidth) (sg : ScrollbarGutter) (is_scrolling : bool),
    let '(g_start, g_end) := compute_reserved_gutters sw sg is_scrolling in
    0 <= g_start /\ 0 <= g_end.
Proof.
  intros sw sg is_scrolling.
  unfold compute_reserved_gutters, resolve_scrollbar_thickness, kDefaultScrollbarThickness, kThinScrollbarThickness.
  destruct sw; destruct sg; try destruct is_scrolling; simpl; split; lia.
Qed.

Theorem scrollbar_none_reserves_zero :
  forall (sg : ScrollbarGutter) (is_scrolling : bool),
    compute_reserved_gutters Scrollbar_None sg is_scrolling = (0, 0).
Proof.
  intros sg is_scrolling.
  reflexivity.
Qed.

(** 2. Content Space Conservation Theorems *)

Theorem content_inline_size_nonneg :
  forall (box_w pb : Z) (gutters : Z * Z),
    0 <= compute_content_inline_size box_w pb gutters.
Proof.
  intros box_w pb [g_start g_end].
  unfold compute_content_inline_size.
  apply Z.le_max_l.
Qed.

Theorem content_inline_size_bounded_by_box :
  forall (box_w pb : Z) (gutters : Z * Z),
    0 <= pb ->
    0 <= fst gutters ->
    0 <= snd gutters ->
    compute_content_inline_size box_w pb gutters <= Z.max 0 box_w.
Proof.
  intros box_w pb [g_start g_end] Hpb Hg1 Hg2.
  unfold compute_content_inline_size.
  simpl in *.
  lia.
Qed.

Theorem gutter_addition_decreases_available_content :
  forall (box_w pb g1 g2 delta : Z),
    0 <= delta ->
    compute_content_inline_size box_w pb (g1, g2 + delta) <=
    compute_content_inline_size box_w pb (g1, g2).
Proof.
  intros box_w pb g1 g2 delta Hdelta.
  unfold compute_content_inline_size.
  simpl.
  lia.
Qed.
