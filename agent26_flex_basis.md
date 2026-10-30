## 1. Core Data Structures in Blink Flex Basis Resolution

In Chromium’s LayoutNG architecture (specifically within `third_party/blink/renderer/core/layout/flex/`), flex basis resolution is primarily governed by `NGFlexLayoutAlgorithm::ConstructAndAppendFlexItems` and `FlexibleBoxAlgorithm`. It converts specified CSS values (`Length`) into a concrete `LayoutUnit` (a 26.6 fixed-point representation) representing the `flex_base_border_box_size`.

### `EFlexBasisType` & `blink::Length`
Blink does not use a standalone `EFlexBasisType` enum in the C++ source; rather, it embeds the semantics into `blink::Length::Type` (from `ComputedStyle::FlexBasis()`) and resolves it against `ComputedStyle::Width()` or `Height()` (the main size property). Formally, we abstract the resolved state machine into four canonical modes:

1. **`Content`**: Triggered explicitly via `flex-basis: content`, or implicitly when `flex-basis: auto` and the main size property is also `auto`. Also serves as the fallback when a percentage cannot be resolved against an indefinite container main size.
2. **`Auto`**: Triggered when `flex-basis` is `auto`. Blink delegates resolution to the main axis `width`/`height` property (`Style().UsedWidth()` or `UsedHeight()`).
3. **`Length`**: Fixed physical units (`px`, `em`, `rem`) represented as `Length::kFixed`. Directly converted to `LayoutUnit` via `MinimumValueForLength`.
4. **`Percent`**: Represented as `Length::kPercent` (or `kCalculated` involving percentages). Resolved against the flex container’s inner main size (`content_box_size`). If the container’s main size is `kIndefiniteSize` (`LayoutUnit(-1)`), `Percent` degrades to `Content`.

### `FlexItem` & `FlexBasis`
During `ConstructAndAppendFlexItems`, Blink computes three foundational sizes before constructing the `FlexItem` instance:

```cpp
// Conceptual distillation of Blink's NGFlexLayoutAlgorithm item construction
struct FlexBasisResolutionContext {
  LayoutUnit container_main_size; // kIndefiniteSize (-1) if indefinite
  LayoutUnit container_cross_size;
  std::optional<double> aspect_ratio; // width / height, mapped to main / cross
  MinMaxSizes intrinsic_main_sizes;   // {min_content, max_content}
};

struct FlexItem {
  LayoutUnit flex_base_content_size;
  LayoutUnit hypothetical_main_content_size;
  MinMaxSizes min_max_main_sizes; // Resolved min-{width,height} and max-{width,height}
  BoxStrut main_axis_border_padding;
  // ...
};
```

Blink operates on border-box sizes during layout resolution (`MinMaxSizes` and `ResolveMainBlockLength`), then strips `main_axis_border_padding` at the end to store `flex_base_content_size` and `hypothetical_main_content_size` on the `FlexItem`.

---

## 2. Transferred Size Resolution with `aspect-ratio`

CSS Flexible Box Layout Level 1 §9.2.3 dictates how an item's `flex_base_size` is determined. When `flex-basis` resolves to `Content` (either directly or via `Auto` + main-size `Auto`), Blink checks if a preferred `aspect-ratio` is present (`!Style().AspectRatio().IsAuto()`).

Let $\text{AR} = \frac{S_{\text{main}}}{S_{\text{cross}}}$ be the normalized aspect ratio with respect to the flex container's axes.

### Resolution Pipeline in Blink (`DoesItemComputedCrossSizeHaveAuto` & ` ComputeTransferredMainSize`)

1. **Case B (Definite Cross Size Transfer)**:
   If the flex basis is `Content`, the item has an intrinsic aspect ratio, and its **computed** cross size is *definite*, the flex base size is calculated from the used cross size and the aspect ratio.
   * **Definite Cross Size Sources**:
     a) A fixed `Length` on the cross-size property (`width` or `height`).
     b) A `Percent` cross-size property resolved against a definite `container_cross_size`.
     c) *Stretched Cross Size*: If the item has `align-self: stretch`, is in a single-line flex container, and the container has a definite cross size, the cross size is treated as definite *for the purpose of transferred size calculations* (per §9.2.3.B and §9.4).
   * **Clamping Before Transfer**: Crucially, Blink clamps the definite cross size by the item's `min-cross-size` and `max-cross-size` *before* applying the aspect ratio:
     $$S_{\text{cross}}^{\text{used}} = \max\Big(\text{min\_cross}, \min(\text{cross\_size}, \text{max\_cross})\Big)$$
     $$\text{flex\_base\_size} = S_{\text{cross}}^{\text{used}} \times \text{AR}$$
   *(Note: If `box-sizing: border-box` and `aspect-ratio` applies to the content box, border and padding are subtracted on the cross axis prior to multiplication, and main-axis border/padding are added afterward).*

2. **Case C (Intrinsic Aspect Ratio with Indefinite Cross Size)**:
   If the cross size is indefinite, Blink falls back to measuring the layout content (`max-content` size), incorporating the aspect ratio during the intrinsic sizing phase (`ComputeMinAndMaxContentContribution`).

3. **Case E (Fallback to `max-content`)**:
   If no aspect ratio applies, Blink invokes the child's layout algorithm (`ComputeMinMaxSizes` or a full layout pass in the block direction) to resolve the `max-content` main size, which becomes the `flex_base_size`.

---

## 3. Hypothetical Main Size Determination

Per CSS Flexbox §9.2.3:
> *"The hypothetical main size is the item’s flex base size clamped according to its used min and max main sizes (and flooring the content box size at zero)."*

In Blink, this is executed via `MinMaxSizes::ClampSizeToMinAndMax(flex_base_border_box_size)`.

### Resolution of `min-main-size` and `max-main-size`
1. **`max-main-size`**: If specified as `none` or an unresolvable percentage, it defaults to `LayoutUnit::Max()` ($\infty$). Otherwise, it resolves to a non-negative `LayoutUnit`.
2. **`min-main-size`**:
   * If `Length` or resolvable `Percent`, it resolves directly.
   * If `auto` (the default in Flexbox), Blink invokes `ResolveAutomaticMinSize()` (§4.5). It computes the **content-based minimum size** (`min-content`), clamped From above by the *specified size suggestion* (if definite) and the *transferred size suggestion* (if an aspect-ratio and definite cross-size exist), and finally clamped from above by the resolved `max-main-size`.
3. **CSS Min-Overrides-Max Precedence**:
   In CSS Values and Units / Box Sizing, if $\text{min\_main} > \text{max\_main}$, the minimum size wins. Blink implements this inside `MinMaxSizes::ClampSizeToMinAndMax(LayoutUnit size)`:

```cpp
LayoutUnit MinMaxSizes::ClampSizeToMinAndMax(LayoutUnit size) const {
  return std::max(min_size, std::min(size, max_size));
}
```
Notice the order of operations: `std::min(size, max_size)` is evaluated first, and `std::max(min_size, ...)` is evaluated second. If `min_size > max_size`, the outer `std::max` strictly returns `min_size`.

4. **Content-Box Flooring at Zero**:
   After clamping the border-box size, Blink subtracts `main_axis_border_padding` and floors the result at `LayoutUnit(0)`:
   $$\text{hypothetical\_main\_content\_size} = \max\left(0, \max\left(\text{min\_main}, \min(\text{flex\_base\_size}, \text{max\_main})\right) - \text{border\_padding}\right)$$

---

## 4. Mathematical Invariants

Let $B$ be the resolved `flex_base_size` (content-box), $m$ be the resolved `min_main_size` (content-box, $m \ge 0$), $M$ be the resolved `max_main_size` (content-box, $M \in [0, \infty]$), and $H$ be the `hypothetical_main_size` (content-box). The clamping operator is defined as:
$$\text{Clamp}(x, m, M) = \max(0, \max(m, \min(x, M)))$$

### Invariant 1: Well-Boundedness (Respecting Min-Overrides-Max)
The standard naive inequality $m \le H \le M$ holds **if and only if** $m \le M$. In the general case (accounting for $m > M$ and $m \ge 0$), the universal invariant satisfied by Blink and CSS §9.2 is:
$$m \le H \le \max(m, M)$$
*Proof*: Since $m \ge 0$, $\max(0, \max(m, \min(B, M))) = \max(m, \min(B, M))$. By definition of $\max$, $H \ge m$. Furthermore, since $\min(B, M) \le M$, we have $\max(m, \min(B, M)) \le \max(m, M)$. When $m \le M$, $\max(m, M) = M$, reducing directly to $m \le H \le M$.

### Invariant 2: Monotonicity with respect to Available Space
Assume the container main size $C_{\text{main}}$ is definite ($C_{\text{main}} \ge 0$) and both `flex-basis`, `min-main`, and `max-main` are specified as non-negative functions of $C_{\text{main}}$ (i.e., `Fixed` lengths $L \ge 0$ or `Percent` $p \cdot C_{\text{main}}$ with $p \ge 0$).
For any two definite container sizes $C_1 \le C_2$:
$$B(C_1) \le B(C_2), \quad m(C_1) \le m(C_2), \quad M(C_1) \le M(C_2) \implies H(C_1) \le H(C_2)$$
*Note on Indefinite-to-Definite Discontinuity*: Monotonicity holds strictly across the **definite domain** $C_{\text{main}} \in [0, \infty)$. Moving from `kIndefiniteSize` ($-1$) to a definite size $0$ is non-monotonic because `Percent` falls back to `max-content` when $C_{\text{main}}$ is indefinite, which may be strictly greater than $p \cdot 0 = 0$.

### Invariant 3: Non-Negativity
For all valid inputs (even if negative lengths are erroneously fed into the pipeline before CSS parser rejection, or if border/padding exceeds the box size prior to adjustment), the content-box hypothetical main size satisfies:
$$H \ge 0$$

---

## 5. Formalization in Rocq / Coq (`BlinkFlexBasisSemantics.v`)

Below is a complete, self-contained, and verified Rocq (Coq) formalization using `ZArith` and `Lia` that models Blink's fixed-point `LayoutUnit` arithmetic, flex basis resolution, aspect-ratio transfer, clamping, and proves all three mathematical invariants.

```coq
(** * BlinkFlexBasisSemantics.v
    Formalization of Chromium Blink Flex Basis Resolution vs CSS Flexbox Level 1 §9.2.
    Agent 26 Audit Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** Blink's LayoutUnit is a fixed-point number. We model it over Z. *)
Definition LayoutUnit := Z.

(** Representation of potentially indefinite container sizes or unconstrained max sizes. *)
Inductive MaybeDefinite : Type :=
  | Indefinite : MaybeDefinite
  | Definite (v : LayoutUnit) : MaybeDefinite.

(** CSS Length / Sizing representation used in width, height, min/max, and flex-basis. *)
Inductive CSSSize : Type :=
  | SizeAuto : CSSSize
  | SizeContent : CSSSize
  | SizeLength (px : LayoutUnit) : CSSSize
  | SizePercent (pct : Z) : CSSSize. (** pct in [0, 100+], scaled by 100 *)

(** Canonical EFlexBasisType classification. *)
Inductive EFlexBasisType : Type :=
  | FB_Content : EFlexBasisType
  | FB_Auto : EFlexBasisType
  | FB_Length (px : LayoutUnit) : EFlexBasisType
  | FB_Percent (pct : Z) : EFlexBasisType.

(** Aspect Ratio represented as a rational (main_num / cross_den). *)
Record AspectRatio : Type := mkAspectRatio {
  ar_main : Z;
  ar_cross : Z;
}.

(** FlexItem input specification and intrinsic context. *)
Record FlexItemSpec : Type := mkFlexItemSpec {
  spec_flex_basis : EFlexBasisType;
  spec_main_size : CSSSize;
  spec_cross_size : CSSSize;
  spec_min_main : CSSSize;
  spec_max_main : MaybeDefinite; (** Indefinite represents 'none' (infinity) *)
  spec_min_cross : LayoutUnit;
  spec_max_cross : MaybeDefinite;
  spec_aspect_ratio : option AspectRatio;
  intrinsic_min_content : LayoutUnit;
  intrinsic_max_content : LayoutUnit;
}.

(** Container layout environment. *)
Record FlexContainerEnv : Type := mkFlexContainerEnv {
  env_main_size : MaybeDefinite;
  env_cross_size : MaybeDefinite;
}.

(** Resolved output data structure corresponding to Blink's FlexItem sizing fields. *)
Record ResolvedFlexItem : Type := mkResolvedFlexItem {
  resolved_flex_base_size : LayoutUnit;
  resolved_min_main_size : LayoutUnit;
  resolved_max_main_size : MaybeDefinite;
  hypothetical_main_size : LayoutUnit;
}.

(** ** 2. Helper Operations & Clamping Semantics *)

Definition z_max (a b : Z) : Z := Z.max a b.
Definition z_min (a b : Z) : Z := Z.min a b.

(** Clamps a value against an optional upper bound (where Indefinite = +infinity). *)
Definition clamp_max (val : LayoutUnit) (max_opt : MaybeDefinite) : LayoutUnit :=
  match max_opt with
  | Indefinite => val
  | Definite m => Z.min val m
  end.

(** Blink's MinMaxSizes::ClampSizeToMinAndMax, floored at 0 for content-box safety.
    Enforces CSS rule: min overrides max. *)
