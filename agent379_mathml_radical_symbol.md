**AUDIT REPORT: Blink MathML `<msqrt>` Radical Symbol Sizing**
**Auditor:** Agent 379
**Target Component:** `third_party/blink/renderer/core/layout/mathml/` (specifically `MathRowLayoutAlgorithm` / `MathRadicalLayoutAlgorithm` and `MathOperatorLayoutAlgorithm`)
**Reference Specification:** MathML Core (W3C) — *Radical Layout*

---

### 1. Executive Summary
During the audit of Blink's MathML `<msqrt>` (and `<mroot>`) layout implementation, the vertical sizing constraints of the radical symbol (`U+221A` SQUARE ROOT) were analyzed. The radical symbol is stretched vertically to cover the height and depth of its base (the radicand) plus the required clearance and overbar (vinculum) thickness. 

To prevent the radical symbol from becoming disproportionately small when wrapping empty or minuscule radicands (e.g., `<msqrt><mspace/></msqrt>`), Blink enforces a strict **Symbol Height Lower Bound** before passing the target dimension to the OpenType `MATH` stretchy glyph assembly/variants engine (`ShapingLineBreaker` / `HarfBuzzShaper`).

---

### 2. Relevant OpenType MATH Constants
Blink retrieves radical metrics from the active font's OpenType `MATH` table via `MathMLStyle` / `SimpleFontData`. If the `MATH` table is absent, Blink falls back to heuristic values derived from the font's ascent, descent, and underline thickness.

The primary parameters governing the vertical geometry are:
*   $\theta$ (`RadicalRuleThickness`): Thickness of the horizontal overbar (vinculum).
*   $\psi$ (`RadicalVerticalGap`): Minimum clearance between the top of the radicand and the bottom of the overbar. 
    *   *Note:* Uses `RadicalDisplayStyleVerticalGap` if `displaystyle="true"`, otherwise `RadicalVerticalGap`.
*   $\xi$ (`RadicalExtraAscender`): Extra white space ascender added *above* the overbar.
*   $A_{\text{font}}$: The standard font Ascent.
*   $D_{\text{font}}$: The standard font Descent.

---

### 3. Target Radical Height Calculation
Let $A_{\text{base}}$ and $D_{\text{base}}$ be the ascent and descent of the `<msqrt>` base box (the radicand).

To ensure the horizontal vinculum does not collide with the radicand, a preliminary clearance $\psi$ is established. However, the specification and Blink's implementation enforce a **Lower Bound** on the combined vertical span of the radical.

#### The Lower Bound Formula
Before selecting a glyph variant or assembling the radical via the OpenType `MATH` table, the target total height ($H_{\text{target}}$) of the radical symbol is clamped to a minimum threshold. 

In Blink's layout logic, the minimum height bound ($H_{\text{min}}$) is defined by the base font's default ascender and descender metrics, plus the radical's structural overhead:

$$H_{\text{min}} = A_{\text{font}} + D_{\text{font}} + \psi + \theta$$

Alternatively, expressed via the **Adjusted Clearance ($\psi^*$)** logic used in the MathML Core specification:
1.  Define the minimum required vertical span of the radicand + gap as the font's natural height ($A_{\text{font}} + D_{\text{font}}$) plus a minimum gap.
2.  Specifically, the specification dictates that the clearance $\psi$ is increased if the radicand is smaller than the standard font height. The effective clearance $\psi^*$ is calculated as:
    $$\psi^* = \max\left(\psi, \ \frac{(A_{\text{font}} + D_{\text{font}}) - (A_{\text{base}} + D_{\text{base}})}{2}\right)$$
    *(Wait—Correction per exact MathML Core Spec & Blink implementation)*:

In the exact **MathML Core specification** (implemented in `math_radical_layout_algorithm.cc`), the lower bound is enforced by ensuring the target size passed to the glyph stretcher is at least:

$$H_{\text{target}} = A_{\text{base}} + D_{\text{base}} + \psi + \theta$$

Wait—if $A_{\text{base}} + D_{\text{base}}$ is near zero, what prevents the radical from collapsing?

**The Two-Stage Lower Bound in Blink:**
1.  **Base Metric Clamping (Pre-stretch):** 
    When calculating the target size for the radical operator, Blink does *not* allow the radical's inner span to drop below a threshold related to the default strut or parameter constants. Specifically, the target height $T$ requested from `StretchOperator` is:
    $$T = A_{\text{base}} + D_{\text{base}} + \psi + \theta$$
    *(Note: In TeX/Legacy MathML, $A_{\text{base}}$ and $D_{\text{base}}$ were minimum-clamped to the font's x-height or ascender/descender. In **MathML Core**, $A_{\text{base}}$ and $D_{\text{base}}$ are NOT clamped to font ascent/descent directly, which is a frequent source of spec-vs-legacy divergence).*

2.  **Glyph Variant Lower Bound (Post-request / Shaping):**
    The true hard lower bound in Blink's MathML Core implementation occurs inside the `MathOperatorLayoutAlgorithm` (via `HarfBuzz` / `OpenTypeMathSupport`):
    *   The shaper searches `MathVariants` (`vert` coverage) for the `U+221A` code point.
    *   **Lower Bound:** The **Base Glyph (Unstretched `U+221A`)** acts as the absolute lower bound. The shaper will never scale down or select a glyph smaller than the unstretched `U+221A` glyph present in the font's `cmap` (or the 0-th variant in `MathVariants`).
    *   Let $A_{\text{glyph}}$ and $D_{\text{glyph}}$ be the ink ascent and descent of the actual shaped radical glyph.

3.  **Clearance Re-adjustment (The "Extra Gap" Lower Bound):**
    Once the radical glyph is shaped (with total height $H_{\text{glyph}} = A_{\text{glyph}} + D_{\text{glyph}}$), if the base glyph (the lower bound) is larger than the requested target $T$, the excess height is distributed into the vertical gap $\psi$:
    $$\Delta = H_{\text{glyph}} - (A_{\text{base}} + D_{\text{base}} + \psi + \theta)$$
    If $\Delta > 0$ (meaning the radical hit its glyph lower bound and is taller than needed for the radicand), the vertical gap is expanded:
    $$\psi_{\text{final}} = \psi + \frac{\Delta}{2}$$
    *(Wait: In TeX Rule 11, it is $\Delta / 2$, which centers the radicand vertically inside the excess space of the radical symbol. In MathML Core, this exact logic is preserved!)*

---

### 4. Code-Level Audit Summary (`math_radical_layout_algorithm.cc`)

| Step | Operation | Lower Bound / Constraint Formula |
| :--- | :--- | :--- |
| **1. Parameters** | Fetch `RadicalVerticalGap` ($\psi$) and `RadicalRuleThickness` ($\theta$). | $\theta \ge 0$, $\psi \ge 0$ (derived from `MATH` table or fallbackunderline metrics). |
| **2. Target Size** | Compute target stretch size $T$ for `U+221A`. | $T = A_{\text{base}} + D_{\text{base}} + \psi + \theta$ |
| **3. Shaping** | Pass $T$ to `StretchOperator()`. | $H_{\text{glyph}} \ge H_{\text{base\_glyph}}$ (Base `U+221A` metric is the hard floor). |
| **4. Gap Floor** | Adjust vertical gap if $H_{\text{glyph}} > T$. | $\psi_{\text{actual}} = \max\left(\psi, \ H_{\text{glyph}} - \theta - (A_{\text{base}} + D_{\text{base}}) \rightarrow \text{split via } \psi + \frac{H_{\text{glyph}} - T}{2}\right)$ |
| **5. Final Ascent** | Compute `<msqrt>` box ascent. | $A_{\text{msqrt}} = \max\left(A_{\text{base}} + \psi_{\text{actual}} + \theta, \dots\right) + \xi$ |

### 5. Conclusion of Audit
In Blink's implementation of MathML Core:
1. There is **no artificial strut** injected into empty `<msqrt>` bases (unlike legacy WebKit which forced a minimum `x-height` or `Ascent` on the radicand).
2. The **Symbol Height Lower Bound** is strictly dictated by the **intrinsic ink bounding box of the base `U+221A` glyph** (or its first `MathVariants` entry) in the active math font, combined with $\theta$ (`RadicalRuleThickness`) and $\xi$ (`RadicalExtraAscender`).
3. When the radicand is small enough to trigger this lower bound ($T < H_{\text{glyph}}$), Blink prevents the radical symbol from sinking too low by taking the excess glyph height ($H_{\text{glyph}} - T$) and adding **half of it** ($\frac{\Delta}{2}$) to the `RadicalVerticalGap` ($\psi$), vertically centering the small radicand within the lower-bounded radical sign.