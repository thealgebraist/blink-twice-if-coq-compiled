**AUDIT LOG: AGENT 411**  
**TARGET:** Chromium / Blink Rendering Engine (via Skia Graphics Library)  
**SUBJECT:** Porter-Duff `source-over` (`SkBlendMode::kSrcOver`) combined with `normal` blend mode.  
**FOCUS:** Mathematical and Computational Output Boundedness.

---

### 1. Executive Summary
Under standard mathematical definitions and floating-point / integer representations within Blink, the `normal` `source-over` blending operation is **strictly bounded** to the unit interval $[0.0, 1.0]$ (or $[0, 255]$ in 8-bit integer space), **provided the inputs are properly bounded and premultiplied.** 

However, under specific edge cases involving GPU fast-paths, unpremultiplied precision drift, and High Dynamic Range (HDR) canvases, output boundedness can be violated or intentionally bypassed.

---

### 2. Mathematical Boundedness (Ideal State)
Blink delegates compositing to Skia, which operates primarily on **premultiplied alpha** color channels. 

Let $S = (S_r, S_g, S_b, S_a)$ be the Source pixel and $D = (D_r, D_g, D_b, D_a)$ be the Destination pixel.
The precondition for valid premultiplied inputs is:
$$0 \le S_c \le S_a \le 1$$
$$0 \le D_c \le D_a \le 1$$
*(where $c \in \{r, g, b\}$)*

The Porter-Duff `source-over` formula for both color and alpha is:
$$O_c = S_c + D_c \times (1 - S_a)$$
$$O_a = S_a + D_a \times (1 - S_a)$$

#### Proof of Upper Bound ($O_c \le O_a \le 1$):
Since $D_c \le D_a$ and $(1 - S_a) \ge 0$:
$$O_c = S_c + D_c(1 - S_a) \le S_a + D_a(1 - S_a) = O_a$$
To prove $O_a \le 1$:
$$O_a = S_a + D_a - S_a D_a = 1 - (1 - S_a)(1 - D_a)$$
Since $0 \le S_a \le 1$ and $0 \le D_a \le 1$, the product $(1 - S_a)(1 - D_a)$ is $\ge 0$. 
Therefore, $O_a \le 1$.

#### Proof of Lower Bound ($O_c \ge 0$):
Since $S_c \ge 0$, $D_c \ge 0$, and $(1 - S_a) \ge 0$, the sum of non-negative products is non-negative. 
Therefore, $O_c \ge 0$.

**Conclusion:** Mathematically, the output is strictly bounded: $0 \le O_c \le O_a \le 1$.

---

### 3. Computational Boundedness (Implementation Audit)

In practice, Blink/Skia executes this math across varying data types (`uint8_t`, `uint16_t`, `half`, `float`). Agent 411 has identified the following implementation realities regarding boundedness:

#### A. 8-Bit Integer Pipeline (`RGBA_8888`)
In the CPU rasterizer (Skia Raster Pipeline), colors are integers in $[0, 255]$. The `source-over` equation is scaled by 255:
$$O_c = S_c + \text{div255}(D_c \times (255 - S_a))$$

*   **Exact Division:** True division by 255 is $(X + 127) / 255$, which can be approximated via bit-shifting as `(X + 128 + ((X + 128) >> 8)) >> 8`. If this exact rounding is used, max values ($S_c=255, S_a=255$) yield $255 + \text{div255}(D_c \times 0) = 255$. Boundedness holds: $[0, 255]$.
*   **Fast Approximation (The "256" Trick):** In older or hyper-optimized SIMD paths (SSE/NEON), division by 255 is sometimes approximated by adding 1 to the inverse alpha: `(D_c * (256 - S_a)) >> 8`.
    *   *Audit Check:* If $S_a = 0$ and $D_c = 255$, $255 \times 256 \gg 8 = 255$. If $S_c = 255, S_a = 255$, $255 + (D_c \times 1 \gg 8) = 255 + 0 = 255$. No overflow occurs, though slight darkening (underflow of expected value by 1) can happen on intermediate alphas. Boundedness holds.

#### B. Premultiplication Invariant Violations (Super-luminescent Pixels)
The most common cause of boundedness failure in Blink is **invalid input state** (where $S_c > S_a$). This occurs via:
1.  **Canvas 2D `putImageData`:** Inputs are unpremultiplied. Conversion to premultiplied and back can suffer from 8-bit quantization errors.
2.  **WebGL / WebGPU Textures:** Shaders can write arbitrary values to framebuffers where $S_c > S_a$ and pass them to the Blink compositor.

*Impact on Boundedness:*
If $S_c = 255$ and $S_a = 0$ (an illegal premultiplied state representing an emissive/additive pixel), and $D_c = 255$:
$$O_c = 255 + 255 \times (1 - 0) = 510$$
*   **CPU Path:** Skia's integer SIMD pipelines use saturating arithmetic (e.g., `_mm_adds_epu8` in x86 SSE) or explicit clamping when packing back to 8-bit. Thus, $510$ clamps to $255$. However, the *invariant* $O_c \le O_a$ may remain broken if $O_a$ evaluates to $< 255$.
*   **GPU Path:** For `RGBA8` textures, the GPU hardware blender automatically clamps outputs to $[0.0, 1.0]$ before writing to the render target.

#### C. Floating-Point and Extended Range (HDR / Wide Gamut)
Blink supports `color-space: display-p3`, `rec2020`, and `RGBA16F` / `RGBA32F` backings (e.g., via Canvas floating-point extensions and HDR video compositing).

1.  **IEEE 754 Precision Drift:** In `F16` or `F32` pipelines, Fused Multiply-Add (`std::fma` or GPU `mad`/`fma` instructions) calculating $S_c + D_c \times (1.0 - S_a)$ can result in $1.0000001$ due to rounding in $(1.0 - S_a)$.
2.  **Extended sRGB (scRGB):** Values $< 0.0$ and $> 1.0$ are **valid** in extended color spaces. In these pipelines, hardware blending does **not** clamp to $[0.0, 1.0]$.
    *   If $S_c = 2.5$ (HDR specular highlight), $S_a = 1.0$, then $O_c = 2.5$.
    *   *Boundedness Status:* Unbounded by the unit interval, bounded only by `FLT_MAX` (or `65504.0` for `FP16`). `NaN` propagation is a risk if $S_a = \infty$ or $\text{NaN}$, as $0 \times \infty = \text{NaN}$ in the $(D_c \times (1 - S_a))$ term.

---

### 4. Summary Matrix for Agent 411

| Pipeline / Backing | Output Range | Enforced By | Vulnerability / Edge Case |
| :--- | :--- | :--- | :--- |
| **Skia CPU (`RGBA8888`)** | $[0, 255]$ | Saturating SIMD (`paddusb`) / Bitwise Masks | Unpremultiplied conversion drift can yield $O_c > O_a$ (still $\le 255$). |
| **GPU Ganesh/Graphite (`RGBA8`)** | $[0.0, 1.0]$ | Fixed-function GPU ROP (Render Output Unit) | Immune to overflow; hardware clamps unconditionally on write. |
| **HDR / Float (`RGBA16F`)** | $[-\text{MAX}, +\text{MAX}]$ | Unclamped (By Design) | **NaN Poisoning:** If $D_c = 0$ and $S_a = \text{NaN}$ or $\infty$, output becomes $\text{NaN}$, corrupting the composition tile. |

### 5. Audit Conclusion
Blink's `normal` `source-over` blending is **strictly bounded** in standard dynamic range (SDR) contexts through a combination of mathematical invariants and hardware/SIMD saturation. In HDR/Float contexts, unit-interval boundedness is intentionally lifted, shifting the security/stability boundary to **NaN/Inf sanitization** at the shader/filter ingestion boundary.

**END OF REPORT - AGENT 411**