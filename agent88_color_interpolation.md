### 1. Core Data Structures in Blink Color Representation

In Chromium Blink (`third_party/blink/renderer/platform/graphics/color.h`), color representation transitioned from legacy 8-bit integer storage to wide-gamut floating-point representations to satisfy CSS Color 4 specifications.

#### `RGBA32` (Legacy Storage)
Historically, Blink packed colors into a 32-bit unsigned integer (`typedef uint32_t RGBA32;`) using `SkColor` conventions (ARGB byte ordering: `[31:24] Alpha`, `[23:16] Red`, `[15:8] Green`, `[7:0] Blue`). This is now strictly confined to fast-path legacy sRGB operations and serialization boundaries.

#### `blink::Color`
`blink::Color` is a 16-byte (128-bit) value type capable of lossless representation of out-of-gamut and wide-gamut colors:
*   **Channels (`float param0_`, `param1_`, `param2_`):** Three 32-bit IEEE 754 floating-point values representing color coordinates (e.g., $R, G, B \in [0,1]$, $L \in [0,1], a, b \in [-0.4, 0.4]$ for OKLab, or $H \in [0, 360), S, L \in [0, 100]$).
*   **Alpha (`float alpha_`):** A 32-bit float constrained to $[0.0, 1.0]$.
*   **Bitfields & Metadata:**
    *   `ColorSpace color_space_ : 4`: Tracks the instantiation space (`kSRGB`, `kSRGBLinear`, `kDisplayP3`, `kA98RGB`, `kProPhotoRGB`, `kRec2020`, `kXYZD50`, `kXYZD65`, `kLab`, `kOKLab`, `kLch`, `kOKLch`, `kHSL`, `kHWB`, `kSRGBLegacy`).
    *   `bool param0_is_none_ : 1`, `param1_is_none_ : 1`, `param2_is_none_ : 1`, `alpha_is_none_ : 1`: Explicit bitflags implementing CSS Color 4 §4.4 "Missing Components" (`none` keyword).

#### `ColorSpace` vs. `ColorInterpolationSpace`
*   **`Color::ColorSpace`**: Defines the intrinsic storage and serialization space of a single `blink::Color` instance.
*   **`ColorInterpolationSpace`**: Defines the active vector space in which a transition, animation, or gradient evaluates between two colors. As per CSS Color 4 §12.1:
    *   If both input colors are in legacy sRGB (`kSRGBLegacy`), Blink defaults the interpolation space to `kSRGB` (gamma-encoded).
    *   If either color is in a non-legacy space and no explicit `<color-interpolation-method>` is declared in CSS, Blink defaults the interpolation space to **`kOKLab`**.

---

### 2. Linear Interpolation & Premultiplied Alpha Handling

Per CSS Color 4 §12.2 and §12.3, Blink executes color interpolation (`Color::InterpolateColors`) across a normalized time parameter $t \in \mathbb{R}$ (typically $[0, 1]$, though cubic-bezier timing functions allow $t \notin [0, 1]$) through a 6-stage pipeline:

#### Stage 1: Conversion to Interpolation Space
Given colors $C_0$ and $C_1$, both are transformed from their intrinsic `ColorSpace` into the target `ColorInterpolationSpace` via intermediate CIE XYZ (D65 or D50) matrices and non-linear transfer functions:
*   **sRGB:** Direct evaluation in gamma-encoded sRGB coordinates.
*   **Display P3:** Converted via sRGB $\to$ XYZ D65 $\to$ Linear P3 $\to$ Gamma P3 (using the sRGB transfer function).
*   **OKLab:** Converted via source space $\to$ XYZ D65 $\to$ LMS cone response ($M_1$) $\to$ non-linear cube root ($\sqrt[3]{\cdot}$) $\to$ OKLab coordinates ($M_2$).

*Note on Analogous Missing Components:* If a color has a `none` component, that flag survives conversion if the target space has an analogous component (e.g., $R, G, B$ across RGB spaces, or $L$ between Lab and OKLab).

#### Stage 2: Missing Component Substitution
Prior to premultiplication, if $C_0$ has a `none` flag for channel $i$ and $C_1$ does not, $C_0$'s channel $i$ takes the value of $C_1$'s channel $i$ (and vice versa). If both are `none`, the interpolated output channel remains `none`.

#### Stage 3: Alpha Premultiplication
To prevent transparent colors (e.g., `rgba(0, 0, 0, 0)`) from polluting the hue/luminance of opaque colors during transition, non-polar channels are premultiplied by their clamped alpha $\alpha \in [0, 1]$:
$$\hat{c}_i = c_i \cdot \alpha \quad \text{for } i \in \{0, 1, 2\}$$
*(Note: Polar hue angles in LCH/OKLCH/HSL/HWB are never premultiplied; they undergo cylindrical angle interpolation via `HueInterpolationMethod` instead).*

#### Stage 4: Linear Interpolation (Lerp)
Blink performs component-wise affine combination on the premultiplied coordinates and the unpremultiplied alpha:
$$\alpha(t) = (1 - t)\alpha_0 + t\alpha_1$$
$$\hat{c}_i(t) = (1 - t)\hat{c}_{0,i} + t\hat{c}_{1,i}$$

#### Stage 5: Unpremultiplication (Division by Alpha)
To project the premultiplied coordinates back into the target color space, Blink divides by the interpolated alpha $\alpha(t)$, guarding against the singularity at $\alpha(t) = 0$:
$$c_i(t) = \begin{cases} \dfrac{\hat{c}_i(t)}{\alpha(t)} & \text{if } \alpha(t) > 0 \\ \hat{c}_i(t) & \text{if } \alpha(t) = 0 \end{cases}$$

#### Audit Finding: Transparent Boundary Discontinuity (`Color::FromHSLA` / `InterpolateColors`)
When $\alpha_0 = 0$ and $\alpha_1 > 0$, $\hat{c}_{0,i} = 0$. For any $t \in (0, 1]$, the unpremultiplied result simplifies algebraically:
$$c_i(t) = \frac{(1 - t)(0) + t(c_{1,i}\alpha_1)}{(1 - t)(0) + t\alpha_1} = \frac{t c_{1,i}\alpha_1}{t\alpha_1} = c_{1,i}$$
However, at the exact boundary $t = 0$, $\alpha(0) = 0$. The conditional branch yields $c_i(0) = \hat{c}_{0,i} = 0$, rather than preserving $c_{0,i}$ or matching the right-hand limit $\lim_{t \to 0^+} c_i(t) = c_{1,i}$. While visually masked because $\alpha(0) = 0$, this violates raw channel boundary preservation if the underlying RGB channels of a fully transparent color are inspected via JS/OM before serialization.

---

### 3. Channel Clamping and Gamut Mapping

#### Intermediate Unclamped Coordinates
Per CSS Color 4 §12, color channels are **not** clamped during conversion or interpolation in wide-gamut spaces (`kSRGB`, `kDisplayP3`, `kOKLab`). If an animation uses an easing curve with $t > 1.0$ or $t < 0.0$, the resulting channels $c_i(t)$ are permitted to exceed $[0.0, 1.0]$ to preserve out-of-gamut fidelity throughout composite pipelines.

#### Alpha Clamping
Alpha is strictly a scalar opacity factor, not a color coordinate. Even when $t \notin [0, 1]$, Blink enforces:
$$\alpha_{\text{clamped}}(t) = \min(1.0, \max(0.0, (1 - t)\alpha_0 + t\alpha_1))$$
Unpremultiplication uses $\alpha_{\text{clamped}}(t)$.

#### Serialization & Legacy Clamping (`kSRGBLegacy`)
Clamping to valid gamut ranges occurs strictly at two boundaries:
1.  **Float Gamut Clamping $[0.0, 1.0]$:** Applied when converting to hardware textures with fixed-point normalization or when CSS Gamut Mapping (§13) is invoked (which in Blink currently defaults to simple per-channel clipping `clamp(c, 0.0f, 1.0f)` in destination RGB space rather than full iterative OKLCH $\Delta E_{OK}$ reduction, due to real-time rendering performance constraints).
2.  **8-bit Quantization $[0, 255]$:** Applied when downsampling to `RGBA32` or serializing legacy `rgb()`/`rgba()` strings:
    $$\text{channel}_{8\text{bit}} = \text{round}\left(\text{clamp}(c_i, 0.0, 1.0) \times 255.0\right)$$
    Implemented in Blink via `ClampTo<int>( std::lround(channel * 255.0f), 0, 255 )`.

---

### 4. Mathematical Invariants

Let $C_0 = (c_0, \alpha_0)$ and $C_1 = (c_1, \alpha_1)$ be valid colors in a rectangular interpolation space with $\alpha_0, \alpha_1 \in [0, 1]$, and $t \in [0, 1]$.

#### Invariant 1: Alpha Conservation (Convexity & Closure)
For all $t \in [0, 1]$, the interpolated alpha $\alpha(t) = (1-t)\alpha_0 + t\alpha_1$ satisfies:
$$\min(\alpha_0, \alpha_1) \le \alpha(t) \le \max(\alpha_0, \alpha_1) \implies \alpha(t) \in [0, 1]$$
Thus, clamping $\alpha(t)$ to $[0, 1]$ is an identity operation on the interval $t \in [0, 1]$.

#### Invariant 2: Convex Combination Boundary Preservation
*   **Alpha Boundary:** At $t=0$, $\alpha(0) = \alpha_0$. At $t=1$, $\alpha(1) = \alpha_1$.
*   **Premultiplied Channel Boundary:** At $t=0$, $\hat{c}(0) = \hat{c}_0$. At $t=1$, $\hat{c}(1) = \hat{c}_1$.
*   **Unpremultiplied Channel Boundary:** Assuming strict opacity ($\alpha_0 > 0$ at $t=0$, and $\alpha_1 > 0$ at $t=1$):
    $$c(0) = \frac{1 \cdot (c_0 \alpha_0) + 0}{\alpha_0} = c_0, \qquad c(1) = \frac{0 + 1 \cdot (c_1 \alpha_1)}{\alpha_1} = c_1$$
    *(If $\alpha_0 = 0$, visual equivalence holds in premultiplied compositor space since $c(0) \cdot \alpha(0) = 0 = c_0 \cdot \alpha_0$, even if raw unpremultiplied coordinate $c_0 \neq 0$).*

#### Invariant 3: Monotonicity of Interpolation in $t$
Even though unpremultiplied interpolation $c(t) = \frac{(1-t)c_0\alpha_0 + tc_1\alpha_1}{(1-t)\alpha_0 + t\alpha_1}$ is a non-linear rational function of $t$ when $\alpha_0 \neq \alpha_1$, it is **strictly monotonic** on $t \in [0, 1]$ whenever $\alpha_0, \alpha_1 > 0$.
Taking the first derivative with respect to $t$:
$$\frac{dc}{dt} = \frac{\alpha_0 \alpha_1 (c_1 - c_0)}{\left((1 - t)\alpha_0 + t\alpha_1\right)^2}$$
Since $\alpha_0 > 0$, $\alpha_1 > 0$, and the denominator $\alpha(t)^2 > 0$ for all $t \in [0, 1]$:
*   If $c_0 \le c_1$, then $\frac{dc}{dt} \ge 0$ for all $t \in [0, 1]$ ($c(t)$ is monotonically non-decreasing).
*   If $c_0 \ge c_1$, then $\frac{dc}{dt} \le 0$ for all $t \in [0, 1]$ ($c(t)$ is monotonically non-increasing).

---

### 5. Formal Verification in Rocq / Coq (`BlinkColorInterpolationSemantics.v`)

The following self-contained Coq formalization encodes Blink's data structures, `none` resolution, premultiplied lerp, clamping semantics, and proves all four mathematical invariants over the Reals ($\mathbb{R}$).

```coq
(** * BlinkColorInterpolationSemantics.v
    Formal verification of Chromium Blink Color Interpolation
    against CSS Color Module Level 4 (§12 & §13). *)

From Coq Require Import Reals Lra Psatz.
Open Scope R_scope.

(** ** 1. Core Data Structures *)

Inductive ColorSpace : Type :=
  | kSRGBLegacy
  | kSRGB
  | kSRGBLinear
  | kDisplayP3
  | kA98RGB
  | kProPhotoRGB
  | kRec2020
  | kXYZD50
  | kXYZD65
  | kLab
  | kOKLab.

Inductive ColorInterpolationSpace : Type :=
  | Interp_SRGB
  | Interp_SRGBLinear
  | Interp_DisplayP3
  | Interp_OKLab
  | Interp_XYZD65.

(** CSS Color 4 §4.4: A channel is either a real value or 'none' (missing). *)
Inductive Channel : Type :=
  | Val (v : R)
  | NoneCh.

Record BlinkColor : Type := mkColor {
  space  : ColorSpace;
  param0 : Channel;
  param1 : Channel;
  param2 : Channel;
  alpha  : Channel
}.

(** Determine default interpolation space per CSS Color 4 §12.1 *)
Definition default_interpolation_space (c0 c1 : BlinkColor) : ColorInterpolationSpace :=
  match space c0, space c1 with
  | kSRGBLegacy, kSRGBLegacy => Interp_SRGB
  | _, _ => Interp_OKLab
  end.

(** ** 2. Clamping