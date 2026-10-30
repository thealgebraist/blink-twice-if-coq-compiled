**AUDIT REPORT: Blink WebAudio `GainNode` Attenuation & Amplitude Bounds**
**Auditor:** Agent 434
**Target Component:** Chromium / Blink (`third_party/blink/renderer/modules/webaudio/gain_node.cc`, `gain_handler.cc`)

### 1. Executive Summary
In the Blink rendering engine's implementation of the Web Audio API, the `GainNode` does not enforce hard clamping (such as `[-1.0, 1.0]`) on its output signal. Instead, output amplitude bounds are strictly dictated by IEEE 754 single-precision floating-point arithmetic, resulting in theoretical bounds of `[-\text{FLT\_MAX}, +\text{FLT\_MAX}]`. Clamping is deferred until the audio graph reaches the hardware destination sink (`AudioDestinationNode`).

---

### 2. Parameter Bounds (`GainNode.gain`)
The `gain` attribute is an a-rate (or k-rate) `AudioParam` representing the multiplier applied to the input signal.

*   **Default Value:** `1.0`
*   **Nominal `minValue`:** `-3.4028234663852886e+38` (`-\text{FLT\_MAX}`)
*   **Nominal `maxValue`:** `+3.4028234663852886e+38` (`+\text{FLT\_MAX}`)
*   **Phase Inversion:** Negative gain values are valid and invert the phase of the input signal while scaling its amplitude.

---

### 3. Signal Processing & Output Amplitude Bounds
Within `GainHandler::Process()`, Blink processes audio in 128-frame render quanta using 32-bit floating-point arrays (`float`). The mathematical operation is a linear multiplication via vector math utilities (`vector_math::Vmul` or `Vsma`):

$$Y[n] = X[n] \times G[n]$$

*(Where $Y$ is output, $X$ is input, and $G$ is the calculated gain value at sample $n$.)*

Because internal WebAudio buses operate in unbounded 32-bit float space to preserve dynamic range (headroom) between intermediate nodes, the output amplitude bounds are categorized as follows:

#### A. Nominal Operating Bounds: `[-1.0, +1.0]`
*    represents 0 dBFS (decibels relative to full scale).
*   If $|X[n]| \le 1.0$ and $|G[n]| \le 1.0$, the output remains within standard non-clipping audio bounds.

#### B. Headroom / Unclamped Bounds: `[-\text{FLT\_MAX}, +\text{FLT\_MAX}]`
*   **Values:** $\approx \pm 3.4028235 \times 10^{38}$ (approx. $+770\text{ dBFS}$).
*   **Behavior:** If a `GainNode` amplifies a signal beyond `1.0`, the signal does **not** clip at the `GainNode` output. Subsequent nodes (e.g., another `GainNode` attenuating the signal, or a `DynamicsCompressorNode`) can recover the signal without distortion.

#### C. Attenuation Lower Bound (Noise Floor / Underflow)
*   **Normalized Minimum (`FLT_MIN`):** $\approx \pm 1.17549435 \times 10^{-38}$ (approx. $-758\text{ dBFS}$).
*   **Subnormal (Denormal) Handling:** When massive attenuation pushes the output amplitude below `FLT_MIN` (into the subnormal range down to $\pm 1.4 \times 10^{-45}$), CPU performance can degrade drastically due to floating-point underflow exceptions. 
*   **Blink Mitigation:** Blink's ` AudioBus` and SIMD execution paths typically enable hardware **Flush-to-Zero (FTZ)** and **Denormals-Are-Zero (DAZ)** flags on the CPU's FPU/SSE/NEON registers during the audio rendering thread. Therefore, any attenuated output $Y[n]$ where $|Y[n]| < 1.17549435 \times 10^{-38}$ is instantaneously clamped to **`0.0f`**.

#### D. Overflow & Non-Finite Bounds (`Inf`, `NaN`)
*   **Infinity (`\pm\infty`):** If $X[n] \times G[n] > \text{FLT\_MAX}$, the output saturates to `+Infinity` or `-Infinity`. 
*   **`NaN` (Not a Number):** If $X[n] = \pm\infty$ and $G[n] = 0.0$ (complete attenuation of an infinitely clipped signal), IEEE 754 dictates $\infty \times 0 = \text{NaN}$.
*   **Sanitization:** Blink’s `GainNode` does not actively scrub `NaN` or `Inf` at its output port for performance reasons. However, `NaN` values will poison downstream IIR/Biquad filters and are only sanitized/zeroed out at the final `AudioDestinationNode` before passing to the OS audio backend.

---

### 4. Silent-Input Optimization (Fast-Path)
Blink utilizes a ` silence_bit` optimization on `AudioBus` objects:
*   **Gain = `0.0`:** If the `GainNode` parameter is statically `0.0` across the entire render quantum, Blink skips the vector multiplication, zeroes the output buffer, and flags the output bus as silent (`is_silent = true`). Output amplitude is strictly `0.0`.
*   **Silent Input:** If the input bus is flagged as silent, the `GainNode` passes the silent flag downstream without processing, **unless** the gain value is `NaN` or `Infinity`, which requires explicit handling to prevent state errors.

### 5. Audit Conclusion
The Blink `GainNode` is mathematically transparent. Its output amplitude is bounded only by the limits of 32-bit IEEE 754 floating-point representation (`0.0` or `[\pm 1.18e-38, \pm 3.40e+38]`), relying on hardware FTZ/DAZ to bound extreme attenuation to `0.0`, and deferring hard-clipping (`[-1.0, +1.0]`) to the final hardware destination node.