### 1. Audit Summary: Chromium Blink Grid Item Stretch vs. CSS Box Alignment 3 §6.2

In Chromium Blink (`third_party/blink/renderer/core/layout/grid/grid_layout_algorithm.cc`), Grid Item Stretch Alignment implements CSS Box Alignment Module Level 3 §6.2 (*Stretch Alignment: the `stretch` keyword*). When an item's inline or block size is `auto` and its self-alignment is `stretch` (or `normal` resolving to `stretch` for non-replaced items without an aspect ratio), Blink computes the stretched size against the grid area defined by the spanned tracks.

#### 1.1 Cell Area Calculation (`area_w`)
Given resolved grid track line offsets $x_{\text{start}}$ (`track_start_x`) and $x_{\text{end}}$ (`track_end_x`), the total grid area extent is $E = x_{\text{end}} - x_{\text{start}}$. 
In `GridLayoutAlgorithm::ComputeGridItemAvailableSize` and subsequent constraint space construction (`ComputeSetGeometry`), the available size passed to the item's layout subtracts the item's physical/logical margins ($M = m_{\text{start}} + m_{\text{end}}$) from the spanned track extent:
$$\text{area\_w} = \max(0, x_{\text{end}} - x_{\text{start}} - (m_{\text{start}} + m_{\text{end}}))$$
*(Note: In arithmetic without underflow clamping, $\text{area\_w} = x_{\text{end}} - x_{\text{start}} - \text{margins}$.)*

#### 1.2 Item Stretch Clamping (`item_w`)
Per CSS Box Alignment 3 §6.2, a `stretch`-aligned box is set to the size of its alignment container (the margin-adjusted grid area), constrained by the item's computed minimum and maximum size properties (`min-width`/`max-width` or `min-height`/`max-height`). In Blink's `MinMaxSizes::ClampSizeToMinAndMax`:
$$\text{item\_w} = \max(\text{min\_w}, \min(\text{max\_w}, \text{area\_w}))$$
Notice the asymmetry in operator precedence: $\text{min\_w}$ takes precedence over $\text{max\_w}$ when $\text{min\_w} > \text{max\_w}$, matching CSS Sizing 3 §4.

#### 1.3 Invariant Analysis
- **Unclamped Exact Fill**: Whenever $\text{min\_w} \le \text{area\_w} \le \text{max\_w}$, the clamping operation is an identity on $\text{area\_w}$, ensuring $\text{item\_w} = \text{area\_w}$.
- **Margin Preservation**: Because $\text{area\_w} = (x_{\text{end}} - x_{\text{start}}) - \text{margins}$, an unclamped stretched item satisfies $\text{item\_w} + \text{margins} = x_{\text{end}} - x_{\text{start}}$, preserving both margins and exact track-boundary occupancy.

---

### 2. Formal Verification in Rocq / Coq (`BlinkGridItemStretchSemantics.v`)

The following file provides self-contained definitions and machine-checked proofs for Blink's stretch alignment semantics over `Z` (representing Blink's fixed-point `LayoutUnit`).

```coq
(** * BlinkGridItemStretchSemantics.v
    Formal Audit of Chromium Blink Grid Item Stretch Alignment
    against CSS Box Alignment Module Level 3 §6.2.
    Agent 173. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Section GridItemStretch.

  (** ** 1. Data Model & Definitions *)

  (** Grid track boundaries and item box constraints represented in LayoutUnits (Z). *)
  Record GridStretchContext := mkContext {
    track_start_x : Z;
    track_end_x   : Z;
    margin_start  : Z;
    margin_end    : Z;
    min_w         : Z;
    max_w         : Z
  }.

  (** Total margins along the stretch axis. *)
  Definition margins (ctx : GridStretchContext) : Z :=
    margin_start ctx + margin_end ctx.

  (** Total span of the grid cell / area before margin subtraction. *)
  Definition track_span (ctx : GridStretchContext) : Z :=
    track_end_x ctx - track_start_x ctx.

  (** 1. Cell area calculation: area_w = track_end_x - track_start_x - margins. *)
  Definition area_w (ctx : GridStretchContext) : Z :=
    track_end_x ctx - track_start_x ctx - margins ctx.

  (** Blink's MinMaxSizes::ClampSizeToMinAndMax implementation:
      max(min_w, min(max_w, val)). *)
  Definition clamp_min_max (min_v max_v val : Z) : Z :=
    Z.max min_v (Z.min max_v val).

  (** 2. Item stretch: item_w = max(min_w, min(max_w, area_w)). *)
  Definition item_w (ctx : GridStretchContext) : Z :=
    clamp_min_max (min_w ctx) (max_w ctx) (area_w ctx).

  (** Outer width (margin box width) of the stretched item. *)
  Definition item_margin_box_w (ctx : GridStretchContext) : Z :=
    item_w ctx + margins ctx.


  (** ** 2. Core Invariants & Theorems *)

  (** Theorem 1: If cell area is within [min_w, max_w], the stretched item
      exact-fills the available cell area (item_w = area_w). *)
  Theorem stretch_fills_cell_area_when_within_bounds :
    forall (ctx : GridStretchContext),
      min_w ctx <= area_w ctx <= max_w ctx ->
      item_w ctx = area_w ctx.
  Proof.
    intros ctx [Hmin Hmax].
    unfold item_w, clamp_min_max.
    rewrite Z.min_r by lia.
    rewrite Z.max_r by lia.
    reflexivity.
  Qed.

  (** Theorem 2: Margin Preservation Invariant.
      When cell area is within [min_w, max_w], the stretched item's margin box
      (item_w + margins) exactly equals the distance between the grid tracks,
      preserving the specified margins without overflow or underflow. *)
  Theorem stretch_preserves_margins_and_fills_tracks :
    forall (ctx : GridStretchContext),
      min_w ctx <= area_w ctx <= max_w ctx ->
      item_margin_box_w ctx = track_span ctx /\
      track_start_x ctx + margin_start ctx + item_w ctx + margin_end ctx = track_end_x ctx.
  Proof.
    intros ctx Hbounds.
    unfold item_margin_box_w, track_span.
    rewrite stretch_fills_cell_area_when_within_bounds by assumption.
    unfold area_w, margins.
    split; lia.
  Qed.

  (** Theorem 3: CSS Sizing 3 §4 Min-Over-Max Precedence Invariant.
      In CSS and Blink, if min_w > max_w, min_w wins. *)
  Theorem stretch_min_precedence_over_max :
    forall (ctx : GridStretchContext),
      min_w ctx > max_w ctx ->
      item_w ctx = min_w ctx.
  Proof.
    intros ctx Hgt.
    unfold item_w, clamp_min_max.
     lia.
  Qed.

  (** Theorem 4: Lower Bound Guarantee.
      The stretched item width is never smaller than min_w. *)
  Theorem stretch_respects_min_w :
    forall (ctx : GridStretchContext),
      min_w ctx <= item_w ctx.
  Proof.
    intros ctx.
    unfold item_w, clamp_min_max.
     lia.
  Qed.

  (** Theorem 5: Upper Bound Guarantee (under well-formed constraints).
      Whenever min_w <= max_w, the stretched item width never exceeds max_w. *)
  Theorem stretch_respects_max_w :
    forall (ctx : GridStretchContext),
      min_w ctx <= max_w ctx ->
      item_w ctx <= max_w ctx.
  Proof.
    intros ctx Hle.
    unfold item_w, clamp_min_max.
    lia.
  Qed.

  (** Theorem 6: Monotonicity of Stretch with respect to Track Expansion.
      Expanding track_end_x (with fixed start, margins, and min/max bounds)
      monotonically increases or maintains item_w. *)
  Theorem stretch_monotonic_in_track_end :
    forall (ctx1 ctx2 : GridStretchContext),
      track_start_x ctx1 = track_start_x ctx2 ->
      margin_start ctx1  = margin_start ctx2 ->
      margin_end ctx1    = margin_end ctx2 ->
      min_w ctx1         = min_w ctx2 ->
      max_w ctx1         = max_w ctx2 ->
      track_end_x ctx1  <= track_end_x ctx2 ->
      item_w ctx1       <= item_w ctx2.
  Proof.
    intros ctx1 ctx2 Hstart Hms Hme Hmin Hmax Hend.
    unfold item_w, clamp_min_max, area_w, margins.
    rewrite Hstart, Hms, Hme, Hmin, Hmax.
    lia.
  Qed.

End GridItemStretch.
```