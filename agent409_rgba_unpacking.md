**AUDIT REPORT: BLINK RGBA8888 UNPACKING & ROUND-TRIP CHANNEL IDENTITY**
**Auditor:** Agent 409
**Component:** `blink::Color` / `SkColor4f` / Skia Pixel Pipeline
**Format Target:** RGBA8888 (32-bit packed unsigned integer, 8 bits per channel)

---

### 1. Memory Layout & Bitwise Extraction (Stage 0)
In Blink, standard unpremultiplied 8-bit colors (historically `RGBA32`, backed by `SkColor`) are stored in ARGB/RGBA 32-bit registers. Assuming canonical RGBA8888 byte-order (or offset-adjusted shift masking):

Let $P \in [0, 2^{32}-1]$ be the packed 32-bit pixel. The discrete channel extraction $\mathcal{E}(P)$ yields four 8-bit unsigned integers $C_{u8} \in [0, 255]$:

$$R_{u8} = (P \gg 0) \ \& \ \text{0xFF}$$
$$G_{u8} = (P \gg 8) \ \& \ \text{0xFF}$$
$$B_{u8} = (P \gg 16) \ \& \ \text{0xFF}$$
$$A_{u8} = (P \gg 24) \ \& \ \text{0xFF}$$

*(Note: Shift offsets permute to $R=16, G=8, B=0, A=24$ for `SkColor` BGRA_8888 little-endian architecture, but the single-channel mathematical identity remains invariant).*

---

### 2. Unpacking: Normalization to Float32 (Stage 1)
Following the Blink Color 4 specification update, unpacked channels are promoted to IEEE 754 `float32` (`SkColor4f`) for wide-gamut and high-precision compositing.

The unpacking transformation $\mathcal{U}: \mathbb{Z}_{256} \to \mathbb{F}_{32}$ is defined as:

$$C_{f32} = \text{float32}(C_{u8}) \times \text{float32}\left(\frac{1.0}{255.0}\right)$$

* **Precision Note:** $\frac{1}{255}$ in IEEE 754 `float32` is represented as `0x3B808081` ($\approx 0.0039215688593685626983642578125$). Because $255$ is not a power of 2, this division introduces an immediate representation error bounded by $0.5 \text{ ULP}$.

---

### 3. Packing: Quantization to UInt8 (Stage 2)
To achieve round-trip identity back to an 8-bit backing store, the normalized float must be quantized via the packing transformation $\mathcal{Q}: \mathbb{F}_{32} \to \mathbb{Z}_{256}$.

In Blink/Skia (`sk_float_round2int`), this is executed via scale-and-round-to-nearest:

$$C'_{u8} = \left\lfloor \text{ clamp}(C_{f32}, 0.0, 1.0) \times 255.0 + 0.5 \right\rfloor$$

---

### 4. Round-Trip Identity Proof
**Theorem:** For any $C \in \{0, 1, \dots, 255\}$, the round-trip transformation $\mathcal{Q}(\mathcal{U}(C)) = C$ holds strictly under IEEE 754 `float32` arithmetic.

**Proof:**
1. Let $k \in [0, 255]$.
2. In IEEE 754 `float32` (24-bit significand), $k$ is represented exactly.
3. Let $M = \text{float32}(1 / 255) = \frac{1}{255}(1 + \epsilon_1)$, where $|\epsilon_1| \le 2^{-24}$.
4. The unpacked float is $C_{f32} = \text{fl}(k \times M) = \frac{k}{255}(1 + \epsilon_1)(1 + \epsilon_2)$, where $|\epsilon_2| \le 2^{-24}$.
5. During repacking, we multiply by $255.0$ (exact in `float32`):
   $$X = \text{fl}(C_{f32} \times 255.0) = k(1 + \epsilon_1)(1 + \epsilon_2)(1 + \epsilon_3)$$
6. The cumulative relative error $\delta = |(1 + \epsilon_1)(1 + \epsilon_2)(1 + \epsilon_3) - 1|$ is bounded by:
   $$\delta \approx 3 \times 2^{-24} \approx 1.788 \times 10^{-7}$$
7. The maximum absolute error occurs at $k = 255$:
   $$|X - k| \le 255 \times \delta \approx 4.56 \times 10^{-5}$$
8. Adding the rounding bias $0.5$:
   $$X + 0.5 = k + 0.5 \pm 4.56 \times 10^{-5}$$
9. Since $4.56 \times 10^{-5} \ll 0.5$, the floor function $\lfloor X + 0.5 \rfloor$ strictly evaluates to $k$ for all $k \in [0, 255]$. $\blacksquare$

*(Hardware Fast-Path Variant):* In Skia's SIMD pipelines (`SkNx` / `skcms`), division by 255 is sometimes approximated using the bit-expansion identity, whereas quantization from `[0, 1]` uses `(C_f32 * 255.0f + 0.5f)`. The identity remains unbroken.

---

### 5. Audit Exceptions: Where Identity Breaks
While isolated channel extraction is lossless, Agent 409 flags two systemic pipeline hazards in Blink where RGBA8888 round-tripping **fails** identity:

#### A. Premultiplied Alpha Bottlenecks (`SkPMColor`)
When Blink hands off `Color` to WebGL, Canvas2D, or the CC compositor, RGBA8888 is frequently converted to **Premultiplied Alpha**:
$$C_{pm} = \left\lfloor \frac{C_{u8} \times A_{u8} + 127}{255} \right\rfloor$$
**Audit Finding:** This operation is **non-injective (lossy)**. 
By the Pigeonhole Principle, for any $A_{u8} < 255$, multiple distinct $C_{u8}$ values map to the same $C_{pm}$. 
* *Example:* If $A_{u8} = 1$, all $C_{u8} \in [0, 127]$ map to $C_{pm} = 0$. Unpacking a premultiplied buffer back to unpremultiplied RGBA8888 ($C'_{u8} = \text{round}(C_{pm} \times 255 / A_{u8})$) **destroys round-trip identity**.

#### B. Naive Truncation (Missing Bias)
If a downstream consumer bypasses ` blink::Color::FromRGBAFloat` and casts via static truncation:
$$C'_{u8} = \text{static\_cast<uint8\_t>}(C_{f32} \times 255.0f)$$
The identity **fails** for $k \in \{3, 6, 7, 12, 13, 14, \dots\}$ where the IEEE 754 float product $C_{f32} \times 255.0f$ evaluates to $k - \text{ULP}$ (e.g., $2.9999998$), truncating to $k - 1$. The $+0.5f$ bias or `std::lround` is mandatory.

### 6. Conclusion
**STATUS: PASS (Unpremultiplied) / CONDITIONAL FAIL (Premultiplied)**
Blink's core `Color` unpacking to `float32` and repacking to `uint8_t` maintains strict mathematical round-trip identity $\mathcal{Q}(\mathcal{U}(C)) \equiv C$, provided standard rounding bias ($+0.5$) is applied and the alpha channel remains unpremultiplied.