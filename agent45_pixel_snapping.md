# Audit Report: Chromium Blink Pixel Snapping vs. CSS Subpixel Rendering
**Agent:** 45  
**Target:** Chromium Blink Rendering Engine (`third_party/blink/renderer/platform/geometry/`)  
**Formalization Target:** `BlinkPixelSnappingSemantics.v`

---

## 1. Core Data Structures in Blink Pixel Snapping

Modern web engines must balance the mathematical continuity of CSS layout (which operates in floating-point or subpixel space) against the discrete nature of physical display hardware (the device pixel grid). If subpixel boxes are handed directly to a rasterizer (like Skia) without alignment, anti-aliasing filters blend edges across pixel boundaries, resulting in blurry 2px borders, washed-out hairlines, and Moiré patterns.

Chromium’s Blink engine resolves this via **Subpixel Layout coupled with Paint-Time Pixel Snapping**. Layout is computed in fractional units, and geometries are snapped to integer boundaries just prior to paint generation.

### 1.1 `LayoutUnit`
To avoid the non-determinism, performance penalties, and precision drift (e.g., Associativity failures, IEEE 754 rounding anomalies across architectures) of `float` and `double`, Blink utilizes a deterministic fixed-point representation called `LayoutUnit`.

* **Representation:** A 32-bit signed integer (`int32_t`).
* **Scaling Factor:** `kFixedPointDenominator = 64` ($2^6$). 
* **Fractional Precision:** 6 bits of fractional precision, representing increments of $\frac{1}{64} = 0.015625$ CSS pixels.
* **Integer Range:** 25 bits of magnitude plus 1 sign bit, yielding a range of $[-33554432, 33554431.984375]$ pixels (`INT32_MIN / 64` to `INT32_MAX / 64`).
* **Saturating Arithmetic:** Operations on `LayoutUnit` use saturating arithmetic (`base::ClampedNumeric`) to prevent integer overflow Wrap-Around bugs during layout calculations.

```cpp
// Conceptual representation of blink::LayoutUnit
class LayoutUnit {
  static constexpr int kFractionalBits = 6;
  static constexpr int kFixedPointDenominator = 1 << kFractionalBits; // 64
  int32_t value_; // Stores (real_pixel_value * 64)
};
```

### 1.2 Geometric Primitives (`PhysicalRect` / `LayoutRect` vs. `gfx::Rect`)
During the Layout phase, boxes are represented as `PhysicalRect` (composed of `PhysicalOffset` $(x, y)$ and `PhysicalSize` $(width, height)$, all using `LayoutUnit`). During PrePaint and Paint phases, these must be lowered to `gfx::Rect` (composed of `gfx::Point` and `gfx::Size`, using standard `int`).

The bridge between these two worlds consists of three core routines:
* `RoundToInt(LayoutUnit)` (The implementation of `RoundToPixel`)
* `SnapSizeToPixel(LayoutUnit size, LayoutUnit location)`
* `ToPixelSnappedRect(const PhysicalRect&)` (The implementation of `SnapRectToPixel`)

---

## 2. Snapping Functions and Fixed-Point Bitwise Mechanics

The fundamental design error in naive pixel snapping is rounding a box's `location` and `size` independently. Blink prevents this by making the snapped size a function of **both** the subpixel size and the subpixel location.

### 2.1 `RoundToPixel` (`LayoutUnit::Round`)
Mathematically, for a real value $v \in \mathbb{R}$, nearest-pixel rounding with ties rounding toward positive infinity ($+\infty$) is defined as:
$$\text{RoundToPixel}(v) = \lfloor v + 0.5 \rfloor$$

In Blink's $1/64$ fixed-point domain, $v$ is represented as an integer $V = 64v$. The value $0.5$ is represented as $32$ ($0.5 \times 64$, or `kFixedPointDenominator / 2`). Floor division by $64$ is equivalent to an arithmetic right shift by 6 bits (`>> 6`), which in C++ rounds toward $-\infty$ for two's complement signed integers.

Thus, for a raw `LayoutUnit` value $V$:
$$\text{RoundToPixel}(V) = (V + 32) \gg 6 = \left\lfloor \frac{V + 32}{64} \right\rfloor$$

* **Boundary Analysis:**
  * If $v = 1.49 \implies V = \lfloor 1.49 \times 64 \rfloor = 95$. $(95 + 32) \gg 6 = 127 \gg 6 = 1$.
  * If $v = 1.50 \implies V = 96$. $(96 + 32) \gg 6 = 128 \gg 6 = 2$.
  * If $v = -0.50 \implies V = -32$. $(-32 + 32) \gg 6 = 0 \gg 6 = 0$.
  * If $v = -0.515625 \implies V = -33$. $(-33 + 32) \gg 6 = -1 \gg 6 = -1$.

### 2.2 `SnapSizeToPixel`
To compute the snapped width (or height) of a segment starting at `location` with length `size`, Blink does not round `size` directly. Instead, it snaps the **start edge** and the **end edge** to the pixel grid independently, and defines the snapped size as the distance between the two snapped edges:

$$\text{SnapSizeToPixel}(\text{size}, \text{loc}) = \text{RoundToPixel}(\text{loc} + \text{size}) - \text{RoundToPixel}(\text{loc})$$

In fixed-point terms ($L = \text{loc}, S = \text{size}$):
$$\text{SnapSizeToPixel}(S, L) = \left\lfloor \frac{(L + S) + 32}{64} \right\rfloor - \left\lfloor \frac{L + 32}{64} \right\rfloor$$

---

## 3. Snapping Rectangular Bounds: Preserving Visual Adjacency

Consider a 1D horizontal layout containing two abutting sibling inline-blocks or flex items, $A$ and $B$, placed inside a container.

Suppose:
* Box $A$ has `location` $x_A = 0.0\text{px}$ and `size` $w_A = 10.4\text{px}$.
* Box $B$ immediately abuts Box $A$, so $x_B = x_A + w_A = 10.4\text{px}$, and let $w_B = 10.4\text{px}$.

### 3.1 The Failure of Independent Rounding (Naive Snapping)
If an engine snaps position and size independently ($\hat{x} = \text{Round}(x), \hat{w} = \text{Round}(w)$):
* **Box A:** $\hat{x}_A = \text{Round}(0.0) = 0$. $\hat{w}_A = \text{Round}(10.4) = 10$.  
  Box A covers pixels $[0, 10)$. Its right edge is at $10\text{px}$.
* **Box B:** $\hat{x}_B = \text{Round}(10.4) = 10$. $\hat{w}_B = \text{Round}(10.4) = 10$.  
  Box B covers pixels $[10, 20)$.

Now suppose $w_A = 10.4\text{px}$ and $x_A = 0.2\text{px}$:
* **Box A:** $x_A = 0.2, w_A = 10.4 \implies \text{right}_A = 10.6$.  
  Naive snap: $\hat{x}_A = \text{Round}(0.2) = 0$, $\hat{w}_A = \text{Round}(10.4) = 10 \implies \text{snapped\_right}_A = 0 + 10 = 10$.
* **Box B:** $x_B = 10.6, w_B = 10.4$.  
  Naive snap: $\hat{x}_B = \text{Round}(10.6) = 11$, $\hat{w}_B = \text{Round}(10.4) = 10$.
* **Result:** Box A ends at pixel $10$, and Box B begins at pixel $11$. **A 1-pixel transparent seam (gap) appears at pixel $[10, 11)$**, bleeding the background color through two elements that CSS specifies as touching.

Conversely, if $x_A = 0.4, w_A = 10.4 \implies x_B = 10.8$:
* Naive snap with $w_A = 10.6, x_A = 0.4 \implies x_B = 11.0$:
  $\hat{x}_A = 0, \hat{w}_A = 11 \implies \text{snapped\_right}_A = 11$.
  If $x_A = 0.6, w_A = 10.6 \implies x_B = 11.2$:
  $\hat{x}_A = 1, \hat{w}_A = 11 \implies \text{snapped\_right}_A = 12$.
  $\hat{x}_B = \text{Round}(11.2) = 11$.
* **Result:** Box A ends at $12$, Box B starts at $11$. **A 1-pixel overlap occurs at pixel $[11, 12)$**, causing dark lines if the boxes have semi-transparent backgrounds (`rgba`).

### 3.2 Blink's `SnapRectToPixel` Resolution
Blink defines `SnapRectToPixel` for a 2D `PhysicalRect` $R = (x, y, w, h)$ as:

$$\text{SnapRectToPixel}(x, y, w, h) = \begin{pmatrix} \hat{x} = \text{RoundToPixel}(x) \\ \hat{y} = \text{RoundToPixel}(y) \\ \hat{w} = \text{SnapSizeToPixel}(w, x) \\ \hat{h} = \text{SnapSizeToPixel}(h, y) \end{pmatrix}$$

Let us re-evaluate the failing gap case ($x_A = 0.2, w_A = 10.4 \implies x_B = 10.6, w_B = 10.4$) using Blink's formulation:
* **Box A:**
  * $\hat{x}_A = \text{RoundToPixel}(0.2) = 0$
  * $\hat{w}_A = \text{RoundToPixel}(0.2 + 10.4) - \text{RoundToPixel}(0.2) = \text{RoundToPixel}(10.6) - 0 = 11 - 0 = 11$.
  * Box A covers $[0, 11)$. Its right edge is $0 + 11 = 11$.
* **Box B:**
  * $\hat{x}_B = \text{RoundToPixel}(10.6) = 11$.
  * $\hat{w}_B = \text{RoundToPixel}(10.6 + 10.4) - \text{RoundToPixel}(10.6) = \text{RoundToPixel}(21.0) - 11 = 21 - 11 = 10$.
  * Box B covers $[11, 21)$. Its left edge is $11$.

Notice the trade-off Blink makes: although $w_A$ and $w_B$ are identical in CSS space ($10.4\text{px}$), Box A renders at $11\text{px}$ wide while Box B renders at $10\text{px}$ wide. Blink intentionally sacrifices **size translation invariance** ($\pm 1\text{px}$ size jitter depending on subpixel offset) in order to strictly guarantee **topological adjacency preservation** (zero gaps, zero overlaps).

---

## 4. Mathematical Invariants

Let $\mathbb{L}$ be the domain of `LayoutUnit` (modeled over $\mathbb{Z}$ where $1\text{px} = 64$ units). Let a 1D interval be $I = (x, w) \in \mathbb{L} \times \mathbb{L}$ with $\text{left}(I) = x$ and $\text{right}(I) = x + w$. Let $\text{Snap}(I) = (\hat{x}, \hat{w})$ be the snapped interval in pixel space $\mathbb{P}$ (where $1\text{px} = 1$ unit, or $64$ units if embedded back into $\mathbb{L}$).

### Invariant 1: Exact Adjacency Preservation (No Gaps, No Overlaps)
For any two subpixel intervals $A = (x_A, w_A)$ and $B = (x_B, w_B)$, if the right edge of $A$ is equal to the left edge of $B$ in subpixel space ($\text{right}(A) = \text{left}(B)$), then the snapped right edge of $A$ is strictly equal to the snapped left edge of $B$.

**Proof:**
$$\text{right}(\text{Snap}(A)) = \hat{x}_A + \hat{w}_A$$
$$= \text{RoundToPixel}(x_A) + \big(\text{RoundToPixel}(x_A + w_A) - \text{RoundToPixel}(x_A)\big)$$
By additive cancellation of $\text{RoundToPixel}(x_A)$:
$$= \text{RoundToPixel}(x_A + w_A)$$
Since $x_A + w_A = \text{right}(A) = \text{left}(B) = x_B$:
$$= \text{RoundToPixel}(x_B) = \hat{x}_B = \text{left}(\text{Snap}(B)) \quad \blacksquare$$

### Invariant 2: Partition Conservation (Telescoping Sum Invariant)
For a sequence of $n$ mutually abutting boxes $B_1, B_2, \dots, B_n$ where $x_{i+1} = x_i + w_i$, the sum of their snapped widths exactly equals the snapped width of their bounding container $C = (x_1, \sum_{i=1}^n w_i)$:
$$\sum_{i=1}^n \hat{w}_i = \sum_{i=1}^n \big(\text{RoundToPixel}(x_i + w_i) - \text{RoundToPixel}(x_i)\big) = \text{RoundToPixel}(x_n + w_n) - \text