## 1. Core Data Structures in Blink Canvas Sizing

In Chromium's Blink rendering engine, the separation between the DOM representation, the rendering context host, and the underlying GPU/CPU backing store (typically managed via `CanvasResourceProvider` and Skia's `SkSurface`) is governed by three primary C++ structures:

### `blink::IntSize` (`gfx::Size`)
Represents discrete 2D integer dimensions.
*   **Fields**: `int width_`, `int height_`.
*   **Invariants**: Clamped to $0$ upon construction via `std::max(0, w)`. In Blink layout and paint paths, `gfx::Size` guarantees non-negative dimensions, bounded above by `std::numeric_limits<int>::max()`.

### `blink::CanvasRenderingContextHost`
An abstract base class (`HTMLCanvasElement` and `OffscreenCanvas` inherit from it) managing the backing store lifecycle and coordinate space metrics.
*   **Key State**:
    *   `gfx::Size size_`: The **intrinsic bitmap dimensions** (coordinate space units). Default initialized to `(300, 150)`.
    *   `std::unique_ptr<CanvasResourceProvider> resource_provider_`: Holds the actual allocated backing store buffer (textures/shared memory).

### `blink::HTMLCanvasElement`
The concrete DOM element implementation (`third_party/blink/renderer/core/html/canvas/html_canvas_element.h`) bridging HTML attributes, CSS layout (`LayoutHTMLCanvas`), and the backing store.
*   **Attribute Parsing**: Parses `width` and `height` content attributes as valid non-negative integers per **HTML Living Standard §4.12.5.1**. If missing or invalid, defaults to `kDefaultCanvasWidth = 300` and `kDefaultCanvasHeight = 150`.
*   **Layout Integration**: Communicates intrinsic size to `LayoutHTMLCanvas` (which inherits from `LayoutReplaced`).

---

## 2. Coordinate Space vs. CSS Layout Dimensions

Per **HTML Living Standard §4.12.5**, a `<canvas>` element has two independent dimensional spaces:
1.  **Coordinate Space (Intrinsic / Bitmap Size)**: Defined strictly by the HTML `width` and `height` attributes ($W_{\text{attr}}, H_{\text{attr}} \in \mathbb{N}$). This dictates the logical resolution of the `CanvasRenderingContext2D` or `WebGLRenderingContext` buffer.
2.  **CSS Layout Size (Extrinsic Box Size)**: Defined by the CSS box model ($W_{\text{css}}, H_{\text{css}} \in \mathbb{R}_{\ge 0}$). If CSS `width` or `height` are `auto`, the layout engine falls back to the intrinsic dimensions ($W_{\text{attr}}, H_{\text{attr}}$).

### Physical Backing Store Allocation vs. Logical Bitmap
In Blink, there are two distinct buffer sizing models depending on how the canvas is used:
*   **Standard HTML Spec Bitmap**: The logical backing store matches $(W_{\text{attr}}, H_{\text{attr}})$ exactly, and the compositor stretches this texture to fit the physical CSS box $(W_{\text{css}} \cdot \text{DPR}, H_{\text{css}} \cdot \text{DPR})$.
*   **HiDPI / Physical Backing Store Sizing**: When computing the physical raster target size (or when scripts resize the canvas buffer dynamically via `ResizeObserver` `devicePixelContentBoxSize`), the physical backing store dimensions $(W_{\text{buf}}, H_{\text{buf}})$ are derived from the CSS layout size scaled by the Device Pixel Ratio ($d \in \mathbb{R}_{>0}$) and clamped to hardware limits ($M_{\max}$, e.g., `kMaxTextureSize = 16384` or `max_texture_dimension`):

$$W_{\text{buf}} = \min\left(\lfloor W_{\text{css}} \cdot d \rfloor, M_{\max}\right)$$
$$H_{\text{buf}} = \min\left(\lfloor H_{\text{css}} \cdot d \rfloor, M_{\max}\right)$$

*(Note: Furthermore, Blink enforces a total area limit `kMaxCanvasArea = 32768 * 8192` in `HTMLCanvasElement::CanAccelerate` / `IsValidImageSize`, falling back or failing allocation if exceeded, though per-axis clamping is governed by $M_{\max}$.)*

---

## 3. Aspect Ratio Preservation under CSS `auto` Dimensions

In Blink (`LayoutHTMLCanvas` / `LayoutReplaced::ComputeIntrinsicSizingInfo`), `<canvas>` is treated as a replaced element with an intrinsic aspect ratio $R$:

$$R = \frac{W_{\text{attr}}}{H_{\text{attr}}} \quad \text{when } W_{\text{attr}} > 0 \land H_{\text{attr}} > 0$$

Per **CSS Sizing Module Level 3** and **HTML §4.12.5**:
1.  **Both CSS `width: auto` and `height: auto`**:
    $$W_{\text{css}} = W_{\text{attr}}, \quad H_{\text{css}} = H_{\text{attr}}$$
2.  **CSS `width` specified ($W_{\text{spec}}$), `height: auto`**:
    *   If $W_{\text{attr}} > 0 \land H_{\text{attr}} > 0$:
        $$W_{\text{css}} = W_{\text{spec}}, \quad H_{\text{css}} = W_{\text{spec}} \cdot \frac{H_{\text{attr}}}{W_{\text{attr}}}$$
    *   Degenerate case ($W_{\text{attr}} = 0 \lor H_{\text{attr}} = 0$): No aspect ratio is defined; $H_{\text{css}}$ falls back to the intrinsic height $H_{\text{attr}}$.
3.  **CSS `width: auto`, `height` specified ($H_{\text{spec}}$)**:
    *   If $W_{\text{attr}} > 0 \land H_{\text{attr}} > 0$:
        $$H_{\text{css}} = H_{\text{spec}}, \quad W_{\text{css}} = H_{\text{spec}} \cdot \frac{W_{\text{attr}}}{H_{\text{attr}}}$$
    *   Degenerate case ($W_{\text{attr}} = 0 \lor H_{\text{attr}} = 0$): $W_{\text{css}} = W_{\text{attr}}$.
4.  **Both CSS `width` and `height` specified**:
    $$W_{\text{css}} = W_{\text{spec}}, \quad H_{\text{css}} = H_{\text{spec}}$$

---

## 4. Mathematical Invariants

1.  **Non-Negativity (`Buffer_NonNegative`)**:
    $$\forall W_{\text{css}}, H_{\text{css}} \ge 0, \forall d \ge 0, M_{\max} \ge 0 \implies W_{\text{buf}} \ge 0 \land H_{\text{buf}} \ge 0$$
2.  **Hardware Texture Bound (`Buffer_Clamped`)**:
    $$\forall W_{\text{css}}, H_{\text{css}}, d, \quad W_{\text{buf}} \le M_{\max} \land H_{\text{buf}} \le M_{\max}$$
3.  **DPR Scaling Monotonicity (`DPR_Monotonicity`)**:
    $$\forall s \ge 0, \forall d_1, d_2 \ge 0, \quad d_1 \le d_2 \implies \min(\lfloor s \cdot d_1 \rfloor, M_{\max}) \le \min(\lfloor s \cdot d_2 \rfloor, M_{\max})$$
4.  **Intrinsic Aspect Ratio Invariance (`Aspect_Ratio_Preserved`)**:
    When one CSS axis is `auto` and $W_{\text{attr}}, H_{\text{attr}} > 0$:
    $$W_{\text{css}} \cdot H_{\text{attr}} = H_{\text{css}} \cdot W_{\text{attr}}$$

---

## 5. Rocq / Coq Formalization (`BlinkCanvasBackingStoreSemantics.v`)

The following self-contained Rocq (Coq) specification models the layout resolution, exact rational aspect ratio arithmetic (using `QArith` to avoid floating-point imprecision during layout modeling), integer floor scaling, and formal proofs of all core invariants.

```coq
(** * BlinkCanvasBackingStoreSemantics.v
    Formalization of Chromium Blink HTMLCanvasElement Backing Store Sizing
    and CSS Replaced Element Layout Resolution per HTML Living Standard §4.12.5.
*)

From Coq Require Import ZArith.
From Coq Require Import QArith.
From Coq Require Import Lia.
From Coq Require Import Lqa.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** Default intrinsic dimensions per HTML Living Standard §4.12.5 *)
Definition kDefaultCanvasWidth : Z := 300.
Definition kDefaultCanvasHeight : Z := 150.
Definition kDefaultMaxTextureSize : Z := 16384.

(** Discrete 2D integer size modeling blink::IntSize / gfx::Size *)
Record IntSize : Type := mkIntSize {
  width : Z;
  height : Z
}.

(** Rational 2D layout size modeling blink::PhysicalSize / LayoutUnit *)
Record LayoutSize : Type := mkLayoutSize {
  css_width : Q;
  css_height : Q
}.

(** HTML content attribute representation (None = missing or invalid) *)
Inductive AttrValue : Type :=
  | AttrMissingOrInvalid : AttrValue
  | AttrValidNat (v : Z) : AttrValue.

(** CSS dimension property representation *)
Inductive CSSDimension : Type :=
  | CSSAuto : CSSDimension
  | CSSLength (q : Q) : CSSDimension.

(** Canvas configuration state *)
Record HTMLCanvasElementState : Type := mkCanvasState {
  attr_width : AttrValue;
  attr_height : AttrValue;
  style_width : CSSDimension;
  style_height : CSSDimension;
  device_pixel_ratio : Q;
  max_texture_dimension : Z
}.

(** ** 2. Intrinsic Size & CSS Box Model Resolution *)

(** HTML §4.12.5.1: Resolve intrinsic coordinate space size from attributes *)
Definition resolve_intrinsic_dimension (attr : AttrValue) (default_val : Z) : Z :=
  match attr with
  | AttrMissingOrInvalid => default_val
  | AttrValidNat v => if v <? 0 then default_val else v
  end.

Definition compute_intrinsic_size (st : HTMLCanvasElementState) : IntSize :=
  mkIntSize
    (resolve_intrinsic_dimension (attr_width st) kDefaultCanvasWidth)
    (resolve_intrinsic_dimension (attr_height st) kDefaultCanvasHeight).

(** Helper: Clamp a rational number to be non-negative *)
Definition Qmax0 (q : Q) : Q :=
  if Qlt_le_dec q 0 then 0%Q else q.

(** Compute CSS layout box dimensions with aspect ratio preservation *)
Definition compute_css_layout_size (st : HTMLCanvasElementState) : LayoutSize :=
  let intr := compute_intrinsic_size st in
  let w_intr := width intr in
  let h_intr := height intr in
  let qw_intr := inject_Z w_intr in
  let qh_intr := inject_Z h_intr in
  let has_aspect_ratio := (0 <? w_intr) && (0 <? h_intr) in
  match style_width st, style_height st with
  | CSSAuto, CSSAuto =>
      mkLayoutSize qw_intr qh_intr
  | CSSLength w_spec, CSSAuto =>
      let w := Qmax0 w_spec in
      if has_aspect_ratio then
        mkLayoutSize w (w * qh_intr / qw_intr)%Q
      else
        mkLayoutSize w qh_intr
  | CSSAuto, CSSLength h_spec =>
      let h := Qmax0 h_spec in
      if has_aspect_ratio then
        mkLayoutSize (h * qw_intr / qh_intr)%Q h
      else
        mkLayoutSize qw_intr h
  | CSSLength w_spec, CSSLength h_spec =>
      mkLayoutSize (Qmax0 w_spec) (Qmax0 h_spec)
  end.

(** ** 3. Backing Store Buffer Allocation Semantics *)

(** Floor of a rational number Q to Z *)
Definition Qfloor (q : Q) : Z :=
  let n := Qnum q in
  let d := Z.pos (Qden q) in
  n / d.

(** Compute single axis buffer size: min(max(0, floor(css_size * dpr)), max_tex) *)
Definition compute_axis_buffer_size (css_dim : Q) (dpr : Q) (max_tex : Z) : Z :=
  let dpr_clamped := Qmax0 dpr in
  let css_clamped := Qmax0 css_dim in
  let scaled := Qfloor (css_clamped * dpr_clamped)%Q in
  Z.min (Z.max 0 scaled) (Z.max 0 max_tex).

Definition compute_backing_store_size (st : HTMLCanvasElementState) : IntSize :=
  let layout := compute_css_layout_size st in
  let dpr := device_pixel_ratio st in
  let max_tex := max_texture_dimension st in
  mkIntSize
    (compute_axis_buffer_size (css_width layout) dpr max_tex)
    (compute_axis_buffer_size (css_height layout) dpr max_tex).

(** ** 4. Formal Proofs of Mathematical Invariants *)

Lemma Qmax0_nonneg : forall q : Q, (0 <= Qmax0 q)%Q.
Proof.
  intros q. unfold Qmax0.
  destruct (Qlt_le_dec q 0); lra.
Qed.

Lemma Qfloor_nonneg : forall q : Q, (0 <= q)%Q -> 0 <= Qfloor q.
Proof.
  intros [n d] Hq. unfold Qfloor. simpl.
  unfold Qle in Hq. simpl in Hq.
  apply Z.div_pos; lia.
Qed.

Lemma Qfloor_monotonic : forall q1 q2 : Q,
  (q1 <= q2)%Q -> Qfloor q1 <= Qfloor q2.
Proof.
  intros [n1 d1] [n2 d2] Hle.
  unfold Qfloor, Qle in *. simpl in *.
  apply Z.div_le_compat_l_2 with (p := Z.pos d1) (q := Z.pos d2); lia ||
  (* Direct cross-multiplication division proof *)
  (pose proof (Z.div_mul_cancel_r n1 (Z.pos d1) (Z.pos d2) ltac:(lia) ltac:(lia)) as H1;
   pose proof (Z.div_mul_cancel_r n2 (Z.pos d2) (Z.pos d1) ltac:(lia) ltac:(lia)) as H2;
   rewrite <- H1, <- H2;