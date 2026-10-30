## 1. Core Data Structures in Blink Intrinsic Sizing

In Chromium's LayoutNG (`third_party/blink/renderer/core/layout/min_max_sizes.h`), intrinsic inline sizes are represented using fixed-point layout units (`LayoutUnit`, 1/64th of a CSS pixel).

### `MinMaxSizes`
Represents a pair of intrinsic inline sizes: the minimum content size and the maximum content size.
```cpp
struct MinMaxSizes {
  LayoutUnit min_size;
  LayoutUnit max_size;
};
```
* **W3C Mapping:** Maps to the CSS Box Sizing Level 3 §4.1 **min-content inline size** (`min_size`) and **max-content inline size** (`max_size`).

### `MinMaxSizesResult`
Wraps `MinMaxSizes` with a dependency flag used during the intrinsic sizing pass (`ComputeMinMaxSizes`).
```cpp
struct MinMaxSizesResult {
  MinMaxSizes sizes;
  bool depends_on_block_constraints = false;
};
```
* **`depends_on_block_constraints`:** Indicates whether the element's inline intrinsic sizes depend on the available block-size of its containing block (e.g., an orthogonal flow child, or an element with an `aspect-ratio` where block-size is resolved via percentage). If `true`, the parent layout algorithm cannot cache the `MinMaxSizes` across passes that alter block constraints.

### `MinMaxSizesType`
An enumeration used when resolving extrinsic/intrinsic size properties (`min-inline-size`, `max-inline-size`, `inline-size`) during the `ComputeMinMaxSizes` phase:
```cpp
enum class MinMaxSizesType { kContent, kIntrinsic };
```
* **`kContent`:** Evaluates sizing properties strictly for content-based contribution. Percentage sizes are treated as unresolvable (falling back to `auto` / content size), whereas keywords like `min-content`, `max-content`, and `fit-content` are resolved using the element's content sizes.
* **`kIntrinsic`:** Used when evaluating intrinsic size keywords (`min-content`, `max-content`, `fit-content`) specified on `min-width`, `width`, or `max-width`.

---

## 2. Operations on `MinMaxSizes`

Assuming `LayoutUnit` operations under ideal (non-saturating) arithmetic, the core methods on `MinMaxSizes` are defined as follows:

### `operator+=(LayoutUnit length)` / `Add`
Adds a uniform scalar offset (such as inline border, padding, or a fixed margin) to both bounds.
$$\text{Add}((m, M), \Delta) = (m + \Delta, M + \Delta)$$
```cpp
MinMaxSizes& operator+=(LayoutUnit length) {
  min_size += length;
  max_size += length;
  return *this;
}
```

### `operator+=(MinMaxSizes other)`
Component-wise addition, used when accumulating inline flow contributions of inline-level or flex items along the same line.
$$\text{AddPair}((m_1, M_1), (m_2, M_2)) = (m_1 + m_2, M_1 + M_2)$$

### `Encompass(LayoutUnit)` and `Encompass(MinMaxSizes)`
Updates the `MinMaxSizes` to be at least as large as the argument. Used when stacking block-level children vertically (where the container's min/max inline size must accommodate the widest child's min/max inline size).
$$\text{Encompass}((m_1, M_1), (m_2, M_2)) = (\max(m_1, m_2), \max(M_1, M_2))$$
$$\text{Encompass}((m, M), v) = (\max(m, v), \max(M, v))$$
```cpp
void Encompass(LayoutUnit value) {
  min_size = std::max(min_size, value);
  max_size = std::max(max_size, value);
}
void Encompass(const MinMaxSizes& other) {
  min_size = std::max(min_size, other.min_size);
  max_size = std::max(max_size, other.max_size);
}
```

### `ShrinkTo(LayoutUnit value)`
Caps both the `min_size` and `max_size` at a given ceiling (e.g., when a definite `max-inline-size` or `inline-size` constrains the intrinsic contribution).
$$\text{ShrinkTo}((m, M), v) = (\min(m, v), \min(M, v))$$
```cpp
void ShrinkTo(LayoutUnit value) {
  min_size = std::min(min_size, value);
  max_size = std::min(max_size, value);
}
```

### `ClampSizeToMinAndMax(LayoutUnit size)`
Evaluates the CSS `fit-content(size)` formula (CSS Box Sizing Level 3 §5.1). It clamps a given available `size` into the $[min\_size, max\_size]$ interval, strictly prioritizing `min_size`.
$$\text{Clamp}((m, M), s) = \max(m, \min(s, M))$$
```cpp
LayoutUnit ClampSizeToMinAndMax(LayoutUnit size) const {
  return std::max(min_size, std::min(size, max_size));
}
```

---

## 3. Invariant Enforcement & Conflict Resolution

### Internal Invariant: `min_size <= max_size`
Within `MinMaxSizes`, the structural invariant is:
$$0 \le \text{min\_size} \le \text{max\_size}$$
In Blink, leaf nodes initialize `MinMaxSizes` with `0 <= min_size <= max_size`. For text runs, `min_size` is the width of the longest unbreakable word/grapheme cluster, and `max_size` is the width of the entire unwrapped text run. Since a sub-segment cannot exceed the total unbreakable run length (barring negative letter/word-spacing edge cases, which Blink clamps at 0), the base case holds.

### Conflict Resolution: CSS `min-width > max-width`
Note a critical distinction in Blink's architecture: `MinMaxSizes` represents **(min-content, max-content)** sizes, **not** the resolved CSS `min-width` and `max-width` properties. Resolved CSS `min-width` and `max-width` are stored in `MinMaxSizes` *only* when passed to `MinMaxSizes::ClampSizeToMinAndMax(size)` as an abuse of the struct (e.g., `MinMaxSizes{resolved_min_width, resolved_max_width}.ClampSizeToMinAndMax(width)`).

According to **W3C CSS 2.1 §10.4** and **CSS Box Sizing Level 3**:
> If the resulting `min-width` is greater than `max-width`, then `max-width` is set to the value of `min-width` (i.e., `min-width` wins).

In Blink (`ClampSizeToMinAndMax`):
```cpp
LayoutUnit ClampSizeToMinAndMax(LayoutUnit size) const {
  return std::max(min_size, std::min(size, max_size));
}
```
If `min_size > max_size` (representing a CSS conflict where `min-width > max-width`):
1. `std::min(size, max_size)` evaluates to $\le \text{max\_size} < \text{min\_size}$.
2. `std::max(min_size, ...)` therefore **always** evaluates to `min_size`.

Thus, `ClampSizeToMinAndMax` naturally enforces the W3C CSS rule that `min_size` wins over `max_size` without requiring a prior normalization step `max_size = std::max(min_size, max_size)`.

---

## 4. Mathematical Invariants, Edge Cases, and Gaps

### Mathematical Invariants
1. **Bounded Join-Semilattice under `Encompass`:**
   Let $\mathcal{S} = \{(m, M) \in \mathbb{Z}^2 \mid 0 \le m \le M\}$. Equipped with the component-wise partial order $(m_1, M_1) \sqsubseteq (m_2, M_2) \iff m_1 \le m_2 \land M_1 \le M_2$, the operation $\text{Encompass}$ acts as the least upper bound (join, $\sqcup$):
   * **Commutativity:** $A \sqcup B = B \sqcup A$
   * **Associativity:** $(A \sqcup B) \sqcup C = A \sqcup (B \sqcup C)$
   * **Idempotence:** $A \sqcup A = A$
   * **Identity Element:** $\bot = (0, 0)$ for non-negative sizes.
2. **Preservation of `min_size <= max_size` (Validity):**
   If $m_1 \le M_1$ and $m_2 \le M_2$, then:
   * `Add`: $m_1 + \Delta \le M_1 + \Delta$
   * `AddPair`: $m_1 + m_2 \le M_1 + M_2$
   * `Encompass`: $\max(m_1, m_2) \le \max(M_1, M_2)$
   * `ShrinkTo`: $\min(m_1, v) \le \min(M_1, v)$
   * `Encompass(v)`: $\max(m_1, v) \le \max(M_1, v)$
3. **Idempotence of `ClampSizeToMinAndMax`:**
   For any $s$ and any $(m, M)$ (even if $m > M$):
   $$\text{Clamp}((m, M), \text{Clamp}((m, M), s)) = \text{Clamp}((m, M), s)$$

### Edge Cases & Implementation Gaps (Blink vs. W3C Spec)

1. **Saturating Arithmetic in `LayoutUnit` breaks Distributivity and Monotonicity:**
   `LayoutUnit` is a 32-bit signed integer clamped to `[kMin, kMax]` ($\approx \pm 3.35 \times 10^7$ px). Under saturation ($\oplus$):
   * `(A + B) + C != A + (B + C)` if intermediate sums saturate and `C` is negative (e.g., negative margins).
   * However, for $m \le M$, since saturation $\text{sat}(x) = \max(\text{MIN}, \min(\text{MAX}, x))$ is a monotonically non-decreasing function, $m \le M \implies m \oplus \Delta \le M \oplus \Delta$ still holds!
2. **Negative Margins and Non-Negativity Gap:**
   CSS Box Sizing Level 3 §4.1 states that intrinsic sizes of a box are floored at zero. In Blink, a child's outer min/max contribution can temporarily become negative if it has large negative inline margins. Calling `Encompass` on a default-initialized `MinMaxSizes{0, 0}` with a negatively-margined child `{-10, -5}` yields `{0, 0}` because `{0, 0}` acts as an implicit floor, masking the negative contribution rather than shrinking the parent. Blink handles this in specific layout algorithms (like `BlockLayoutAlgorithm`) by clamping outer contributions to `LayoutUnit()` (0) *before* encompassing, or initializing appropriately, which is ad-hoc rather than enforced by the `MinMaxSizes` type.
3. **Floats and `max-content` Spec Divergence:**
   In CSS Box Sizing Level 3, the `max-content` inline size of a block container containing floats is the sum of the `max-content` inline sizes of the floats and the inline content if they do not clear each other. In Blink, `BlockLayoutAlgorithm::ComputeMinMaxSizes` accumulates un-cleared floats using `Add` for `max_size`, and `Encompass` for `min_size`. If a child block has `min_size > max_size` due to broken layout states or negative margins on inline children, the divergence between how `min_size` (Encompass) and `max_size` (Add) accumulate can violate `min_size <= max_size`, requiring Blink to manually enforce `sizes.max_size = std::max(sizes.min_size, sizes.max_size)` at the end of `ComputeMinMaxSizes`.

---

## 5. Formalization in Rocq / Coq (`BlinkMinMaxSizesSemantics.v`)

The following script is a complete, self-contained Rocq/Coq formalization using `ZArith` and `Lia` that models `MinMaxSizes`, `MinMaxSizesResult`, `MinMaxSizesType`, all core operations, and proves all the algebraic and W3C CSS invariants.

```coq
(** * BlinkMinMaxSizesSemantics.v
    Formal verification of Chromium Blink's MinMaxSizes against
    W3C CSS Box Sizing Module Level 3 (Section 4 & 5). *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Bool.Bool.
Require Import Coq.Micromega.Lia.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** LayoutUnit is modeled over Z (arbitrary-precision integers, representing
    1/64th pixel fixed-point units prior to saturation). *)
Definition LayoutUnit := Z.

(** W3C CSS Box Sizing L3 §4.1: min-content and max-content inline sizes. *)
Record MinMaxSizes : Type := mkMinMaxSizes {
  min_size : LayoutUnit;
  max_size : LayoutUnit
}.

(** Blink's MinMaxSizesResult: pairs sizes with block constraint dependency. *)
Record MinMaxSizesResult : Type := mkMinMaxSizesResult {
  sizes : MinMaxSizes;
  depends_on_block_constraints : bool
}.

(** Blink's MinMaxSizesType: distinguishes content vs intrinsic evaluation. *)
Inductive MinMaxSizesType : Type :=
  | kContent
  | kIntrinsic.

(** ** 2. Structural Invariants and Ordering *)

(** Well-formedness invariant: min_size <= max_size *)
Definition Valid (s : MinMaxSizes) : Prop :=
  min_size s <= max_size s.

(** Non-negativity invariant: 0 <= min_size and 0 <= max_size *)
Definition NonNegative (s : MinMaxSizes) : Prop :=
  0 <= min_size s /\ 0 <= max_size s.

(** Strict CSS Box Sizing validity: 0 <= min_size <= max_size *)
Definition StrictlyValid (s : MinMaxSizes) : Prop :=
  0 <= min_size s /\ min_size s <= max_size s.

(** Component-wise partial order on MinMaxSizes *)
Definition le_sizes (s1 s2 : MinMaxSizes) : Prop :=
  min_size s1 <= min_size s2 /\ max_size s1 <= max_size s2.

Infix "<=s" := le_sizes (at level 70).

(** ** 3. Operations on MinMaxSizes *)

(** Default empty sizes {0, 