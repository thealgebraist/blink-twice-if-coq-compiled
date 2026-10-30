# Formal Verification Report: Blink `shape-outside` Image Alpha Channel Threshold Cutoff

**Agent**: Formal Verification Agent 702  
**Domain**: W3C/WHATWG Layout Rules (CSS Shapes) in Chromium Blink  
**Target Source**: `third_party/blink/renderer/core/layout/shapes/shape_outside_image.cc` (and associated shape extraction in `shape.cc`)  
**Specification**: CSS Shapes Module Level 1, §3.3 (Shapes from Images) & §5.2 (`shape-image-threshold`)  
**Formal Theory Target**: `BlinkShapeOutsideImageAlphaThresholdSemantics.v`  

---

## 1. Normative W3C Specification Requirements

In CSS Shapes Module Level 1, a float area's exclusion contour can be extracted from the alpha channel of a raster image supplied to the `shape-outside` property.

### 1.1 CSS Shapes 1 §3.3 (Shapes from Images) & §5.2 (`shape-image-threshold`)
* **Property Definition**: `shape-image-threshold` accepts an `<alpha-value>` (a `<number>` or `<percentage>` clamping to the closed real interval $[0.0, 1.0]$). The initial value is `0.0`.
* **Threshold Semantics**: 
  > "The `shape-image-threshold` defines the alpha channel threshold used to extract the shape using an image as the value for `shape-outside`. Any values of the alpha channel that are **greater than** the threshold result in the pixel being part of the shape." (CSS Shapes 1 §5.2).
* **Boundary & Quantization**:
  * A threshold of `0.0` implies that any pixel with strictly positive opacity ($\alpha > 0$) is included in the shape, while completely transparent pixels ($\alpha = 0$) are excluded.
  * A threshold of `1.0` implies that no pixel has an alpha strictly greater than `1.0` ($\alpha > 1.0$ is impossible in standard $[0, 1]$ alpha representation), resulting in an empty shape contour.

---

## 2. Chromium Blink Implementation Details & Invariants

In Chromium Blink's layout engine (`third_party/blink/renderer/core/layout/shapes/`), shape computation from images is orchestrated between `ShapeOutsideInfo` and `Shape::CreateRasterShape`.

### 2.1 Alpha Quantization and Threshold Cutoff
When extracting the `RasterShapeIntervals` from an `Image`'s 32-bit RGBA/BGRA pixel buffer (where each channel is quantized to an 8-bit unsigned integer `uint8_t` $\in [0, 255]$):

1. **Clamping & Scaling**: The CSS floating-point `shape_image_threshold` $t \in [0.0, 1.0]$ is clamped and mapped to an integer cutoff boundary. Specifically, Blink converts the float threshold into a discrete byte threshold:
   ```cpp
   // Conceptual discretization in Blink's shape extraction pipeline:
   uint8_t alpha_pixel_threshold = static_cast<uint8_t>(
       ClampTo<float>(shape_image_threshold, 0.0f, 1.0f) * 255.0f);
   ```
   Or when evaluating the inclusive boundary `threshold` $\in [0, 255]$ directly in the generalized predicate `is_pixel_opaque(alpha, threshold)`:
   ```cpp
   bool IsPixelOpaque(uint8_t alpha, uint8_t threshold) {
     return alpha >= threshold; // or alpha > alpha_pixel_threshold
   }
   ```
2. **Core Mathematical Property**:
   For the formalized discrete cutoff `threshold` $\in [0, 255]$ representing the minimum required opacity level:
   $$\text{is\_pixel\_opaque}(\alpha, \tau) \iff \alpha \ge \tau$$
   *(Note: We also formally bridge the strict W3C comparison $\alpha > \tau_{\text{strict}}$ with the non-strict cutoff $\alpha \ge \tau_{\text{cutoff}}$ via $\tau_{\text{cutoff}} = \tau_{\text{strict}} + 1$ in our Rocq development below).*

### 2.2 Layout Invariants in `shape_outside_image.cc`
* **Pixel Bounds**: $\forall p, 0 \le \text{alpha}(p) \le 255$.
* **Alpha Monotonicity**: Increasing the opacity $\alpha$ of a pixel under a fixed threshold $\tau$ can only transition the pixel from excluded (`false`) to included (`true`), never the reverse.
* **Threshold Antitonicity**: Increasing the threshold $\tau$ under a fixed pixel opacity $\alpha$ shrinks (or keeps equal) the set of included pixels, guaranteeing that the extracted `RasterShapeIntervals` are monotonically nested with respect to $\tau$.
* **Run-Length Interval Soundness**: Scanline interval construction (`RasterShapeIntervals`) accumulates contiguous horizontal runs of pixels where `is_pixel_opaque(alpha, threshold) == true`.

---

## 3. Formal Specification & Proofs in Rocq/Coq

Below is the complete, self-contained formalization `BlinkShapeOutsideImageAlphaThresholdSemantics.v`. It is written in standard Rocq/Coq utilizing `ZArith`, `Lia`, `Bool`, and `List`, with zero `Admitted` statements.

```coq
(** * BlinkShapeOutsideImageAlphaThresholdSemantics.v
    Formal Verification of W3C CSS Shapes 1 §3.3 & §5.2
    Chromium Source: third_party/blink/renderer/core/layout/shapes/shape_outside_image.cc
    Agent 702 - W3C/WHATWG Layout Rules *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Basic Types and Channel Bounds *)

(** An 8-bit alpha value or quantized threshold in the range [0, 255]. *)
Definition AlphaVal := Z.
Definition ThresholdVal := Z.

(** Well-formedness predicate for 8-bit unsigned byte values [0, 255]. *)
Definition valid_byte (v : Z) : Prop :=
  0 <= v <= 255.

(** Executable clamping function to the [0, 255] byte domain. *)
Definition clamp_byte (v : Z) : Z :=
  Z.max 0 (Z.min 255 v).

(** ** 2. Core Pixel Opacity Predicates *)

(** Target Mathematical Property:
    is_pixel_opaque(alpha, threshold) = (alpha >= threshold) *)
Definition is_pixel_opaque (alpha : AlphaVal) (threshold : ThresholdVal) : bool :=
  threshold <=? alpha.

(** Propositional counterpart of [is_pixel_opaque]. *)
Definition is_pixel_opaque_prop (alpha : AlphaVal) (threshold : ThresholdVal) : Prop :=
  alpha >= threshold.

(** Strict W3C threshold comparison (alpha > strict_threshold) for bridging
    CSS Shapes 1 §5.2 ("greater than the threshold") to discrete cutoffs. *)
Definition is_pixel_opaque_strict (alpha : AlphaVal) (strict_threshold : ThresholdVal) : bool :=
  strict_threshold <? alpha.

(** ** 3. Scanline Filtering and Interval Extraction Model *)

(** A scanline is modeled as a list of pixel alpha values along the X-axis. *)
Definition Scanline := list AlphaVal.

(** Count the number of opaque pixels in a scanline for a given threshold. *)
Fixpoint count_opaque_pixels (line : Scanline) (threshold : ThresholdVal) : nat :=
  match line with
  | [] => 0%nat
  | a :: rest =>
      if is_pixel_opaque a threshold
      then S (count_opaque_pixels rest threshold)
      else count_opaque_pixels rest threshold
  end.

(** Extract the indices (x-coordinates) of all opaque pixels in a scanline. *)
Fixpoint opaque_x_coords_aux (line : Scanline) (threshold : ThresholdVal) (x : nat) : list nat :=
  match line with
  | [] => []
  | a :: rest =>
      if is_pixel_opaque a threshold
      then x :: opaque_x_coords_aux rest threshold (S x)
      else opaque_x_coords_aux rest threshold (S x)
  end.

Definition opaque_x_coords (line : Scanline) (threshold : ThresholdVal) : list nat :=
  opaque_x_coords_aux line threshold 0%nat.

(** ** 4. Concrete Theorems and Complete Proofs *)

(** *** Theorem 1: Clamping Soundness and Idempotence *)
Theorem clamp_byte_valid : forall (v : Z),
  valid_byte (clamp_byte v).
Proof.
  intros v.
  unfold valid_byte, clamp_byte.
  lia.
Qed.

Theorem clamp_byte_idempotent : forall (v : Z),
  valid_byte v -> clamp_byte v = v.
Proof.
  intros v H.
  unfold valid_byte in H.
  unfold clamp_byte.
  lia.
Qed.

(** *** Theorem 2: Boolean Reflection Equivalence *)
Theorem is_pixel_opaque_iff : forall (alpha threshold : Z),
  is_pixel_opaque alpha threshold = true <-> is_pixel_opaque_prop alpha threshold.
Proof.
  intros alpha threshold.
  unfold is_pixel_opaque, is_pixel_opaque_prop.
  rewrite Z.leb_le.
  lia.
Qed.

Theorem is_pixel_opaque_false_iff : forall (alpha threshold : Z),
  is_pixel_opaque alpha threshold = false <-> alpha < threshold.
Proof.
  intros alpha threshold.
  unfold is_pixel_opaque.
  rewrite Z.leb_gt.
  reflexivity.
Qed.

(** *** Theorem 3: Monotonicity in Alpha (Primary Verification Target)
    If alpha1 <= alpha2, then if alpha1 is opaque at [threshold],
    alpha2 is guaranteed to be opaque at [threshold]. *)
Theorem is_pixel_opaque_monotone_alpha_bool : forall (a1 a2 threshold : Z),
  a1 <= a2 ->
  implb (is_pixel_opaque a1 threshold) (is_pixel_opaque a2 threshold) = true.
Proof.
  intros a1 a2 threshold Hle.
  unfold is_pixel_opaque.
  destruct (threshold <=? a1) eqn:E1; simpl; [| reflexivity].
  rewrite Z.leb_le in E1.
  rewrite Z.leb_le.
  lia.
Qed.

Theorem is_pixel_opaque_monotone_alpha : forall (a1 a2 threshold : Z),
  a1 <= a2 ->
  is_pixel_opaque a1 threshold = true ->
  is_pixel_opaque a2 threshold = true.
Proof.
  intros a1 a2 threshold Hle Hop1.
  rewrite is_pixel_opaque_iff in *.
  unfold is_pixel_opaque_prop in *.
  lia.
Qed.

(** *** Theorem 4: Antitonicity (Monotone Decreasing) in Threshold
    Increasing the threshold cutoff can only shrink or preserve the shape. *)
Theorem is_pixel_opaque_antitone_threshold : forall (alpha t1 t2 : Z),
  t1 <= t2 ->
  is_pixel_opaque alpha t2 = true ->
  is_pixel_opaque alpha t1 = true.
Proof.
  intros alpha t1 t2 Hle Hop2.
  rewrite is_pixel_opaque_iff in *.
  unfold is_pixel_opaque_prop in *.
  lia.
Qed.

(** *** Theorem 5: Boundary Cutoff Properties [0, 255] *)

(** At threshold = 0, every valid byte [0, 255] is considered opaque. *)
Theorem zero_threshold_all_valid_opaque : forall (alpha : AlphaVal),
  valid_byte alpha ->
  is_pixel_opaque alpha 0 = true.
Proof.
  intros alpha Hvalid.
  unfold valid_byte in Hvalid.
  rewrite is_pixel_opaque_iff.
  unfold is_pixel_opaque_prop.
  lia.
Qed.

(** At threshold = 255, only fully opaque pixels (alpha = 255) are included. *)
Theorem max_threshold_only_255_opaque : forall (alpha : AlphaVal),
  valid_byte alpha ->
  (is_pixel_opaque alpha 255 = true <-> alpha = 255).
Proof.
  intros alpha Hvalid.
  unfold valid_byte in Hvalid.
  rewrite is_pixel_opaque_iff.
  unfold is_pixel_opaque_prop.
  lia.
Qed.

(** For any threshold > 255 (e.g., strict threshold 255 shifted to cutoff 256),
    no valid byte pixel is opaque. *)
Theorem above_max_threshold_none_opaque : forall (alpha threshold : Z),
  valid_byte alpha ->
  threshold > 255 ->
  is_pixel_opaque alpha threshold = false.
Proof.
  intros alpha threshold Hvalid Hthresh.
  unfold valid_byte in Hvalid.
  rewrite is_pixel_opaque_false_iff.
  lia.
Qed.

(** *** Theorem 6: Bridging Strict W3C Semantics and Cutoff Semantics
    In integer arithmetic, (alpha > strict_t) is strictly equivalent to
    (alpha >= strict_t + 1). *)
Theorem strict_to_inclusive_cutoff_bridge : forall (alpha strict_t : Z),
  is_pixel_opaque_strict alpha strict_t = is_pixel_opaque alpha (strict_t + 1).
Proof.
  intros alpha strict_t.
  unfold is_pixel_opaque_strict, is_pixel_opaque.
  destruct (strict_t <? alpha) eqn:E1; destruct (strict_t + 1 <=? alpha) eqn:E2; auto.
  - rewrite Z.ltb_lt in E1. rewrite Z.leb_gt in E2. lia.
  - rewrite Z.ltb_ge in E1. rewrite Z.leb_le in E2. lia.
Qed.

(** *** Theorem 7: Scanline Opacity Count Bounds and Threshold Monotonicity *)
Theorem count_opaque_pixels_bounded : forall (line : Scanline) (threshold : ThresholdVal),
  (count_opaque_pixels line threshold <= length line)%nat.
Proof.
  induction line as [| a rest IH]; intros threshold; simpl.
  - lia.
  - destruct (is_pixel_opaque a threshold); simpl; specialize (IH threshold); lia.
Qed.

Theorem count_opaque_pixels_antitone_threshold : forall (line : Scanline) (t1 t2 : ThresholdVal),
  t1 <= t2 ->
  (count_opaque_pixels line t2 <= count_opaque_pixels line t1)%nat.
Proof.
  induction line as [| a rest IH]; intros t1 t2 Hle; simpl.
  - lia.
  - specialize (IH t1 t