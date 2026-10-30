**AUDIT REPORT: BLINK CANVAS PATTERN REPEAT WRAPPING**
**AUDITOR:** Agent 446
**COMPONENT:** Blink Rendering Engine (`third_party/blink/renderer/modules/canvas/`) & Skia Backend (`third_party/skia/src/shaders/`)
**SUBJECT:** Modulo Coordinate Wrapping Mechanics (`repeat`, `repeat-x`, `repeat-y`)

---

### 1. EXECUTIVE SUMMARY
In the Chromium Blink engine, HTML5 Canvas `CanvasPattern` repeat wrapping does not occur directly in the DOM/Blink layer during the draw call. Instead, Blink acts as a state translator, mapping HTML5 repetition strings into `SkTileMode` enums and passing them via `cc::PaintFlags` to the Skia graphics backend. The actual modulo coordinate wrapping is executed within Skia’s fragment shaders (GPU) or raster pipelines (CPU) in normalized texture space.

---

### 2. ARCHITECTURAL DATA FLOW
1. **Blink API Layer (`CanvasPattern`):** Validates the repetition string (`"repeat"`, `"repeat-x"`, `"repeat-y"`, `"no-repeat"`) and sets internal `WebCore`/`Blink` repeat flags.
2. **Paint Layer (`ImagePattern` / `PaintShader`):** Maps the flags to two orthogonal Skia tile modes: `SkTileMode::kRepeat` and `SkTileMode::kDecal` (for `no-repeat` axes).
3. **Skia Shader Execution:** Coordinates are transformed from local Canvas space to Pattern space via the inverse of the CTM (Current Transformation Matrix) combined with the `DOMMatrix` applied to the pattern.

---

### 3. MATHEMATICAL & ALGORITHMIC DETAIL: MODULO WRAPPING

When rendering a primitive filled with a repeating `CanvasPattern`, the engine maps destination pixel coordinates $(x, y)$ to source pattern coordinates $(u, v)$. 

#### A. Coordinate Normalization
Before modulo arithmetic is applied, pattern space coordinates $(x_p, y_p)$ are normalized against the pattern's intrinsic dimensions $(W, H)$:
$$u = \frac{x_p}{W}, \quad v = \frac{y_p}{H}$$

#### B. The Modulo Equivalence (Positive vs. Negative Space)
A naive C++ modulo (`fmod(u, 1.0f)`) fails for negative coordinates (resulting in negative UV values, which read out-of-bounds memory or mirror incorrectly). Blink/Skia utilizes a floor-subtraction method to ensure Euclidean modulo behavior:

$$u_{wrapped} = u - \lfloor u \rfloor$$
$$v_{wrapped} = v - \lfloor v \rfloor$$

In GPU shaders (GLSL/SkSL), this is executed via the hardware `fract()` intrinsic, which is mathematically identical to $u - \text{floor}(u)$ and strictly maps all real numbers to the range $[0.0, 1.0)$.

#### C. De-normalization (Texel Fetching)
Once wrapped to $[0.0, 1.0)$, the coordinates are scaled back to the pattern's texture dimensions to fetch the correct texel:
$$X_{texel} = u_{wrapped} \times W$$
$$Y_{texel} = v_{wrapped} \times H$$

---

### 4. AXIS-SPECIFIC WRAPPING STATES

Blink translates the 4 HTML5 states into orthogonal $(X, Y)$ operations:

* **`repeat`:** 
  * X-Axis: $u - \lfloor u \rfloor$ (`SkTileMode::kRepeat`)
  * Y-Axis: $v - \lfloor v \rfloor$ (`SkTileMode::kRepeat`)
* **`repeat-x`:** 
  * X-Axis: $u - \lfloor u \rfloor$ (`SkTileMode::kRepeat`)
  * Y-Axis: Bounds check $0.0 \le v < 1.0$. Outside returns transparent black `rgba(0,0,0,0)` (`SkTileMode::kDecal`).
* **`repeat-y`:** 
  * X-Axis: Bounds check $0.0 \le u < 1.0$ (`SkTileMode::kDecal`).
  * Y-Axis: $v - \lfloor v \rfloor$ (`SkTileMode::kRepeat`)
* **`no-repeat`:** 
  * Both axes use `SkTileMode::kDecal`. No modulo arithmetic is performed.

---

### 5. AUDIT FINDINGS: EDGE CASES & VULNERABILITY VECTORS

During the audit of the modulo wrapping implementation, the following precision and rendering edge cases were noted:

#### Finding 446-A: Floating-Point Precision Underflow at Negative Boundaries
* **Mechanism:** For a negative coordinate very close to zero (e.g., $u = -1\times 10^{-8}$), $\lfloor u \rfloor = -1.0$. 
* **Math:** $u - (-1.0)$ in IEEE 754 floating-point arithmetic can round to exactly $1.00000000$.
* **Impact:** Since valid normalized texture space is $[0.0, 1.0)$, a value of $1.0$ multiplied by $W$ results in $X_{texel} = W$. Because textures are 0-indexed up to $W-1$, this causes an off-by-one out-of-bounds read.
* **Mitigation in Place:** Skia's CPU raster pipeline (`SkRasterPipeline_opts.h`) explicitly clamps the result of the modulo operation to `std::nextafter(1.0f, 0.0f)` (roughly `0.99999994f`) or applies a bitwise mask at the integer texel level to prevent buffer overreads.

#### Finding 446-B: Bilinear Filtering Seam Bleeding (`imageSmoothingEnabled = true`)
* **Mechanism:** When `imageSmoothingEnabled` is true (default), texel fetching samples a $2\times2$ grid around $(X_{texel}, Y_{texel})$.
* **Impact:** At the wrapping boundary ($u_{wrapped} \to 0.0$ or $u_{wrapped} \to 1.0$), the bilinear filter must wrap *individual sample offsets*. Sample points at $W - 0.5$ must interpolate with sample points at $0.5$.
* **Mitigation in Place:** If hardware `GL_REPEAT` is unavailable (e.g., Non-Power-Of-Two textures on legacy drivers or atlas-backed textures), Skia injects a software wrap shader that computes the modulo *four separate times* per pixel (once for each bilinear tap) rather than once for the pixel center.

#### Finding 446-C: Sub-pixel Matrix Scaling Artifacts
* **Mechanism:** When a `CanvasPattern` is scaled down heavily via `CanvasPattern.setTransform()`, high-frequency modulo wrapping occurs.
* **Impact:** Without mipmapping, the $u - \lfloor u \rfloor$ step function aliases severely (Moiré patterns). Blink delegates mipmap generation to Skia (`SkFilterMode::kLinear`, `SkMipmapMode::kLinear`) to pre-filter the pattern before modulo wrapping is calculated.

---
**STATUS:** Audit Complete. Modulo wrapping arithmetic is memory-safe and compliant with the HTML Living Standard. 
**END OF REPORT**