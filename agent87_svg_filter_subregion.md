### 1. Core Data Structures in Blink SVG Filter Primitive Processing

In Chromium’s Blink rendering engine (specifically under `third_party/blink/renderer/core/svg/` and `platform/graphics/filters/`), SVG filter subregion computation relies on the interaction between the DOM representation and the graphics platform representation:

*   **`SVGFilterPrimitiveStandardAttributes`**: The base DOM class for all SVG filter primitives (`feGaussianBlur`, `feColorMatrix`, `feMerge`, etc.). It inherits from `SVGElement` and manages the standard SVG filter primitive attributes: `x`, `y`, `width`, `height`, and `result`. When these attributes change, it triggers invalidation on the parent `LayoutSVGResourceFilter`.
*   **`SVGFilterBuilder`**: Orchestrates the construction of the filter graph (DAG). It traverses the DOM children of an `<filter>` element, invokes `Build()` on each `SVGFilterPrimitiveStandardAttributes` node, maps string identifiers (`in`, `in2`, `result`) to concrete `FilterEffect` pointers, and resolves the primitive subregions against the parent filter context.
*   **`FilterEffect`**: The platform-level graphics node representing an operation in the filter graph. Relevant state fields include:
    *   `filter_primitive_subregion_` (`gfx::RectF` / `FloatRect`): The resolved subregion in the local coordinate space of the filter.
    *   `absolute_paint_rect_` (`gfx::Rect`): The final device-space/pixel-aligned bounding box used to allocate the backing `SkSurface` or `PaintRecord`.
    *   `clips_to_bounds_` (`bool`): Controls whether the effect explicitly clips its output to the resolved subregion (true by default for standard SVG primitives).
*   **`FloatRect` (`gfx::RectF`)**: Represents a 2D axis-aligned bounding box parameterized by origin $(x, y)$ and dimensions $(w, h)$ in single-precision IEEE 754 floating-point space. It provides geometric primitives such as `Intersect(const FloatRect&)` and `Unite(const FloatRect&)`.

---

### 2. Subregion Calculation: Defaults and Coordinate Spaces

According to W3C Filter Effects Module Level 1 §7 (Filter Primitive Subregion), every filter primitive defines a rectangular region $(x, y, width, height)$ to which its output is clipped.

#### Coordinate Spaces (`primitiveUnits`)
The coordinate system used to interpret the `x`, `y`, `width`, and `height` attributes of a filter primitive is dictated by the parent `<filter>` element’s `primitiveUnits` attribute (`SVGUnitTypes::SVGUnitType`):
1.  **`userSpaceOnUse` (Default)**: Percentages are resolved relative to the current SVG viewport dimensions. Raw numbers represent coordinates in the local user coordinate system active at the time the `<filter>` element is referenced.
2.  **`objectBoundingBox`**: Coordinates and lengths (whether specified as percentages or unitless numbers, where `0.5` is equivalent to `50%`) are resolved as fractions/multiples of the target element's bounding box ($B_{obj} = (x_{obj}, y_{obj}, w_{obj}, h_{obj})$).
    $$\text{Resolved}_{x} = x_{obj} + \text{val}_{x} \cdot w_{obj}, \quad \text{Resolved}_{w} = \text{val}_{w} \cdot w_{obj}$$

*Note: This contrasts with `filterUnits`, which defaults to `objectBoundingBox` and governs the parent `<filter>` region $(-10\%, -10\%, 120\%, 120\%)$.*

#### Default Subregion Inheritance
For any given primitive $P$ with $N$ input effects $\{I_1, \dots, I_N\}$:
*   **0 Inputs ($N = 0$)** (e.g., `feFlood`, `feTurbulence`, `feImage`): The default subregion is the **Filter Region** $R_{\text{filter}}$ itself (i.e., $0\%, 0\%, 100\%, 100\%$ of the parent filter region).
*   **$\ge 1$ Inputs ($N \ge 1$)** (e.g., `feGaussianBlur`, `feComposite`, `feMerge`): The default subregion is the **bounding box union** of the resolved subregions of all referenced input primitives:
    $$R_{\text{default}} = \bigcup_{k=1}^{N} R_{\text{subregion}}(I_k)$$

In Blink (`SVGFilterBuilder::ResolveFilterPrimitiveSubregion`), the engine first computes $R_{\text{default}}$. Then, it inspects the `x`, `y`, `width`, and `height` `SVGLength` attributes on `SVGFilterPrimitiveStandardAttributes`. For each individual attribute:
*   If the attribute is **explicitly specified** in the DOM, Blink resolves the length against the `primitiveUnits` coordinate space and overrides that specific component ($x, y, w,$ or $h$) of $R_{\text{default}}$.
*   If the attribute is **unspecified**, the corresponding component from $R_{\text{default}}$ is retained.

---

### 3. Clipping Filter Primitive Output

During the filter graph preparation and rendering phases (`FilterEffect::DetermineAbsolutePaintRect` and `SkImageFilter` generation), the actual output bounds of a filter primitive are determined by three distinct rectangles:
1.  **Natural Effect Bounds ($R_{\text{natural}}$)**: The unclipped bounding box required to hold the mathematical output of the operation based on its inputs and parameters (e.g., for `feGaussianBlur`, the input bounds expanded by $\lceil 3\sigma \rceil$; for `feOffset`, the input bounds translated by $(dx, dy)$; for `feFlood`, infinite bounds $\mathbb{R}^2$).
2.  **Resolved Primitive Subregion ($R_{\text{subregion}}$)**: The rectangle computed in Section 2, stored in `filter_primitive_subregion_`.
3.  **Parent Filter Region ($R_{\text{filter}}$)**: The master clipping region defined by the `<filter>` element.

#### The Intersection Pipeline
W3C Filter Effects 1 §7 specifies that the primitive subregion acts as a hard clip on the filter primitive’s output, and the filter region acts as a hard clip on the primitive subregion. In Blink, the effective bounding box $R_{\text{out}}$ of a primitive is computed via progressive intersection:

$$R_{\text{clipped\_subregion}} = R_{\text{subregion}} \cap R_{\text{filter}}$$
$$R_{\text{out}} = R_{\text{natural}} \cap R_{\text{clipped\_subregion}} = R_{\text{natural}} \cap R_{\text{subregion}} \cap R_{\text{filter}}$$

If either width or height of $R_{\text{subregion}}$ is negative (invalid per spec) or zero, the intersection yields an empty rectangle ($w=0, h=0$), short-circuiting the rendering of that primitive to a transparent black surface.

---

### 4. Mathematical Invariants

Let $\mathcal{R}$ be the space of valid axis-aligned rectangles $R = [x_1, x_2] \times [y_1, y_2]$ where $x_1 \le x_2$ and $y_1 \le y_2$. Let $\text{Area}(R) = (x_2 - x_1)(y_2 - y_1) \ge 0$.

1.  **Containment Invariant (Subregion & Filter Region Bounds)**:
    For any filter primitive output $R_{\text{out}}$, it is strictly contained within both the resolved primitive subregion and the master filter region:
    $$(R_{\text{out}} \subseteq R_{\text{subregion}}) \land (R_{\text{out}} \subseteq R_{\text{filter}})$$
2.  **Default Inheritance Containment**:
    If a primitive has no explicitly authored subregion attributes ($x, y, w, h = \text{None}$) and all its inputs satisfy the Filter Region Containment Invariant ($\forall k, R_{I_k} \subseteq R_{\text{filter}}$), then its unclipped default subregion is already contained within the filter region:
    $$R_{\text{default}} = \text{Union}(R_{I_1}, \dots, R_{I_n}) \subseteq R_{\text{filter}}$$
3.  **Monotonic Area Reduction**:
    The clipping step is a projection operator that monotonically reduces (or keeps equal) the area of the allocation buffer:
    $$\text{Area}(R_{\text{out}}) \le \min\big(\text{Area}(R_{\text{natural}}),\, \text{Area}(R_{\text{subregion}}),\, \text{Area}(R_{\text{filter}})\big)$$
4.  **Idempotence of Filter Region Clipping**:
    Clipping the output again by the master filter region at the end of the pipeline does not alter the geometry of a valid primitive:
    $$R_{\text{out}} \cap R_{\text{filter}} = R_{\text{out}}$$

---

### 5. Rocq / Coq Formalization (`BlinkSVGFilterSubregionSemantics.v`)

The following complete, self-contained Rocq (Coq) formalization models the geometry over `Q` (rationals, representing exact layout coordinates) using min/max interval bounds to guarantee closure and clean proof automation via `lia` / `lra`.

```coq
(** * BlinkSVGFilterSubregionSemantics.v
    Formal verification of Chromium Blink SVG Filter Subregion clipping 
    and coordinate resolution against W3C Filter Effects Module Level 1 §7. *)

Require Import Coq.QArith.QArith.
Require Import Coq.QArith.Qminmax.
Require Import Coq.Lists.List.
Require Import Coq.micromega.Lia.
Require Import Coq.micromega.Lra.
Import ListNotations.

Open Scope Q_scope.

(** ** 1. Core Geometric Data Structures (FloatRect abstraction) *)

(** We represent a 2D axis-aligned bounding box (FloatRect) by its 
    minimum and maximum coordinates [x0, x1] x [y0, y1]. *)
Record Rect : Type := mkRect {
  x0 : Q;
  y0 : Q;
  x1 : Q;
  y1 : Q
}.

(** A rectangle is well-formed (non-degenerate/valid) if min <= max. *)
Definition wf_rect (r : Rect) : Prop :=
  r.(x0) <= r.(x1) /\ r.(y0) <= r.(y1).

(** Point containment and Rectangle inclusion (subset relation). *)
Definition rect_subset (r1 r2 : Rect) : Prop :=
  r2.(x0) <= r1.(x0) /\ r1.(x1) <= r2.(x1) /\
  r2.(y0) <= r1.(y0) /\ r1.(y1) <= r2.(y1).

(** Width, Height, and Area (clamped to 0 if inverted). *)
Definition width (r : Rect) : Q := Qmax 0 (r.(x1) - r.(x0)).
Definition height (r : Rect) : Q := Qmax 0 (r.(y1) - r.(y0)).
Definition area (r : Rect) : Q := (width r) * (height r).

(** Intersection of two rectangles (FloatRect::Intersect). *)
Definition rect_intersect (r1 r2 : Rect) : Rect :=
  let nx0 := Qmax r1.(x0) r2.(x0) in
  let ny0 := Qmax r1.(y0) r2.(y0) in
  let nx1 := Qmin r1.(x1) r2.(x1) in
  let ny1 := Qmin r1.(y1) r2.(y1) in
  mkRect nx0 ny0 (Qmax nx0 nx1) (Qmax ny0 ny1).

(** Bounding-box union of two rectangles (FloatRect::Unite). *)
Definition rect_union (r1 r2 : Rect) : Rect :=
  mkRect (Qmin r1.(x0) r2.(x0))
         (Qmin r1.(y0) r2.(y0))
         (Qmax r1.(x1) r2.(x1))
         (Qmax r1.(y1) r2.(y1)).

(** ** 2. SVG Filter Coordinate Spaces and Attributes *)

Inductive SVGUnitType : Type :=
  | UserSpaceOnUse
  | ObjectBoundingBox.

(** Represents SVGFilterPrimitiveStandardAttributes (x, y, width, height).
    None indicates the attribute was not specified by the author. *)
Record SubregionAttrs : Type := mkAttrs {
  attr_x : option Q;
  attr_y : option Q;
  attr_w : option Q;
  attr_h : option Q
}.

(** Resolves a single coordinate or length in primitiveUnits. *)
Definition resolve_coord (u : SVGUnitType) (origin span val : Q) : Q :=
  match u with
  | UserSpaceOnUse => val
  | ObjectBoundingBox => origin + val * span
  end.

Definition resolve_length (u : SVGUnitType) (span val : Q) : Q :=
  match u with
  | UserSpaceOnUse => val
  | ObjectBoundingBox => val * span
  end.

(** ** 3. Subregion Calculation and Output Clipping (W3C §7 & Blink) *)

(** Compute default subregion from input primitive subregions.
    If no inputs exist, defaults to the parent filter region. *)
Fixpoint union_inputs (filter_region : Rect) (inputs : list Rect) : Rect :=
  match inputs with
  | [] => filter_region
  | [r] => r
  | r :: rest => rect_union r (union_inputs filter_region rest)
  end.

(** Applies author-specified x, y, width, height overrides over the default box. *)
Definition resolve_primitive_subregion
  (u : SVGUnitType)
  (target_bbox : Rect)
  (filter_region : Rect)
  (inputs : list Rect)
  (attrs : SubregionAttrs) : Rect :=
  let def := union_inputs filter_region inputs in
  let def_w := def.(x1) - def.(x0) in
  let def_h := def.(y1) - def.(y0) in
  let obj_w := target_bbox.(x1) - target_bbox.(x0) in
  let obj_h := target_bbox.(y1) - target_bbox.(y0) in
  let rx := match attrs.(attr_x) with
            | Some v => resolve_coord u target_bbox.(x0) obj_w v
            | None => def.(x0)
            end in
  let ry := match attrs.(attr_y) with
            | Some v => resolve_coord u target_bbox.(y0) obj_h v
            | None => def.(y0)
            end in
  let rw := match attrs.(attr_w) with
            | Some v => Qmax 0 (resolve_length u obj_w v)
            | None => Qmax 0 def_w
            end in
  let rh := match attrs.(attr_h) with
            | Some v => Qmax 0 (resolve_length u obj_h v)
            | None => Qmax 0 def_h
            end in
  mkRect rx ry (rx + rw) (ry + rh).

