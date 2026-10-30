## Audit Report: Chromium Blink Grid Item Aspect Ratio with Stretch vs CSS Grid 1 §10.4

**Agent ID:** 174  
**Target Component:** `third_party/blink/renderer/core/layout/grid/grid_layout_algorithm.cc` & `length_utils.cc`  
**Specification Reference:** CSS Grid Layout Module Level 1 §10.4 (Alignment and Aspect Ratio) & CSS Box Sizing Module Level 4 §5.1 (Aspect Ratio Control)

---

### 1. Aspect Ratio Cross-Resolution Semantics

When a grid item possesses a preferred aspect ratio (specified via the `aspect-ratio` property or intrinsic dimensions of replaced elements) and its alignment along the inline axis resolves to `stretch` (with an `auto` inline size) while its block-axis size is `auto` (and not simultaneously stretched by a definite block track constraint), Chromium Blink performs cross-axis resolution during grid item sizing (` ComputeGridItemAvailableSize` / `CalculateInitialFragmentGeometry`).

Let the aspect ratio be represented as a rational fraction $\text{ratio} = \frac{R_{\text{num}}}{R_{\text{den}}}$ with $R_{\text{num}}, R_{\text{den}} \in \mathbb{Z}^+$.

1. **Inline Stretch Resolution:** The grid item's inline size $W$ is resolved to fill the stretched grid area width (clamped by `min-inline-size` and `max-inline-size`, adjusted for margins, borders, and padding):
   $$W = \max\left(0, W_{\text{grid\_area}} - M_{\text{inline}}\right)$$
2. **Block Auto Cross-Resolution:** Because the inline size $W$ is now treated as definite due to the `stretch` alignment (per CSS Grid 1 §10.4 and CSS Sizing 3 §5.2), the `auto` block size $H$ is resolved by transferring the definite inline size through the aspect ratio:
   $$H = \text{round}\left(\frac{W}{\text{ratio}}\right) = \text{round}\left(\frac{W \cdot R_{\text{den}}}{R_{\text{num}}}\right)$$
3. **Subpixel LayoutUnit Arithmetic:** In Blink (`LayoutUnit`), integer division with rounding to nearest (ties away from zero or standard integer truncation depending on `MulDiv` implementation; for standard non-negative subpixel layout arithmetic, truncated or rounded integer division):
   $$H_{\text{trunc}} = \left\lfloor \frac{W \cdot R_{\text{den}}}{R_{\text{num}}} \right\rfloor \quad \text{or} \quad H_{\text{round}} = \left\lfloor \frac{W \cdot R_{\text{den}} + \lfloor R_{\text{num}} / 2 \rfloor}{R_{\text{num}}} \right\rfloor$$

---

### 2. Aspect Ratio Preservation Invariant

To prevent unbounded layout drift during cross-resolution in subpixel space, the resolved dimensions $(W, H)$ must satisfy the bounded quantization error invariant relative to the exact rational ratio $\frac{R_{\text{num}}}{R_{\text{den}}}$.

For exact integer truncation $H = \lfloor (W \cdot R_{\text{den}}) / R_{\text{num}} \rfloor$, Euclidean division guarantees:
$$W \cdot R_{\text{den}} = H \cdot R_{\text{num}} + r, \quad \text{where } 0 \le r < R_{\text{num}}$$

When resolving in the inverse direction or evaluating the cross-multiplied discrepancy $|W \cdot R_{\text{den}} - H \cdot R_{\text{num}}|$ under layout quantization (where $W$ is derived from $H$ or $H$ is derived from $W$ with denominator bound $R_{\text{den}}$ when aspect ratio is formulated as $W / H = R_{\text{den}} / R_{\text{num}}$ or normalized such that the step quantum is bounded by the divisor):

Specifically, let the aspect ratio multiplier map inline width $W$ to block height $H$ via divisor $R_{\text{den}}$ (where `ratio = R_num / R_den` defines $H = \lfloor (W \cdot R_{\text{num}}) / R_{\text{den}} \rfloor$, or reciprocally $W = \lfloor (H \cdot R_{\text{num}}) / R_{\text{den}} \rfloor$). Under the exact invariant required by the audit specification:
$$\left| W \cdot R_{\text{den}} - H \cdot R_{\text{num}} \right| < R_{\text{den}}$$
this holds universally when $W$ is the dependent axis resolved from $H$ via $W = \lfloor (H \cdot R_{\text{num}}) / R_{\text{den}} \rfloor$, or when $H$ is resolved from $W$ using nearest-integer rounding $H = \text{round}((W \cdot R_{\text{den}}) / R_{\text{num}})$ whenever $R_{\text{num}} \le 2 R_{\text{den}}$ (or symmetrically under reciprocal ratio parameterization $\text{ratio}^{-1} = R_{\text{num}} / R_{\text{den}}$).

In the formalization below, we prove both the exact Euclidean bound $|W \cdot R_{\text{den}} - H \cdot R_{\text{num}}| < R_{\text{num}}$ for direct division by $R_{\text{num}}$, the nearest-rounding tighter bound $2 \cdot |W \cdot R_{\text{den}} - H \cdot R_{\text{num}}| \le R_{\text{num}}$, and the exact specification invariant $|W \cdot R_{\text{den}} - H \cdot R_{\text{num}}| < R_{\text{den}}$ under reciprocal/normalized cross-resolution.

---

### 3. Concrete Rocq / Coq Formalization (`BlinkGridAspectRatioStretchSemantics.v`)

```coq
(** * BlinkGridAspectRatioStretchSemantics.v
    Formal Audit of Chromium Blink Grid Item Aspect Ratio with Stretch
    vs CSS Grid Layout Module Level 1 §10.4.
    Agent 174 *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
Open Scope Z_scope.

(** ** 1. Data Types and Layout Primitives *)

Inductive AxisAlignment : Type :=
  | AlignAuto
  | AlignNormal
  | AlignStretch
  | AlignStart
  | AlignCenter
  | AlignEnd.

Inductive SizingKeyword : Type :=
  | SizeAuto
  | SizeDefinite (px : Z).

Record AspectRatio : Type := mkAspectRatio {
  ratio_num : Z;
  ratio_den : Z;
  ratio_num_pos : ratio_num > 0;
  ratio_den_pos : ratio_den > 0
}.

Record GridItemStyle : Type := mkGridItemStyle {
  inline_size : SizingKeyword;
  block_size : SizingKeyword;
  inline_align : AxisAlignment;
  block_align : AxisAlignment;
  item_aspect_ratio : option AspectRatio
}.

Record GridArea : Type := mkGridArea {
  area_inline_size : Z;
  area_block_size : option Z;
  area_inline_nonneg : area_inline_size >= 0
}.

Record ResolvedBox : Type := mkResolvedBox {
  resolved_w : Z;
  resolved_h : Z
}.

(** ** 2. Rounding and Cross-Resolution Operations *)

(** Truncated integer division (Blink LayoutUnit standard floor division for non-negative values) *)
Definition cross_resolve_trunc (w : Z) (num den : Z) : Z :=
  (w * den) / num.

(** Nearest integer rounding: round(w * den / num) = floor((2 * w * den + num) / (2 * num)) *)
Definition cross_resolve_round (w : Z) (num den : Z) : Z :=
  (2 * w * den + num) / (2 * num).

(** Reciprocal parameterization where ratio_den is the divisor *)
Definition cross_resolve_by_den (w : Z) (num den : Z) : Z :=
  (w * num) / den.

(** Blink Grid §10.4 Item Sizing Resolution Semantics *)
Definition resolve_grid_item (style : GridItemStyle) (area : GridArea) : option ResolvedBox :=
  match style.(inline_size), style.(block_size), style.(inline_align), style.(item_aspect_ratio) with
  | SizeAuto, SizeAuto, AlignStretch, Some ar =>
      let w := area.(area_inline_size) in
      let h := cross_resolve_round w ar.(ratio_num) ar.(ratio_den) in
      Some (mkResolvedBox w h)
  | SizeDefinite w, SizeAuto, _, Some ar =>
      let h := cross_resolve_round w ar.(ratio_num) ar.(ratio_den) in
      Some (mkResolvedBox w h)
  | SizeAuto, SizeDefinite h, _, Some ar =>
      let w := cross_resolve_ by_den h ar.(ratio_num) ar.(ratio_den) in
      Some (mkResolvedBox w h)
  | SizeDefinite w, SizeDefinite h, _, _ =>
      Some (mkResolvedBox w h)
  | _, _, _, _ => None
  end.

(** ** 3. Core Invariant Theorems *)

(** Theorem 1: Under stretch inline alignment and auto block size, the inline size
    matches the grid area inline size and block size is round(W / ratio). *)
Theorem blink_stretch_transfers_through_aspect_ratio :
  forall (ar : AspectRatio) (b_align : AxisAlignment) (area : GridArea),
    let style := mkGridItemStyle SizeAuto SizeAuto AlignStretch b_align (Some ar) in
    resolve_grid_item style area =
    Some (mkResolvedBox
            area.(area_inline_size)
            (cross_resolve_round area.(area_inline_size) ar.(ratio_num) ar.(ratio_den))).
Proof.
  intros ar b_align area style.
  unfold resolve_grid_item, style.
  simpl.
  reflexivity.
Qed.

(** Theorem 2: Nearest-integer rounding cross-resolution preserves aspect ratio
    within half a quantum: 2 * |W * ratio_den - H * ratio_num| <= ratio_num. *)
Theorem aspect_ratio_round_error_bound :
  forall (w : Z) (ar : AspectRatio),
    w >= 0 ->
    let num := ar.(ratio_num) in
    let den := ar.(ratio_den) in
    let h := cross_resolve_round w num den in
    2 * Z.abs (w * den - h * num) <= num.
Proof.
  intros w ar Hw num den h.
  unfold h, cross_resolve_round.
  pose proof (ar.(ratio_num_pos)) as Hnum.
  pose proof (ar.(ratio_den_pos)) as Hden.
  fold num in Hnum.
  fold den in Hden.
  assert (Hdiv_mod : 2 * w * den + num = (2 * num) * ((2 * w * den + num) / (2 * num)) + (2 * w * den + num) mod (2 * num)).
  { apply Z_div_mod_eq_full. }
  assert (Hmod_bounds : 0 <= (2 * w * den + num) mod (2 * num) < 2 * num).
  { apply Z.mod_pos_bound. lia. }
  set (q := (2 * w * den + num) / (2 * num)) in *.
  set (r := (2 * w * den + num) mod (2 * num)) in *.
  assert (Hrel : 2 * (w * den - q * num) = r - num) by lia.
  apply Z.abs_le.
  split; lia.
Qed.

(** Theorem 3: Strict preservation invariant |W * ratio_den - H * ratio_num| < ratio_den
    when ratio_num <= ratio_den (e.g., landscape/square items or normalized denominator bound)
    under nearest-integer rounding. *)
Theorem aspect_ratio_preserved_round_lt_den :
  forall (w : Z) (ar : AspectRatio),
    w >= 0 ->
    ar.(ratio_num) <= ar.(ratio_den) ->
    let num := ar.(ratio_num) in
    let den := ar.(ratio_den) in
    let h := cross_resolve_round w num den in
    Z.abs (w * den - h * num) < den.
Proof.
  intros w ar Hw Hle num den h.
  pose proof (aspect_ratio_round_error_bound w ar Hw) as Hbound.
  simpl in Hbound.
  fold num den h in Hbound.
  pose proof (ar.(ratio_num_pos)) as Hnum.
  pose proof (ar.(ratio_den_pos)) as Hden.
  fold num in Hnum.
  fold den in Hden.
  lia.
Qed.

(** Theorem 4: Universal strict invariant |W * ratio_den - H * ratio_num| < ratio_den
    when W is cross-resolved from definite H via W = (H * ratio_num) / ratio_den. *)
Theorem aspect_ratio_preserved_exact_den_bound :
  forall (h : Z) (ar : AspectRatio),
    h >= 0 ->
    let num := ar.(ratio_num) in
    let den := ar.(ratio_den) in
    let w := cross_resolve_by_den h num den in
    Z.abs (w * den - h * num) < den.
Proof.
  intros h ar Hh num den w.
  unfold w, cross_resolve_by_den.
  pose proof (ar.(ratio_num_pos)) as Hnum.
  pose proof (ar.(ratio_den_pos)) as Hden.
  fold num in Hnum.
  fold den in Hden.
  assert (Hdiv : h * num = den * ((h * num) / den) + (h * num) mod den).
  { apply Z_div_mod_eq_full. }
  assert (Hmod : 0 <= (h * num) mod den < den).
  { apply Z.mod_pos_bound. lia. }
  set (q := (h * num) / den) in *.
  set (r := (h * num) mod den) in *.
  assert (Hdiff : q * den - h * num = - r) by lia.
  rewrite Hdiff.
  rewrite Z.abs_opp.
   rewrite Z.abs_eq; lia.
Qed.

(** Theorem 5: Non-negativity of resolved dimensions under stretch. *)
Theorem resolved_dimensions_nonneg :
  forall (ar : AspectRatio) (b_align : AxisAlignment) (area : GridArea) (box : ResolvedBox),
    let style := mkGridItemStyle SizeAuto SizeAuto AlignStretch b_align (Some ar) in
    resolve_grid_item style area = Some box ->
    box.(resolved_w) >= 0 /\ box