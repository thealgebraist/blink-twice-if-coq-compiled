(**
  BlinkTextDecorationMetricsSemantics.v
  Formal specification of Chromium Blink text decoration sizing and baseline offsets
  derived from third_party/blink/renderer/core/paint/text_decoration_info.cc
  according to W3C CSS Text Decoration Module Level 3 (§2 & §3 Line-through, Underline, Overline).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Record FontDecorationMetrics := {
  metric_ascent : Z;
  metric_descent : Z;
  metric_underline_pos : Z;
  metric_underline_thickness : Z
}.

Definition resolve_decoration_thickness (raw_thickness max_thickness : Z) : Z :=
  let floored := Z.max 1 raw_thickness in
  Z.min floored max_thickness.

Definition compute_underline_offset (baseline font_pos css_offset : Z) : Z :=
  let delta := Z.max 1 (font_pos + css_offset) in
  baseline + delta.

Definition compute_overline_offset (baseline ascent css_offset : Z) : Z :=
  let delta := Z.max 0 (ascent + css_offset) in
  baseline - delta.

(** 1. Thickness Visibility Lower Bound Invariant *)

Theorem decoration_thickness_at_least_one :
  forall (raw_t max_t : Z),
    1 <= max_t ->
    1 <= resolve_decoration_thickness raw_t max_t <= max_t.
Proof.
  intros raw_t max_t Hmax.
  unfold resolve_decoration_thickness.
  split.
  - apply Z.min_glb_iff.
    split; [apply Z.le_max_l | exact Hmax].
  - apply Z.le_min_r.
Qed.

(** 2. Vertical Stacking Order Invariant *)

Theorem text_decoration_vertical_ordering :
  forall (baseline ascent font_pos css_offset : Z),
    0 <= ascent ->
    0 <= font_pos ->
    0 <= css_offset ->
    compute_overline_offset baseline ascent css_offset <= baseline /\
    baseline <= compute_underline_offset baseline font_pos css_offset.
Proof.
  intros baseline ascent font_pos css_offset Hasc Hpos Hcss.
  unfold compute_overline_offset, compute_underline_offset.
  split; lia.
Qed.

Theorem underline_strictly_below_baseline :
  forall (baseline font_pos css_offset : Z),
    0 <= font_pos ->
    0 <= css_offset ->
    baseline < compute_underline_offset baseline font_pos css_offset.
Proof.
  intros baseline font_pos css_offset Hpos Hcss.
  unfold compute_underline_offset.
  lia.
Qed.

