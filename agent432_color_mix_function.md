**AUDIT LOG: AGENT 432**
**TARGET:** Chromium / Blink Rendering Engine (`third_party/blink/renderer/core/css/`)
**SUBJECT:** CSS Color 5 `color-mix()` Percentage Normalization Rules
**STATUS:** ACTIVE

---

### 1. Specification Baseline (CSS Color Module Level 5)
In `color-mix(in <color-space>, <color> <percentage>?, <color> <percentage>?)`, let $p_1$ and $p_2$ be the percentages provided for the first and second colors, respectively. 

Blink must resolve missing percentages, validate ranges, and normalize $p_1$ and $p_2$ so they sum to $100\%$ before interpolation, whilst accounting for the alpha multiplier ($\alpha_{mult}$) when the raw sum is $< 100\%$.

### 2. Normalization Pipeline in Blink

#### Phase A: Defaulting Missing Percentages
Before normalization, Blink resolves omitted percentages during parsing/value-calculation (`css_color_mix_value.cc` / `color.cc`):
*   **Both omitted:** $p_1 = 50\%$, $p_2 = 50\%$.
*   **One omitted:** The missing percentage is calculated as $100\% - p_{provided}$.
    *   *If $p_1$ is provided:* $p_2 = 100\% - p_1$.
    *   *If $p_2$ is provided:* $p_1 = 100\% - p_2$.

#### Phase B: Parse-Time Validation
*   **Rule:** $p_1$ and $p_2$ must reside within the range $[0\%, 100\%]$.
*   **Blink Behavior:** Values $< 0\%$ or $> 100\%$ (e.g., `color-mix(in srgb, red 110%, blue)`) are rejected at parse time as invalid CSS values (`CSSParserFastPaths` / `CSSPropertyParser`).
*   **Zero-Sum Edge Case:** If $p_1 = 0\%$ and $p_2 = 0\%$, the function is invalid. If defined via explicit literals, it fails at parse time. If resolved via `calc()`, it fails at computed-value time.

#### Phase C: Sum-to-100% Normalization & Alpha Scaling
Once $p_1$ and $p_2$ are resolved, let $S = p_1 + p_2$. Blink normalizes the weights ($w_1, w_2$) and determines the alpha multiplier ($\alpha_{mult}$) in `blink::Color::FromColorMix`:

1.  **Case 1: $S = 100\%$ (Standard)**
    *   No scaling required.
    *   $w_1 = p_1 / 100$
    *   $w_2 = p_2 / 100$
    *   $\alpha_{mult} = 1.0$
    *   *Sum of weights:* $1.0$ ($100\%$).

2.  **Case 2: $S > 100\%$ (Over-saturated Sum)**
    *   Percentages are scaled down proportionally so their sum equals $100\%$.
    *   $w_1 = \frac{p_1}{p_1 + p_2}$
    *   $w_2 = \frac{p_2}{p_1 + p_2}$
    *   $\alpha_{mult} = 1.0$
    *   *Audit Example:* `color-mix(in srgb, red 80%, blue 80%)`
        *   $S = 160\%$.
        *   $w_1 = 80 / 160 = 0.50$ ($50\%$).
        *   $w_2 = 80 / 160 = 0.50$ ($50\%$).
        *   Resulting mix is $50\% / 50\%$ with full opacity.

3.  **Case 3: $S < 100\%$ (Under-saturated Sum)**
    *   The relative weights are still scaled up to sum to $100\%$ for the **color channel interpolation**, *but* the shortfall is stored as an alpha multiplier applied to the final color.
    *   $w_1 = \frac{p_1}{p_1 + p_2}$
    *   $w_2 = \frac{p_2}{p_1 + p_2}$
    *   $\alpha_{mult} = \frac{p_1 + p_2}{100}$
    *   *Audit Example:* `color-mix(in srgb, red 20%, blue 20%)`
        *   $S = 40\%$.
        *   $w_1 = 20 / 40 = 0.50$ ($50\%$).
        *   $w_2 = 20 / 40 = 0.50$ ($50\%$).
        *   $\alpha_{mult} = 40 / 100 = 0.40$.
        *   Resulting mix interpolates channels at $50\% / 50\%$, then multiplies the final alpha channel by $0.4$.

---

### 3. Blink Codebase Verification (`color.cc`)

In Blink's implementation (`blink::Color::FromColorMix`), normalization is executed via floating-point arithmetic (`double`). The C++ logic follows this exact structure:

```cpp
// blink::Color::NormalizeColorMixPercentages
bool Color::NormalizeColorMixPercentages(
    double& mix_amount,     // Equivalates to w2 (weight of color 2)
    double& alpha_multiplier,
    std::optional<double> percentage1,
    std::optional<double> percentage2) {

  double p1 = percentage1.value_or(1.0 - percentage2.value_or(0.5));
  double p2 = percentage2.value_or(1.0 - p1);

  if (p1 < 0.0 || p1 > 1.0 || p2 < 0.0 || p2 > 1.0)
    return false; // Invalid

  double sum = p1 + p2;
  if (sum == 0.0)
    return false; // Invalid per spec

  // Normalize so p1 + p2 = 100% (1.0)
  p1 /= sum;
  p2 /= sum;

  alpha_multiplier = std::min(sum, 1.0);
  
  // Blink's InterpolateColors expects a single [0..1] 'progress' parameter (w2)
  // because w1 is implicitly (1.0 - w2).
  mix_amount = p2; 
  if (p1 == 1.0) {
    mix_amount = 0.0; // Guard against floating-point drift when p2 is 0
  }
  
  return true;
}
```

### 4. Serialization Audit (Computed Value / `getComputedStyle`)
Per the CSS Color 5 spec on serialization of `color-mix()` (primarily relevant when mixing with `currentcolor` where interpolation must be deferred until used-value time):
*   Blink normalizes the percentages in the serialized string if they can be simplified, or outputs the normalized $p_1$ directly while omitting $p_2$ if $p_1 + p_2 = 100\%$.
*   If $p_1 + p_2 \neq 100\%$, Blink retains or computes the necessary representation to preserve the $\alpha_{mult}$ effect during deferred evaluation.

**AUDIT CONCLUSION:** Blink's `NormalizeColorMixPercentages` strictly adheres to W3C CSS Color 5 § 2.1. Floating-point inaccuracies at boundaries ($p_1 = 100\%, p_2 = 0\%$) are explicitly clamped. **PASS.**