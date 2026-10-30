## 1. Core Data Structures in Blink SVG Layout

In Chromium’s Blink rendering engine, the interface between the HTML/CSS layout tree (LayoutNG) and the internal SVG coordinate system is governed by `LayoutSVGRoot` and its geometric primitives. 

### `LayoutSVGRoot`
Defined in `third_party/blink/renderer/core/layout/svg/layout_svg_root.h`, `LayoutSVGRoot` inherits from `LayoutReplaced`. This design treats an outer `<svg>` element as a replaced element (like `<img>` or `<video>`) with respect to its CSS container, while acting as a coordinate-system root for its `LayoutSVGModelObject` and `LayoutSVGShape` descendants.

Key member fields and responsibilities:
* **`local_to_border_box_transform_` (`AffineTransform`)**: Stores the computed $3 \times 3$ (represented as a 6-element array $[a, b, c, d, e, f]$) affine transformation matrix that maps coordinates from the SVG’s local user space (defined by `viewBox`) into the CSS physical border box space.
* **`intrinsic_sizing_info_` (`IntrinsicSizingInfo`)**: Caches the natural width, natural height, and aspect ratio extracted from the underlying `SVGSVGElement` attributes and `viewBox`.
* **`is_layout_size_changed_` (`bool`)**: Tracks whether the CSS viewport dimensions mutated during the current LayoutNG pass, requiring child relative lengths (percentages) and transformations to be dirtied and recomputed.

### `SVGViewSpec` / `FloatRect` (`viewBox`)
Defined across `third_party/blink/renderer/core/svg/svg_view_spec.h` and `svg_fit_to_view_box.h`, the `viewBox` attribute is parsed into an `SVGRect` (wrapping a `gfx::RectF` / `FloatRect`).
* **`x_`, `y_`**: The minimum $x$ and $y$ coordinates ($\text{min-x}, \text{min-y}$) in user space.
* **`width_`, `height_`**: The span of the coordinate system ($\text{vb-width}, \text{vb-height}$).
* **Validity Flags**: Tracked via `SVGAnimatedRect` status flags (`IsSpecified()`, `IsValid()`). A `viewBox` with $\text{width} < 0$ or $\text{height} < 0$ is flagged invalid at parse time; a `viewBox` with $\text{width} = 0$ or $\text{height} = 0$ is structurally valid but disables rendering of the subtree.

### `SVGPreserveAspectRatio`
Defined in `third_party/blink/renderer/core/svg/svg_preserve_aspect_ratio.h`, this class encapsulates the parsing and transformation logic of the `preserveAspectRatio` attribute.

```cpp
enum SVGPreserveAspectRatioType {
  kSvgPreserveaspectratioUnknown = 0,
  kSvgPreserveaspectratioNone = 1,
  kSvgPreserveaspectratioXminymin = 2,
  kSvgPreserveaspectratioXmidymin = 3,
  kSvgPreserveaspectratioXmaxymin = 4,
  kSvgPreserveaspectratioXminymid = 5,
  kSvgPreserveaspectratioXmidymid = 6, // Default
  kSvgPreserveaspectratioXmaxymid = 7,
  kSvgPreserveaspectratioXminymax = 8,
  kSvgPreserveaspectratioXmidymax = 9,
  kSvgPreserveaspectratioXmaxymax = 10
};

enum SVGMeetOrSliceType {
  kSvgMeetorsliceUnknown = 0,
  kSvgMeetorsliceMeet = 1, // Default
  kSvgMeetorsliceSlice = 2
};
```
The core method `SVGPreserveAspectRatio::ComputeTransform(...)` takes the viewBox dimensions and viewport dimensions and outputs an `AffineTransform`.

---

## 2. Sizing Calculation: Intrinsic vs. CSS Specified

Blink reconciles W3C SVG 2 Section 7.12 ("Sizing of outermost svg elements") with CSS Sizing Module Level 3 via `LayoutSVGRoot::UnscaledIntrinsicSizingInfo`.

```
                  +---------------------------------------+
                  |        SVGSVGElement Attributes       |
                  |  width | height | viewBox="x y w h"   |
                  +--------+--------+----------+----------+
                           |                   |
            +--------------+                   +--------------+
            v                                                 v
  [Intrinsic Dimensions]                             [Intrinsic Aspect Ratio]
  If length is fixed (px, em, etc.):                 1. If width & height are fixed:
    intrinsic_w = width                                   AR = width / height (if no viewBox)
    intrinsic_h = height                             2. Else if viewBox is valid (w>0, h>0):
  If percentage (%) or 'auto':                            AR = vb_w / vb_h
    intrinsic_w/h = None (0)                         3. Else: AR = None
            |                                                 |
            +-----------------------+-------------------------+
                                    |
                                    v
                  +---------------------------------------+
                  |   CSS Default Sizing Algorithm        |
                  |   (LayoutReplaced / LayoutNG)         |
                  |                                       |
                  |  1. CSS Specified w & h -> Use both   |
                  |  2. Only w specified -> h = w / AR    |
                  |  3. Only h specified -> w = h * AR    |
                  |  4. Neither specified:                |
                  |     - Resolve from intrinsic w/h & AR |
                  |     - Fallback: 300px by 150px        |
                  +---------------------------------------+
```

### Step 1: Extracting `IntrinsicSizingInfo`
In `LayoutSVGRoot::UnscaledIntrinsicSizingInfo`:
1. **Natural Dimensions (`size`)**: Blink queries the `<svg>` `width` and `height` presentation attributes. If a dimension is a fixed length (e.g., `px`, `pt`, `cm`, `em`), it is resolved to pixels and stored in `sizing_info.size`. If the dimension is `auto` or a percentage (`%`), it yields *no* intrinsic size (`has_width = false` or `has_height = false`).
2. **Intrinsic Aspect Ratio (`aspect_ratio`)**:
   * **Rule A**: If a valid `viewBox` with $\text{vb\_w} > 0$ and $\text{vb\_h} > 0$ is present, the intrinsic aspect ratio is strictly defined by the `viewBox`:
     $$\text{AR} = \frac{\text{vb\_w}}{\text{vb\_h}}$$
   * **Rule B**: If no valid `viewBox` is present, and *both* `width` and `height` are fixed lengths (non-percentage, non-auto) greater than 0, the aspect ratio is derived from the intrinsic dimensions:
     $$\text{AR} = \frac{\text{intrinsic\_w}}{\text{intrinsic\_h}}$$
   * **Rule C**: Otherwise, the element has no intrinsic aspect ratio ($\text{AR} = \emptyset$).

*Note on SVG 2 vs SVG 1.1*: In SVG 2, `width` and `height` on `<svg>` are promoted to **geometry properties** (stylable via CSS). Blink implements this by mapping the attributes into ` ComputedStyle` via `SVGElement::CollectStyleForPresentationAttribute`.

### Step 2: CSS Default Sizing Resolution
LayoutNG (`NGReplacedLayoutAlgorithm` / `LayoutReplaced::ComputeReplacedLogicalWidth/Height`) combines `ComputedStyle` (`width`, `height`, `min-width`, `max-width`, `box-sizing`) with `IntrinsicSizingInfo` to yield the concrete **CSS Content Box** $(W_c, H_c)$:

1. **Both Specified**: If CSS specifies definite `width` and `height`, $W_c = \text{CSS}_w$ and $H_c = \text{CSS}_h$.
2. **One Specified + Aspect Ratio**:
   * If only $W_c$ is definite and $\text{AR} \neq \emptyset$: $H_c = W_c \cdot \frac{1}{\text{AR}}$.
   * If only $H_c$ is definite and $\text{AR} \neq \emptyset$: $W_c = H_c \cdot \text{AR}$.
3. **Neither Specified (Auto Sizing)**:
   * If both intrinsic width and height exist: $W_c = \text{intrinsic\_w}$, $H_c = \text{intrinsic\_h}$.
   * If one intrinsic dimension exists (e.g., $\text{intrinsic\_w}$) and $\text{AR} \neq \emptyset$: $W_c = \text{intrinsic\_w}, H_c = \text{intrinsic\_w} / \text{AR}$.
   * If only $\text{AR} \neq \emptyset$ exists (e.g., `<svg viewBox="0 0 100 50">` with `width: auto; height: auto` in a block context): Blink resolves the inline size ($W_c$) to the available container inline size (stretch-fit), then computes $H_c = W_c / \text{AR}$.
   * **Fallback**: If an axis cannot be resolved via CSS, intrinsic size, or aspect ratio transfer, it falls back to the CSS Default Object Size: **$300\text{px}$ width** and **$150\text{px}$ height**.

---

## 3. `preserveAspectRatio` Mathematical Mapping

Once LayoutNG resolves the physical content box size, we denote the viewport dimensions as $e_w = \text{container\_w}$ and $e_h = \text{container\_h}$. Given a valid `viewBox` $(\text{vb\_x}, \text{vb\_y}, \text{vb\_w}, \text{vb\_h})$ with $\text{vb\_w} > 0$ and $\text{vb\_h} > 0$, `SVGPreserveAspectRatio::ComputeTransform` constructs the user-space-to-viewport transformation.

### Base Scale Factors
The unadjusted directional scale ratios are:
$$\text{scale\_x} = \frac{e_w}{\text{vb\_w}}, \quad \text{scale\_y} = \frac{e_h}{\text{vb\_h}}$$

### Case 1: `align = none` (Non-Uniform Scaling)
The `meetOrSlice` parameter is ignored. The viewBox is stretched anisotropically to fill the viewport:
$$S_x = \text{scale\_x}, \quad S_y = \text{scale\_y}$$
The alignment offsets in viewport space are zero ($\Delta_x = 0, \Delta_y = 0$). To map $(\text{vb\_x}, \text{vb\_y})$ to $(0, 0)$, the translation in viewport pixels is:
$$T_x = -\text{vb\_x} \cdot S_x, \quad T_y = -\text{vb\_y} \cdot S_y$$

### Case 2: `align != none` and `meetOrSlice = meet` (Uniform Containment)
The entire `viewBox` must fit inside the viewport. The uniform scale factor $S$ is the minimum of the directional scales:
$$S = S_x = S_y = \min(\text{scale\_x}, \text{scale\_y})$$

### Case 3: `align != none` and `meetOrSlice = slice` (Uniform Cover)
The viewport must be completely covered by the `viewBox`. The uniform scale factor $S$ is the maximum of the directional scales:
$$S = S_x = S_y = \max(\text{scale\_x}, \text{scale\_y})$$

### Alignment Offsets ($\Delta_x, \Delta_y$) for `meet` and `slice`
When scaling is uniform ($S_x = S_y = S$), the scaled `viewBox` has physical dimensions $(W_{\text{scaled}}, H_{\text{scaled}}) = (\text{vb\_w} \cdot S, \text{vb\_h} \cdot S)$. The leftover (for `meet`) or overflowing (for `slice`) space along each axis is:
$$\text{rem\_w} = e_w - \text{vb\_w} \cdot S, \quad \text{rem\_h} = e_h - \text{vb\_h} \cdot S$$

The viewport-space alignment offset $(\Delta_x, \Delta_y)$ is determined by the X and Y alignment keywords:

| X Alignment | $\Delta_x$ (Viewport Space) | Y Alignment | $\Delta_y$ (Viewport Space) |
| :--- | :--- | :--- | :--- |
| **`XMin`** | $0$ | **`YMin`** | $0$ |
| **`XMid`** | $\frac{e_w - \text{vb\_w} \cdot S}{2}$ | **`YMid`** | $\frac{e_h - \text{vb\_h} \cdot S}{2}$ |
| **`XMax`** | $e_w - \text{vb\_w} \cdot S$ | **`YMax`** | $e_h - \text{vb\_h} \cdot S$ |

### Resulting Affine Matrix Construction
In `SVGPreserveAspectRatio::ComputeTransform`, Blink applies operations on an `AffineTransform` (which post-multiplies matrices). First it scales by $(S_x, S_y)$, then translates in user space, which yields the combined viewport-space translation $(T_x, T_y)$:
$$T_x = \Delta_x - \text{vb\_x} \cdot S_x$$
$$T_y = \Delta_y - \text{vb\_y} \cdot S_y$$

The resulting $3 \times 3$ homogeneous transformation matrix $M_{\text{viewBox}}$ mapping a user-space point $(x_u, y_u)$ to content-box point $(x_c, y_c)$ is:
$$\begin{bmatrix} x_c \\ y_c \\ 1 \end{bmatrix} = \begin{bmatrix} S_x & 0 & \Delta_x - \text{vb\_x} \cdot S_x \\ 0 & S_y & \Delta_y - \text{vb\_y} \cdot S_y \\ 0 & 0 & 1 \end{bmatrix} \begin{bmatrix} x_u \\ y_u \\ 1 \end{bmatrix}$$

---

## 4. Physical Viewport Clipping & Transformed Bounding Rect

### `local_to_border_box_transform_`
In `LayoutSVGRoot::UpdateLayout()`, Blink computes `local_to_border_box_transform_` via `LayoutSVGRoot::BuildLocalToBorderBoxTransform`:

1. Let $(B_L, B_T)$ be the sum of the CSS left border + left padding (`BorderLeft() + PaddingLeft()`) and top border + top padding (`BorderTop() + PaddingTop()`).
2. Let $(e_w, e_h)$ be the physical content box size (`ContentWidth()`, `ContentHeight()`).
3. Initialize `transform` with the border/padding translation:
   $$M_{\text{border}} = \begin{bmatrix} 1 & 0 & B_L \\ 0 & 1 & B_T \\ 0 & 0 & 1 \end{bmatrix}$$
4. Compute the viewBox matrix $M_{\text{viewBox}}$ for $(e_w, e_h)$ using `SVGSVGElement::ViewBoxToViewTransform(e_w,