(* =========================================================================
   BlinkFormControlSemantics.v
   Formalization of Chromium Blink Form Control Baselines & Intrinsic Metrics
   Source: third_party/blink/renderer/core/layout/forms/layout_text_control.cc
           third_party/blink/renderer/core/layout/forms/layout_text_control_single_line.cc
   Specification: HTML Standard §4.10 & §15.3.5, CSS Box Alignment 3 §9.1
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

(* 26.6 Fixed-Point Saturation Constants *)
Definition kInt32Min : Z := -2147483648.
Definition kInt32Max : Z := 2147483647.

Definition sat_clamp (x : Z) : Z :=
  if x <? kInt32Min then kInt32Min
  else if x >? kInt32Max then kInt32Max
  else x.

Inductive ControlType : Type :=
  | SingleLineInput
  | MultiLineTextArea.

Record FormControlMetrics : Type := mkFormControlMetrics {
  fcm_border_top : Z;
  fcm_padding_top : Z;
  fcm_content_height : Z;
  fcm_line_height : Z;
  fcm_font_ascent : Z;
  fcm_font_descent : Z
}.

Definition compute_form_control_baseline (m : FormControlMetrics) : Z :=
  let leading := m.(fcm_line_height) - (m.(fcm_font_ascent) + m.(fcm_font_descent)) in
  let half_leading := leading / 2 in
  let center_shift := (Z.max 0 (m.(fcm_content_height) - m.(fcm_line_height))) / 2 in
  sat_clamp (m.(fcm_border_top) + m.(fcm_padding_top) + center_shift + half_leading + m.(fcm_font_ascent)).

Definition resolve_baseline_with_scroll_bypass
    (is_text_control : bool) (is_scroll_container : bool)
    (bottom_margin_edge : Z) (inner_baseline : Z) : Z :=
  if is_text_control then
    inner_baseline
  else if is_scroll_container then
    bottom_margin_edge
  else
    inner_baseline.

Theorem form_control_baseline_deterministic :
  forall m b1 b2,
    b1 = compute_form_control_baseline m ->
    b2 = compute_form_control_baseline m ->
    b1 = b2.
Proof.
  intros m b1 b2 H1 H2.
  subst. reflexivity.
Qed.

Theorem form_control_scroll_bypass_preserves_inner :
  forall is_scroll fallback inner,
    resolve_baseline_with_scroll_bypass true is_scroll fallback inner = inner.
Proof.
  intros is_scroll fallback inner.
  unfold resolve_baseline_with_scroll_bypass.
  reflexivity.
Qed.

Theorem form_control_baseline_nonneg :
  forall m,
    0 <= m.(fcm_border_top) ->
    0 <= m.(fcm_padding_top) ->
    0 <= m.(fcm_font_ascent) ->
    0 <= m.(fcm_line_height) - (m.(fcm_font_ascent) + m.(fcm_font_descent)) ->
    m.(fcm_border_top) + m.(fcm_padding_top) + m.(fcm_content_height) <= kInt32Max ->
    0 <= compute_form_control_baseline m.
Proof.
  intros m Hbt Hpt Hascent Hlead Hmax.
  unfold compute_form_control_baseline.
  set (leading := m.(fcm_line_height) - (m.(fcm_font_ascent) + m.(fcm_font_descent))).
  set (center_shift := Z.max 0 (m.(fcm_content_height) - m.(fcm_line_height)) / 2).
  assert (Hcs : 0 <= center_shift).
  { unfold center_shift.
    apply Z.div_pos; [| lia].
    apply Z.le_max_l. }
  assert (Hhl : 0 <= leading / 2).
  { apply Z.div_pos; [exact Hlead | lia]. }
  assert (Hsum_nonneg : 0 <= m.(fcm_border_top) + m.(fcm_padding_top) + center_shift + (leading / 2) + m.(fcm_font_ascent)).
  { lia. }
  unfold sat_clamp.
  destruct (m.(fcm_border_top) + m.(fcm_padding_top) + center_shift + (leading / 2) + m.(fcm_font_ascent) <? kInt32Min) eqn:Emin.
  - apply Z.ltb_lt in Emin.
    unfold kInt32Min in Emin. lia.
  - destruct (m.(fcm_border_top) + m.(fcm_padding_top) + center_shift + (leading / 2) + m.(fcm_font_ascent) >? kInt32Max) eqn:Emax.
    + unfold kInt32Max. lia.
    + exact Hsum_nonneg.
Qed.

