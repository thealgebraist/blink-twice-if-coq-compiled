# Agent 2 (W3C CSS Flexible Box Layout Level 1 Auditor) Final Report

**Audited Modules**:
- `BlinkFlexboxContainerSemantics.v`
- `BlinkFlexboxSpecialization.v`
**Referenced Specifications & Implementations**:
- W3C CSS Flexible Box Layout Module Level 1 (CR / Current Draft), §9 (Flex Layout Algorithm) & §9.7 (Resolving Flexible Lengths)
- Chromium Blink LayoutNG: `third_party/blink/renderer/core/layout/flex/flexible_box_algorithm.cc` & `flex_layout_algorithm.cc`
**Audit Report Artifact**: [`agent2_w3c_flexbox.md`](file:///Users/anders/projects/testapi/agent2_w3c_flexbox.md)

---

### 1. Mathematical Definition of Target Main Size Under Flex-Grow and Flex-Shrink

#### W3C Section 9.7 Normative Definitions:
1. **Flex-Grow (Positive Free Space)**:
   For unfrozen item $i$:
   $$\text{share}_i = \text{RemainingFreeSpace} \times \frac{\text{flex-grow}_i}{\sum_{j \in \text{Unfrozen}} \text{flex-grow}_j}$$
   $$\text{TargetMainSize}_i = \text{FlexBaseSize}_i + \text{share}_i$$
2. **Flex-Shrink (Negative Free Space)**:
   Each unfrozen item defines a **scaled flex shrink factor**:
   $$w_i = \text{flex-shrink}_i \times \text{InnerFlexBaseSize}_i$$
   The proportional reduction is:
   $$\text{share}_i = |\text{RemainingFreeSpace}| \times \frac{w_i}{\sum_{j \in \text{Unfrozen}} w_j}$$
   $$\text{TargetMainSize}_i = \text{FlexBaseSize}_i - \text{share}_i \quad \left( = \text{FlexBaseSize}_i + \frac{\text{RemainingFreeSpace} \times w_i}{\sum w_j} \right)$$

#### Verification in Coq Modules:
- **`BlinkFlexboxSpecialization.v`**:
  - **Flex-Grow**: Accurately modeled using weights $w_i = \max(0, \text{grow}_i)$ and `distribute_and_detect_violation`.
  - **Flex-Shrink**: Accurately models the W3C scaled flex shrink factor as $w_i = \max(0, \text{shrink}_i \times \text{base}_i)$ (`unfrozen_weight NegativeFlexibility`). Division by zero when $\sum w_j = 0$ is guarded (`total_weight >? 0`).
- **`BlinkFlexboxContainerSemantics.v`**:
  - **Flex-Grow**: Conforms to W3C proportional growth via `sat_clamp (Z.quot (free_space * fis_grow it) total_grow)`.
  - **Flex-Shrink Divergence / Omission**: **Flex-shrink is completely unhandled**. If $\text{free\_space} < 0$, line 73 checks `(free_space >? 0) && (total_grow >? 0)` which evaluates to false, setting `share = 0`. Negative flexibility is ignored, leaving items at their unclamped base sizes.

---

### 2. Space Conservation Invariant (Unconstrained by Min/Max)

#### Theorem in Continuous Arithmetic ($\mathbb{R}$):
When items have unbounded min/max ($\text{min} = -\infty, \text{max} = +\infty$) and flex factors sum to $\ge 1$:
$$\sum_{i=1}^N \text{TargetMainSize}_i \equiv \text{AvailableSpace}$$
This holds identically for both flex-grow and flex-shrink because $\sum \text{share}_i = \text{RemainingFreeSpace} \times \frac{\sum w_i}{\sum w_i} = \text{RemainingFreeSpace}$.

#### Discrete / Fixed-Point Arithmetic Invariant ($\mathbb{Z}$ / `LayoutUnit`):
Due to integer division truncation ($\lfloor \cdot \rfloor$ in `Z.div` / `Z.quot` / `LayoutUnit`):
$$\sum_{i=1}^N \text{TargetMainSize}_i \le \text{AvailableSpace}$$
Total unallocated remainder is bounded by:
$$0 \le \text{AvailableSpace} - \sum_{i=1}^N \text{TargetMainSize}_i \le (N - 1)$$
- **Coq Theorem Status**: Proven in `BlinkFlexboxContainerSemantics.v` as `flex_single_item_space_conservation` for $N = 1$. For $N > 1$, exact equality does not hold in general unless remainder is 0.
- **Blink LayoutNG Behavior**: Blink does *not* redistribute main-axis fractional subpixel remainders across items; the remainder (at most $(N-1) \times \frac{1}{64}\text{px}$) accumulates at the end of the line.

---

### 3. Critical Discrepancies and Edge Cases

1. **Critical Discrepancy — Violation Metric (Size Delta vs Violation Count)**:
   - **W3C §9.7 Step 4.d / Blink LayoutNG C++**:
     $$\text{TotalViolation} = \sum_{i \in \text{Unfrozen}} (\text{ClampedSize}_i - \text{UnclampedSize}_i)$$
     Blink C++ accumulates `LayoutUnit total_violation += clamped_size - raw_target`.
   - **`BlinkFlexboxSpecialization.v` Divergence**:
     Uses `violation_code` mapping `MinViolation -> 1`, `MaxViolation -> -1`, `NoViolation -> 0`, computing $\text{count}(\text{MinViolation}) - \text{count}(\text{MaxViolation})$.
     *Failure Case*: 5 items violate max by $1\text{px}$ each (total $-5\text{px}$) and 1 item violates min by $500\text{px}$ (total $+500\text{px}$). W3C & Blink C++ see $+495\text{px} > 0$ and freeze the min violation; `BlinkFlexboxSpecialization.v` calculates $1 - 5 = -4 < 0$ and freezes the max violations!
2. **Sum of Flex Factors Less Than One ($\sum \text{factor} < 1$)**:
   - W3C §9.7 Step 4.b specifies dampening free space by $\sum \text{factor}$ if $< 1$.
   - Both Coq models use integer $Z$ factors, omitting fractional flex factor support and dampening.
3. **Sign Determination Metric (Step 1)**:
   - W3C specifies comparing available space against the sum of *outer hypothetical main sizes* (clamped base sizes).
   - `BlinkFlexboxSpecialization.v` compares against the sum of *raw flex base sizes*.
4. **Base Size Zero Under Shrink**:
   - Under W3C, an item with base size 0 has scaled shrink factor 0 and cannot shrink. Handled safely in `BlinkFlexboxSpecialization.v` with `total_weight >? 0`.
5. **Single-Pass vs Multi-Pass Redistribution**:
   - `BlinkFlexboxContainerSemantics.v` is purely 1-pass and non-iterative (does not redistribute clamped space).
   - `BlinkFlexboxSpecialization.v` unrolls to 1-pass at Stage 3 (`max_passes := 1`), which is only sound if unconstrained by min/max.

Full documentation, formulas, and recommendations have been written to [`agent2_w3c_flexbox.md`](file:///Users/anders/projects/testapi/agent2_w3c_flexbox.md).
