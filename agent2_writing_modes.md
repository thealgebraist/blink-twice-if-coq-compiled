### 1. Core Data Structures in Chromium Blink

In Chromium’s LayoutNG (`third_party/blink/renderer/core/layout/geometry/` and `platform/text/`), coordinate spaces are strictly typed to prevent accidental mixing of logical (flow-relative) and physical (screen-relative) geometry. All layout units are backed by `LayoutUnit`, a 32-bit fixed-point value with 6 fractional bits ($\frac{1}{64}$ pixel precision).

#### Enumerations
*   **`WritingMode`** (`writing_mode.h`):
    ```cpp
    enum class WritingMode : unsigned {
      kHorizontalTb = 0,
      kVerticalRl = 1,
      kVerticalLr = 2,
      kSidewaysRl = 3,
      kSidewaysLr = 4,
    };
    ```
    *Note*: `WritingMode` defines the block flow direction and whether the inline base direction is horizontal or vertical.
*   **`TextDirection`** (`text_direction.h`):
    ```cpp
    enum class TextDirection : uint8_t { kLtr = 0, kRtl = 1 };
    ```
*   **`WritingDirectionMode`** (`writing_direction_mode.h`): A tuple $(\text{WritingMode}, \text{TextDirection})$ that encapsulates the complete flow transformation context.

#### Geometry Primitives
*   **`LogicalSize`**: `{ LayoutUnit inline_size; LayoutUnit block_size; }`
*   **`PhysicalSize`**: `{ LayoutUnit width; LayoutUnit height; }`
*   **`LogicalOffset`**: `{ LayoutUnit inline_offset; LayoutUnit block_offset; }` — Represents an offset from the *logical start* corner of a box (inline-start, block-start).
*   **`PhysicalOffset`**: `{ LayoutUnit left; LayoutUnit top; }` — Represents an offset from the *top-left* physical corner of a box.

#### `WritingModeConverter`
`WritingModeConverter` (`writing_mode_converter.h`) is the state-carrying functor that mediates between logical and physical coordinate spaces. Because physical coordinates are always anchored at the top-left of a container, while logical coordinates may be anchored at the top-right, bottom-left, or bottom-right depending on the mode, **coordinate conversion of a child box requires the size of both the outer container and the inner child box**.

```cpp
class WritingModeConverter {
  WritingDirectionMode writing_direction_;
  PhysicalSize outer_size_;
};
```

---

### 2. Coordinate Transform Calculus

Let $W, H$ be the physical width and height of the outer container (`outer_size`).
Let $w, h$ be the physical width and height of the inner child box (`inner_size`).
Let $(I, B)$ be the `LogicalOffset` and $(X, Y)$ be the `PhysicalOffset`.

The dimension mapping (size conversion) depends solely on whether the `WritingMode` is horizontal (`kHorizontalTb`) or vertical (`kVerticalRl`, `kVerticalLr`, `kSidewaysRl`, `kSidewaysLr`):

$$\text{ToPhysical}(s_{\text{inline}}, s_{\text{block}}) = \begin{cases} 
(s_{\text{inline}}, s_{\text{block}}) & \text{if } \text{WM} = \text{kHorizontalTb} \\
(s_{\text{block}}, s_{\text{inline}}) & \text{otherwise}
\end{cases}$$

#### Complete Orientation Matrix

| WritingMode | TextDirection | Inline Flow | Block Flow | Logical Origin (Physical Corner) | Physical $(X, Y)$ from $(I, B)$ | Logical $(I, B)$ from $(X, Y)$ |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`horizontal-tb`** | `LTR` | $\rightarrow$ ($+X$) | $\downarrow$ ($+Y$) | Top-Left $(0, 0)$ | $X = I$<br>$Y = B$ | $I = X$<br>$B = Y$ |
| **`horizontal-tb`** | `RTL` | $\leftarrow$ ($-X$) | $\downarrow$ ($+Y$) | Top-Right $(W, 0)$ | $X = W - I - w$<br>$Y = B$ | $I = W - X - w$<br>$B = Y$ |
| **`vertical-rl`**<br>**`sideways-rl`** | `LTR` | $\downarrow$ ($+Y$) | $\leftarrow$ ($-X$) | Top-Right $(W, 0)$ | $X = W - B - w$<br>$Y = I$ | $I = Y$<br>$B = W - X - w$ |
| **`vertical-rl`**<br>**`sideways-rl`** | `RTL` | $\uparrow$ ($-Y$) | $\leftarrow$ ($-X$) | Bottom-Right $(W, H)$ | $X = W - B - w$<br>$Y = H - I - h$ | $I = H - Y - h$<br>$B = W - X - w$ |
| **`vertical-lr`** | `LTR` | $\downarrow$ ($+Y$) | $\rightarrow$ ($+X$) | Top-Left $(0, 0)$ | $X = B$<br>$Y = I$ | $I = Y$<br>$B = X$ |
| **`vertical-lr`** | `RTL` | $\uparrow$ ($-Y$) | $\rightarrow$ ($+X$) | Bottom-Left $(0, H)$ | $X = B$<br>$Y = H - I - h$ | $I = H - Y - h$<br>$B = X$ |
| **`sideways-lr`** | `LTR` | $\uparrow$ ($-Y$) | $\rightarrow$ ($+X$) | Bottom-Left $(0, H)$ | $X = B$<br>$Y = H - I - h$ | $I = H - Y - h$<br>$B = X$ |
| **`sideways-lr`** | `RTL` | $\downarrow$ ($+Y$) | $\rightarrow$ ($+X$) | Top-Left $(0, 0)$ | $X = B$<br>$Y = I$ | $I = Y$<br>$B = X$ |

*Crucial Observation on `sideways-lr`*: Unlike `vertical-lr` where `LTR` flows top-to-bottom ($\downarrow$), in `sideways-lr`, `LTR` flows bottom-to-top ($\uparrow$). Thus, `sideways-lr` flips the inline-axis polarity relative to `vertical-lr`.

---

### 3. Mathematical Formulas for Bijection

Let $\mathcal{C} = (\text{WM}, \text{Dir}, W, H)$ be the `WritingModeConverter` state, and $s = (w, h)$ be the `PhysicalSize` of the inner box (if given a `LogicalSize`, it is first converted to `PhysicalSize` via the dimension mapping above).

#### Forward Transform: `ToPhysicalOffset`
$$\Phi_{\mathcal{C}, s}(I, B) = (X, Y)$$

$$X = \begin{cases} 
I & \text{if } (\text{WM} = \text{HTB} \land \text{Dir} = \text{LTR}) \\
W - I - w & \text{if } (\text{WM} = \text{HTB} \land \text{Dir} = \text{RTL}) \\
B & \text{if } \text{WM} \in \{\text{VLR}, \text{SLR}\} \\
W - B - w & \text{if } \text{WM} \in \{\text{VRL}, \text{SRL}\}
\end{cases}$$

$$Y = \begin{cases} 
B & \text{if } \text{WM} = \text{HTB} \\
I & \text{if } (\text{WM} \in \{\text{VRL}, \text{SRL}, \text{VLR}\} \land \text{Dir} = \text{LTR}) \lor (\text{WM} = \text{SLR} \land \text{Dir} = \text{RTL}) \\
H - I - h & \text{if } (\text{WM} \in \{\text{VRL}, \text{SRL}, \text{VLR}\} \land \text{Dir} = \text{RTL}) \lor (\text{WM} = \text{SLR} \land \text{Dir} = \text{LTR})
\end{cases}$$

#### Inverse Transform: `ToLogicalOffset`
$$\Psi_{\mathcal{C}, s}(X, Y) = (I, B)$$

$$I = \begin{cases} 
X & \text{if } (\text{WM} = \text{HTB} \land \text{Dir} = \text{LTR}) \\
W - X - w & \text{if } (\text{WM} = \text{HTB} \land \text{Dir} = \text{RTL}) \\
Y & \text{if } (\text{WM} \in \{\text{VRL}, \text{SRL}, \text{VLR}\} \land \text{Dir} = \text{LTR}) \lor (\text{WM} = \text{SLR} \land \text{Dir} = \text{RTL}) \\
H - Y - h & \text{if } (\text{WM} \in \{\text{VRL}, \text{SRL}, \text{VLR}\} \land \text{Dir} = \text{RTL}) \lor (\text{WM} = \text{SLR} \land \text{Dir} = \text{LTR})
\end{cases}$$

$$B = \begin{cases} 
Y & \text{if } \text{WM} = \text{HTB} \\
X & \text{if } \text{WM} \in \{\text{VLR}, \text{SLR}\} \\
W - X - w & \text{if } \text{WM} \in \{\text{VRL}, \text{SRL}\}
\end{cases}$$

*(Notice that for $\text{WM} = \text{HTB}$, $\Phi$ and $\Psi$ are identical functions: self-inverting reflections).*

---

### 4. Invariants

1.  **Bijective Involution (Round-Trip Identity)**:
    Over $\mathbb{Z}$ (infinite precision integer / ideal fixed-point arithmetic without saturation), for all valid $\mathcal{C}$ and $s$:
    $$\forall L \in \text{LogicalOffset}, \quad \Psi_{\mathcal{C}, s}(\Phi_{\mathcal{C}, s}(L)) = L$$
    $$\forall P \in \text{PhysicalOffset}, \quad \Phi_{\mathcal{C}, s}(\Psi_{\mathcal{C}, s}(P)) = P$$
2.  **Bounded Non-Negativity Preservation (Containment Invariant)**:
    Logical coordinates are non-negative when a child box is strictly inside its container's logical bounds. Physical coordinates are non-negative when the child is inside the physical bounds.
    Let $L = (I, B)$ and $s_{\text{log}} = (s_I, s_B)$ be the logical size of the inner box, and $S_{\text{log}} = (S_I, S_B)$ be the logical size of the outer container.
    $$\text{If } 0 \le I \land I + s_I \le S_I \land 0 \le B \land B + s_B \le S_B$$
    $$\text{Then } \Phi_{\mathcal{C}, s}(I, B) = (X, Y) \text{ satisfies } 0 \le X \le W - w \land 0 \le Y \le H - h$$
3.  **Zero-Size Point Duality**:
    When transforming a *point* rather than a *box* (e.g., cursor offset or scroll origin), `inner_size` is $(0, 0)$. The formulas degenerate cleanly to pure affine reflections $W - I$ and $H - B$.
4.  **Outer-Size Independence for Purely Positive Flows**:
    If $(\text{WM}, \text{Dir}) \in \{(\text{HTB}, \text{LTR}), (\text{VLR}, \text{LTR}), (\text{SLR}, \text{RTL})\}$, then $\Phi_{\mathcal{C}, s}$ and $\Psi_{\mathcal{C}, s}$ are completely independent of $W, H, w, h$. In Blink, developers frequently introduce bugs when testing only in `HTB/LTR` or `VLR/LTR` by passing an uninitialized `outer_size` or `(0,0)` `inner_size` to `WritingModeConverter`, which only manifests as visual corruption in `RTL` or `vertical-rl`.

---

### 5. Edge Cases & Divergences: Blink LayoutNG vs. W3C CSS Writing Modes Level 3/4

1.  **`LayoutUnit` Saturated Arithmetic Breaks Involution**:
    W3C CSS assumes real-number geometry ($\mathbb{R}^2$). Blink uses `LayoutUnit` (`int32_t` clamped to `[kMin, kMax]`). When $W$, $I$, or $w$ approaches `LayoutUnit::Max()` ($\approx 3.35 \times 10^7$ px), the subtraction $W - I - w$ can saturate (clamp) if $I < 0$ (e.g., extreme negative margins or out-of-flow positioning). Once saturated, $\Psi(\Phi(L)) \neq L$.
2.  **CSS Level 3 vs. Level 4 `sideways-*` Specification**:
    W3C CSS Writing Modes Level 3 deferred `sideways-rl` and `sideways-lr` to Level 4 (retaining only `horizontal-tb`, `vertical-rl`, `vertical-lr` in L3). However, Blink implements `kSidewaysRl` and `kSidewaysLr` directly in the core `WritingMode` enum to support both CSS Writing Modes Level 4 and legacy SVG/text-orientation mappings.
3.  **`vertical-rl` vs `sideways-rl` Geometric Indistinguishability**:
    At the box-geometry level (`WritingModeConverter`), `kVerticalRl` and `kSidewaysRl` are **100% identical** in their coordinate transforms. Their divergence in Blink exists exclusively in inline layout (`FontBaseline`, glyph orientation, and typographic baseline alignment: `vertical-rl` uses central baselines for CJK, whereas `sideways-rl` uses alphabetic baselines rotated $90^\circ$ clockwise).
4.  **Indefinite Container Sizes (`kIndefiniteSize = -1`)**:
    During the intrinsic sizing or initial block-size measurement passes in LayoutNG, the outer container's block size (e.g., $W$ in `vertical-rl` or $H$ in `horizontal-tb`) is unknown and set to `kIndefiniteSize` ($-1$). Calling `WritingModeConverter::ToPhysicalOffset` during this phase in `vertical-rl` yields garbage negative physical X coordinates ($X = -1 - B - w$). Blink enforces an architectural invariant: *All layout happens in Logical space; `WritingModeConverter` is only instantiated after fragment physical sizes are finalized.*
5.  **Line-Relative Directions (`line-left`, `line-right`)**:
    W3C CSS Writing Modes §6.3 defines a *third* coordinate system: **Line-Relative** (`line-left`,