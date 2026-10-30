**Agent 435 — Blink WebAudio Audit Report**
**Target:** `BiquadFilterNode` / `BiquadDSPKernel` / `BiquadProcessor`
**Subject:** Frequency (`cutoff`) Parameter Clamping and Bounds Analysis

In Chromium’s Blink engine, the `BiquadFilterNode` implements standard second-order IIR filters. To prevent mathematical instability (e.g., division by zero, `NaN` propagation, or filter explosion near the Nyquist limit), Blink enforces strict clamping on the cutoff/center `frequency` parameter before calculating filter coefficients.

Here is the detailed audit of the cutoff bounds across the three layers of Blink's WebAudio implementation:

### 1. IDL / AudioParam Nominal Bounds (User-Facing)
When a `BiquadFilterNode` is instantiated in the `BaseAudioContext`, the `frequency` `AudioParam` is initialized with strict nominal bounds dictated by the Web Audio API specification:

*   **Minimum (`minValue`):** `0.0` Hz
*   **Maximum (`maxValue`):** $\frac{f_s}{2}$ Hz (Nyquist frequency, where $f_s$ is `context.sampleRate`).
*   **Default (`defaultValue`):** `350.0` Hz

*Audit Note:* If a developer attempts to set `biquad.frequency.value` outside of $[0, \frac{f_s}{2}]$, Blink clamps the value and logs a console warning via `ExceptionState` or `AudioParamTimeline`, depending on whether it's an immediate setter or an automation curve.

### 2. DSP Kernel Normalization (Internal)
Inside `BiquadDSPKernel::UpdateCoefficients()`, the raw frequency in Hertz (including any `a-rate` or `k-rate` modulation inputs and detune calculations) is converted into a **normalized frequency** ($f_{\text{norm}}$) prior to entry into the coefficient math:

$$f_{\text{computed}} = f_{\text{param}} \times 2^{\text{detune} / 1200}$$
$$f_{\text{norm}} = \frac{f_{\text{computed}}}{f_s / 2}$$

At this stage, $f_{\text{norm}}$ represents the frequency on a scale from `0.0` (DC) to `1.0` (Nyquist). Because `detune` or connected audio-rate signals can push $f_{\text{computed}}$ past the nominal `AudioParam` bounds, a hard clamp is executed at the DSP level.

### 3. Coefficient Calculation Clamping (`Biquad.cc`)
In `blink::Biquad`, the normalized frequency (`cutoff`) is strictly clamped using ` std::clamp(cutoff, 0.0, 1.0)` (or historical ` ClampTo()` equivalents), with specific boundary behaviors depending on the filter type to avoid trigonometric singularities (such as $\tan(\pi / 2)$ or $\sin(0)$):

*   **Lower Bound (`0.0`):**
    *   **Lowpass:** If `cutoff <= 0.0`, the filter completely blocks all signal. Coefficients are hardcoded to $b_0, b_1, b_2 = 0$ and $a_1, a_2 = 0$ (Complete silence).
    *   **Highpass:** If `cutoff <= 0.0`, the filter passes all signal unaffected. Coefficients are set to unity gain ($b_0 = 1$, all others $0$).
    *   **Bandpass / Peaking / Notch / Shelving:** Clamped strictly at `0.0`. In filters utilizing $\omega_0 = \pi \times \text{cutoff}$, if $\omega_0 == 0$, $\sin(\omega_0) = 0$. The math guards against dividing by $\alpha$ (which depends on $\sin(\omega_0)$) by short-circuiting to unity or zero-gain states.

*   **Upper Bound (`1.0` - Nyquist):**
    *   **Lowpass:** If `cutoff >= 1.0`, the filter acts as a pass-through (unity gain: $b_0 = 1$, others $0$).
    *   **Highpass:** If `cutoff >= 1.0`, the filter outputs total silence ($b_0, b_1, b_2 = 0$).
    *   **Other Filter Types:** Clamped to `1.0`. At Nyquist, $\omega_0 = \pi$, meaning $\cos(\omega_0) = -1$ and $\sin(\omega_0) = 0$. The bilinear transform calculations in Blink explicitly branch if `cutoff >= 1.0` to prevent unstable poles from forming right on the unit circle ($z = -1$).

### Summary of Security / Stability Posture
*   **NaN/Inf Mitigation:** `AudioParam` automation values are sanitized before reaching `Biquad.cc`, and `ClampTo()` ensures `NaN` defaults to `0.0` or `minValue`.
*   **Denormals:** Coefficients resulting from extreme clamping bounds (`cutoff` very close to `0.0` or `1.0`) are protected against floating-point underflow via `FlushDenormals` macros in the `Biquad::Process` loop.

**End of Report — Agent 435.**