# Formal Verification Report: Shape Detection API Bounding Box Dimension Non-Negativity

**Agent Identifier:** Formal Verification Agent 668  
**Specialization:** Web Platform File System, Streams, Shape Detection, and Platform Totality in Chromium Blink  
**Target Source:** `third_party/blink/renderer/modules/shape_detection/shape_detector.cc` (and subclasses `face_detector.cc`, `barcode_detector_statics.cc`, `text_detector.cc`)  
**Specification:** WICG Accelerated Shape Detection in Images §3 (FaceDetector, BarcodeDetector, TextDetector) & W3C Geometry Interfaces Module Level 1  
**Formal Theory Target:** `BlinkShapeDetectionBoundingBoxSemantics.v`  
**Mathematical Property:** $\forall r \in \text{DetectedBoundingBox},\; \text{rect\_valid}(r) \iff (r.\text{width} \ge 0 \land r.\text{height} \ge 0)$

---

## 1. Normative W3C / WICG Specification Requirements

The Accelerated Shape Detection in Images specification (WICG) defines the `FaceDetector`, `BarcodeDetector`, and `TextDetector` interfaces. Each of their respective detection algorithms resolves a Promise with a sequence of dictionary objects (`DetectedFace`, `DetectedBarcode`, `DetectedText`), each containing a `boundingBox` member of type `DOMRectReadOnly`.

### 1.1 Shape Detection API §3 Normative Requirements
In WICG Shape Detection API:
* **§3.1.2 `DetectedFace` Dictionary:**
  ```webidl
  dictionary DetectedFace {
    required DOMRectReadOnly boundingBox;
    required sequence<Landmark>? landmarks;
  };
  ```
* **§3.2.2 `DetectedBarcode` Dictionary:**
  ```webidl
  dictionary DetectedBarcode {
    required DOMRectReadOnly boundingBox;
    required DOMString rawValue;
    required BarcodeFormat format;
    required sequence<Point2D> cornerPoints;
  };
  ```
* **§3.3.2 `DetectedText` Dictionary:**
  ```webidl
  dictionary DetectedText {
    required DOMRectReadOnly boundingBox;
    required DOMString rawValue;
    required sequence<Point2D> cornerPoints;
  };
  ```

For all three interfaces, the specification normatively mandates that `boundingBox` represents an axis-aligned rectangle localized within the `ImageBitmapSource` coordinate space, where the rectangle's dimensions correspond to the extent of the detected feature along the X and Y axes. By geometric definition of an image sub-region, the extent (width and height) of a detected feature cannot be negative:
$$\text{width} \ge 0 \quad \land \quad \text{height} \ge 0$$

### 1.2 Interaction with W3C Geometry Interfaces Module Level 1
In W3C Geometry Interfaces §2.1 (`DOMRectReadOnly`), a rectangle is parameterized by origin $(x, y)$ and dimensions $(\text{width}, \text{height})$. While `DOMRectReadOnly.fromRect()` permits negative width and height in general CSS/SVG constructions (causing `left = min(x, x + width)` and `right = max(x, x + width)`), the Shape Detection API requires the `boundingBox` attributes `width` and `height` themselves to be non-negative so that:
1. $r.\text{left} = r.x$ and $r.\text{top} = r.y$.
2. $r.\text{right} = r.x + r.\text{width}$ and $r.\text{bottom} = r.y + r.\text{height}$.
3. Degenerate or inverted rectangles from underlying OS/hardware vision APIs (e.g., Android Google Play Services Vision, macOS Vision framework, Windows Media FaceAnalysis) cannot violate renderer geometry invariants when deserialized across the Mojo IPC boundary into Blink.

---

## 2. Chromium Blink Implementation & Invariants

In Chromium's multi-process architecture, shape detection execution occurs in the GPU or Utility process (via `shape_detection::mojom`), returning results to the Blink renderer process.

### 2.1 Architecture of `shape_detector.cc` and Subclasses
`third_party/blink/renderer/modules/shape_detection/shape_detector.cc` provides the base image extraction pipeline (`ShapeDetector::detect`), decoding `ImageBitmapSource` instances (such as `HTMLImageElement`, `HTMLVideoElement`, `HTMLCanvasElement`, `OffscreenCanvas`, `ImageBitmap`, or `Blob`) into an `SkBitmap` and dispatching it via `DoDetect`.

When the Mojo callback returns to the renderer in the concrete detectors (`FaceDetector::OnDetectFaces`, `BarcodeDetector::OnDetectBarcodes`, `TextDetector::OnDetectText`), the Mojo structs contain a `::gfx::RectF bounding_box` field mapped via StructTraits from `gfx.mojom.RectF`.

```cpp
// Conceptual Blink conversion in OnDetect* callbacks:
DOMRectReadOnly* bounding_box = DOMRectReadOnly::Create(
    face->bounding_box.x(),
    face->bounding_box.y(),
    face->bounding_box.width(),
    face->bounding_box.height());
```

### 2.2 The Two-Tier Non-Negativity Invariant
Chromium enforces `rect_valid(r)` across the Mojo and `gfx::RectF` boundary through two mechanisms:

1. **Mojo Deserialization Guard (`ui/gfx/geometry/mojom/geometry_mojom_traits.cc`):**
   ```cpp
   bool StructTraits<gfx::mojom::RectFDataView, gfx::RectF>::Read(
       gfx::mojom::RectFDataView data,
       gfx::RectF* out) {
     if (data.width() < 0 || data.height() < 0)
       return false;
     out->SetRect(data.x(), data.y(), data.width(), data.height());
     return true;
   }
   ```
   If an untrusted or buggy backend produces a negative dimension, Mojo deserialization fails immediately (`return false`), rejecting the message before `OnDetect*` is ever invoked in Blink.

2. **`gfx::RectF` Clamping Invariant (`ui/gfx/geometry/rect_f.h` & `size_f.h`):**
   Even when constructed directly in C++ via `gfx::RectF(x, y, width, height)`, the `gfx::SizeF` constructor clamps dimensions to zero:
   ```cpp
   constexpr SizeF(float width, float height)
       : width_(std::max(0.f, width)), height_(std::max(0.f, height)) {}
   ```
   Subsequently, `DOMRectReadOnly::Create(x, y, width, height)` directly assigns these validated, non-negative `width` and `height` values to the Blink IDL `DOMRectReadOnly` object.

Thus, the Blink execution path forms a total, verified pipeline where both IPC validation and geometric clamping guarantee $\text{width} \ge 0 \land \text{height} \ge 0$.

---

## 3. Formal Specification in Rocq / Coq

We model coordinates and dimensions over $\mathbb{Z}$ (representing fixed-point or discrete IEEE-754 finite sub-pixel coordinates scaled to integer units, avoiding NaN/Infinity which are rejected by Mojo and WebIDL finite `unrestricted double` / `float` invariants).

Below is the complete, self-contained formalization in `BlinkShapeDetectionBoundingBoxSemantics.v`.

```coq
(* ========================================================================== *)
(* Formal Theory: BlinkShapeDetectionBoundingBoxSemantics.v                   *)
(* Target: third_party/blink/renderer/modules/shape_detection/shape_detector  *)
(* Specification: WICG Shape Detection API §3 & W3C Geometry Interfaces       *)
(* ========================================================================== *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(* -------------------------------------------------------------------------- *)
(* 1. Core Geometric and WebIDL Data Types                                    *)
(* -------------------------------------------------------------------------- *)

(** Raw rectangle payload arriving over Mojo IPC (gfx.mojom.RectFDataView) *)
Record MojoRawRect : Type := mkMojoRawRect {
  raw_x : Z;
  raw_y : Z;
  raw_width : Z;
  raw_height : Z
}.

(** Validated Chromium geometry rectangle (gfx::RectF) *)
Record GfxRectF : Type := mkGfxRectF {
  gfx_x : Z;
  gfx_y : Z;
  gfx_width : Z;
  gfx_height : Z
}.

(** Blink WebIDL DOMRectReadOnly (third_party/blink/renderer/core/geometry) *)
Record DOMRectReadOnly : Type := mkDOMRectReadOnly {
  dom_x : Z;
  dom_y : Z;
  dom_width : Z;
  dom_height : Z
}.

(** Shape Detection API §3 Detected Feature Variants *)
Inductive ShapeKind : Type :=
  | KindFace
  | KindBarcode
  | KindText.

(** Detected shape object returned in Blink Promise resolution *)
Record DetectedShape : Type := mkDetectedShape {
  shape_kind : ShapeKind;
  bounding_box : DOMRectReadOnly
}.

(** ImageBitmapSource dimensions decoded by ShapeDetector::detect *)
Record ImageBitmapDimensions : Type := mkImageDims {
  img_width : Z;
  img_height : Z
}.

(* -------------------------------------------------------------------------- *)
(* 2. W3C Geometry Interfaces §2.1 Derived Attributes                         *)
(* -------------------------------------------------------------------------- *)

Definition dom_top (r : DOMRectReadOnly) : Z :=
  Z.min (dom_y r) (dom_y r + dom_height r).

Definition dom_bottom (r : DOMRectReadOnly) : Z :=
  Z.max (dom_y r) (dom_y r + dom_height r).

Definition dom_left (r : DOMRectReadOnly) : Z :=
  Z.min (dom_x r) (dom_x r + dom_width r).

Definition dom_right (r : DOMRectReadOnly) : Z :=
  Z.max (dom_x r) (dom_x r + dom_width r).

(* -------------------------------------------------------------------------- *)
(* 3. Specification Predicates                                                *)
(* -------------------------------------------------------------------------- *)

(** Mathematical Property: rect_valid(r) = (r.width >= 0 /\ r.height >= 0) *)
Definition rect_valid (r : DOMRectReadOnly) : Prop :=
  dom_width r >= 0 /\ dom_height r >= 0.

(** Boolean decision procedure for rect_valid *)
Definition rect_valid_b (r : DOMRectReadOnly) : bool :=
  (dom_width r >=? 0) && (dom_height r >=? 0).

(** Predicate over a detected shape *)
Definition shape_valid (s : DetectedShape) : Prop :=
  rect_valid (bounding_box s).

(** Predicate overgfx::RectF *)
Definition gfx_rect_valid (r : GfxRectF) : Prop :=
  gfx_width r >= 0 /\ gfx_height r >= 0.

(* -------------------------------------------------------------------------- *)
(* 4. Chromium Blink Implementation Semantics                                 *)
(* -------------------------------------------------------------------------- *)

(** gfx::SizeF clamping semantics: std::max(0, d) *)
Definition clamp_non_negative (d : Z) : Z :=
  Z.max 0 d.

(** Direct C++ construction of gfx::RectF clamps width and height to >= 0 *)
Definition gfx_rect_create (x y w h : Z) : GfxRectF :=
  mkGfxRectF x y (clamp_non_negative w) (clamp_non_negative h).

(** Mojo StructTraits<gfx::mojom::RectFDataView, gfx::RectF>::Read *)
Definition mojo_deserialize_rect (raw : MojoRawRect) : option GfxRectF :=
  if (raw_width raw <? 0) || (raw_height raw <? 0) then
    None
  else
    Some (gfx_rect_create (raw_x raw) (raw_y raw) (raw_width raw) (raw_height raw)).

(** DOMRectReadOnly::Create in Blink OnDetect* callbacks *)
Definition blink_create_dom_rect (g : GfxRectF) : DOMRectReadOnly :=
  mkDOMRectReadOnly (gfx_x g) (gfx_y g) (gfx_width g) (gfx_height g).

(** Complete ShapeDetector IPC-to-DOM conversion for a single detected item *)
Definition blink_convert_detected_shape
    (k : ShapeKind) (raw : MojoRawRect) : option DetectedShape :=
  match mojo_deserialize_rect raw with
  | None => None
  | Some g => Some (mkDetectedShape k (blink_create_dom_rect g))
  end.

(** Batch deserialization of Mojo sequence<Detected*> *)
Fixpoint blink_convert_shape_sequence
    (k : ShapeKind) (raws : list MojoRawRect) : option (list DetectedShape) :=
  match raws with
  | [] => Some []
  | r :: rest =>
      match blink_convert_detected_shape k r, blink_convert_shape_sequence k rest with
      | Some s, Some ss => Some (s :: ss)
      | _, _ => None
      end
  end.

(** Fallback/clamped pipeline used when raw coordinates are sanitized in-place *)
Definition blink_clamped_dom_rect (raw : MojoRawRect) : DOMRectReadOnly :=
  blink_create_dom_rect
    (gfx_rect_create (raw_x raw) (raw_y raw) (raw_width raw) (raw_height raw)).

(** Crop / intersection of a bounding box with the decoded SkBitmap bounds *)
Definition intersect_with_bitmap
    (img : ImageBitmapDimensions) (g : GfxRectF) : GfxRectF :=
  let x1 := Z.max 0 (gfx_x g) in
  let y1 := Z.max 0 (gfx_y g) in
  let x2 := Z.min (Z.max 0 (img_width img)) (gfx_x g + gfx_width g) in
  let y2 := Z.min (Z.max 0 (img_height img)) (gfx_y g + gfx_height g) in
  gfx_rect_create x1 y1 (x2 - x1) (y2 - y1).
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

We now state and prove the core verification theorems establishing `rect_valid(r)` across all execution paths in `shape_detector.cc` and its concrete subclasses, with zero `Admitted` statements.

```coq
(* -------------------------------------------------------------------------- *)
(* 5. Formal Verification Theorems and Proofs                                 *)
(* -------------------------------------------------------------------------- *)

(** Theorem 1: Reflection equivalence between rect_valid and rect_valid_b. *)
Theorem rect_valid_reflect :
  forall (r : DOMRectReadOnly),
    rect_valid r <-> rect_valid_b r = true.
Proof.
  intros r.
  unfold rect_valid, rect_valid_b.
  rewrite andb_