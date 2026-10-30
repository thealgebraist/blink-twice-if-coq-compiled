### 1. Core Data Structures in Blink Box Geometry

In Chromium’s Blink rendering engine (specifically within the LayoutNG architecture), layout geometry is abstracted into flow-relative (logical) coordinates to seamlessly handle varied writing modes and text directions. This enforces strict type safety and geometric separation between physical screen coordinates and layout calculations.

#### `BoxStrut` (Logical Strut)
Defined in `third_party/blink/renderer/core/layout/geometry/box_strut.h`, `BoxStrut` represents the thickness of a box's surrounding layers (margins, borders, or paddings) along the logical axes:
* `inline_start`: Thickness at the start of the inline progression axis.
* `inline_end`: Thickness at the end of the inline progression axis.
* `block_start`: Thickness at the start of the block progression axis.
* `block_end`: Thickness at the end of the block progression axis.

Helper methods on `BoxStrut` aggregate these directional thickness values:
* `InlineSum() = inline_start + inline_end`
* `BlockSum() = block_start + block_end`

#### `PhysicalBoxStrut` (Physical Strut)
Represents thicknesses tied directly to the physical viewport edges: `top`, `right`, `bottom`, and `left`. Before LayoutNG performs layout algorithms, physical properties resolved from CSS are transposed into a `BoxStrut`.

#### `LogicalSize`
Defined in `logical_size.h`, it pairs two scalar layout units representing the 2D extent of a box in flow-relative terms:
* `inline_size`: The dimension parallel to the text flow within a line.
* `block_size`: The dimension perpendicular to the inline flow (the direction in which blocks stack).

#### `PhysicalBoxSides` / `LogicalBoxSides`
Structures storing boolean flags indicating whether a specific edge of a box is present (e.g., when a box is fragmented across pages or columns, an edge might be omitted on the fragmented side).

---

### 2. Box Model Composition

In accordance with **CSS Box Model Module Level 3**, a layout box is composed of concentric rectangular areas. In Blink, these areas are computed by expanding or contracting a `LogicalSize` using `BoxStrut` instances.

Let $\oplus : \text{LogicalSize} \times \text{BoxStrut} \to \text{LogicalSize}$ be the **Box Expansion Operator**:
$$\text{Size}(I, B) \oplus \text{Strut}(i_s, i_e, b_s, b_e) = \text{Size}(I + i_s + i_e, B + b_s + b_e)$$

Let $+$ on `BoxStrut` be component-wise addition:
$$\text{Strut}(i_s, i_e, b_s, b_e) + \text{Strut}(i'_s, i'_e, b'_s, b'_e) = \text{Strut}(i_s + i'_s, i_e + i'_e, b_s + b'_s, b_e + b'_e)$$

The canonical layout sizing hierarchy is formalized as:
1. **Padding Box**: 
   $$\text{padding\_box} = \text{content\_box} \oplus \text{padding\_strut}$$
2. **Border Box**: 
   $$\text{border\_box} = \text{padding\_box} \oplus \text{border\_strut} = \text{content\_box} \oplus (\text{padding\_strut} + \text{border\_strut})$$
3. **Margin Box**: 
   $$\text{margin\_box} = \text{border\_box} \oplus \text{margin\_strut}$$

When `box-sizing: border-box` is active, Blink inversely computes the `content_box` by subtracting `(padding_strut + border_strut)` from the specified `border_box`, clamping the resulting dimensions to $0$ to satisfy the CSS invariant that content sizes cannot be negative.

---

### 3. Writing Mode Transposition

In accordance with **CSS Writing Modes Level 3**, the mapping between physical edges ($T, R, B, L$) and logical edges ($i_s, i_e, b_s, b_e$) is governed by two CSS properties:
* `writing-mode`: `horizontal-tb` (`HTB`), `vertical-rl` (`VRL`), `vertical-lr` (`VLR`), `sideways-rl` (`SRL`), `sideways-lr` (`SLR`).
* `direction`: `ltr` (`LTR`), `rtl` (`RTL`).

The transposition function $T_{\text{wm}, \text{dir}} : \text{PhysicalBoxStrut} \to \text{BoxStrut}$ maps `(top, right, bottom, left)` to `(inline_start, inline_end, block_start, block_end)` as follows:

| `writing-mode` | `direction` | `inline_start` | `inline_end` | `block_start` | `block_end` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `horizontal-tb` | `ltr` | `left` | `right` | `top` | `bottom` |
| `horizontal-tb` | `rtl` | `right` | `left` | `top` | `bottom` |
| `vertical-rl` / `sideways-rl` | `ltr` | `top` | `bottom` | `right` | `left` |
| `vertical-rl` / `sideways-rl` | `rtl` | `bottom` | `top` | `right` | `left` |
| `vertical-lr` | `ltr` | `top` | `bottom` | `left` | `right` |
| `vertical-lr` | `rtl` | `bottom` | `top` | `left` | `right` |
| `sideways-lr` | `ltr` | `bottom` | `top` | `left` | `right` |
| `sideways-lr` | `rtl` | `top` | `bottom` | `left` | `right` |

*Note: This mapping forms a bijection between the 4-tuple of physical edges and the 4-tuple of logical edges, ensuring the total perimeter sum (`top + right + bottom + left`) is strictly conserved.*

---

### 4. Mathematical Invariants

1. **Abelian Group Structure of `BoxStrut` under Addition**:
   * **Commutativity**: $\forall S_1, S_2 \in \text{BoxStrut}, S_1 + S_2 = S_2 + S_1$.
   * **Associativity**: $\forall S_1, S_2, S_3 \in \text{BoxStrut}, (S_1 + S_2) + S_3 = S_1 + (S_2 + S_3)$.
   * **Identity**: The zero strut $S_0 = (0, 0, 0, 0)$ satisfies $S + S_0 = S$.
2. **Module-like Action on `LogicalSize`**:
   * Expanding a `LogicalSize` $L$ sequentially by two struts is equivalent to expanding $L$ by the sum of the two struts: $(L \oplus S_1) \oplus S_2 = L \oplus (S_1 + S_2)$.
3. **Non-Negativity Conservation**:
   * Per CSS specifications, `padding` and `border-width` struts must be non-negative ($\ge 0$). If a `LogicalSize` $L$ is non-negative and a `BoxStrut` $S$ is non-negative, then $L \oplus S$ is guaranteed to be non-negative.
4. **Bijective Conservation of Transposition**:
   * Converting from `PhysicalBoxStrut` to `BoxStrut` and back to `PhysicalBoxStrut` under the same `(writing-mode, direction)` pair is an identity operation: $T^{-1}_{\text{wm}, \text{dir}}(T_{\text{wm}, \text{dir}}(P)) = P$.

---

### 5. Rocq / Coq Formalization (`BlinkBoxStrutGeometrySemantics.v`)

The following complete, self-contained Rocq (Coq) script formalizes the geometry primitives, writing mode transpositions, box model compositions, and proves all core algebraic and geometric invariants.

```coq
(** * BlinkBoxStrutGeometrySemantics.v
    Formal Audit of Chromium Blink BoxStrut Geometry against
    CSS Box Model Level 3 & CSS Writing Modes Level 3.
    Agent 73 Formal Verification Module. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** In Blink, LayoutUnit is a fixed-point number. We model it over Z. *)
Definition LayoutUnit := Z.

(** Logical BoxStrut: Flow-relative thicknesses *)
Record BoxStrut : Type := mkBoxStrut {
  inline_start : LayoutUnit;
  inline_end   : LayoutUnit;
  block_start  : LayoutUnit;
  block_end    : LayoutUnit
}.

(** PhysicalBoxStrut: Viewport-relative thicknesses *)
Record PhysicalBoxStrut : Type := mkPhysicalBoxStrut {
  top    : LayoutUnit;
  right  : LayoutUnit;
  bottom : LayoutUnit;
  left   : LayoutUnit
}.

(** LogicalSize: Flow-relative 2D extent *)
Record LogicalSize : Type := mkLogicalSize {
  inline_size : LayoutUnit;
  block_size  : LayoutUnit
}.

(** BoxSides: Presence flags for edges (used in fragmentation) *)
Record LogicalBoxSides : Type := mkLogicalBoxSides {
  has_inline_start : bool;
  has_inline_end   : bool;
  has_block_start  : bool;
  has_block_end    : bool
}.

(** Writing Modes and Directions (CSS Writing Modes Level 3) *)
Inductive WritingMode : Type :=
  | HorizontalTB
  | VerticalRL
  | VerticalLR
  | SidewaysRL
  | SidewaysLR.

Inductive TextDirection : Type :=
  | LTR
  | RTL.

(** ** 2. Operations and Box Model Composition *)

Definition zero_strut : BoxStrut := mkBoxStrut 0 0 0 0.

Definition inline_sum (s : BoxStrut) : LayoutUnit :=
  s.(inline_start) + s.(inline_end).

Definition block_sum (s : BoxStrut) : LayoutUnit :=
  s.(block_start) + s.(block_end).

Definition strut_add (s1 s2 : BoxStrut) : BoxStrut :=
  mkBoxStrut
    (s1.(inline_start) + s2.(inline_start))
    (s1.(inline_end)   + s2.(inline_end))
    (s1.(block_start)  + s2.(block_start))
    (s1.(block_end)    + s2.(block_end)).

Definition expand_size (sz : LogicalSize) (s : BoxStrut) : LogicalSize :=
  mkLogicalSize
    (sz.(inline_size) + inline_sum s)
    (sz.(block_size)  + block_sum s).

(** CSS Box Model Level 3 Hierarchy *)
Definition compute_padding_box (content_box : LogicalSize) (padding : BoxStrut) : LogicalSize :=
  expand_size content_box padding.

Definition compute_border_box (content_box : LogicalSize) (padding border : BoxStrut) : LogicalSize :=
  expand_size (compute_padding_box content_box padding) border.

Definition compute_margin_box (border_box : LogicalSize) (margin : BoxStrut) : LogicalSize :=
  expand_size border_box margin.

(** ** 3. Writing Mode Transposition *)

Definition physical_to_logical (p : PhysicalBoxStrut) (wm : WritingMode) (dir : TextDirection) : BoxStrut :=
  match wm, dir with
  | HorizontalTB, LTR => mkBoxStrut p.(left)   p.(right)  p.(top)    p.(bottom)
  | HorizontalTB, RTL => mkBoxStrut p.(right)  p.(left)   p.(top)    p.(bottom)
  | VerticalRL,   LTR => mkBoxStrut p.(top)    p.(bottom) p.(right)  p.(left)
  | VerticalRL,   RTL => mkBoxStrut p.(bottom) p.(top)    p.(right)  p.(left)
  | SidewaysRL,   LTR => mkBoxStrut p.(top)    p.(bottom) p.(right)  p.(left)
  | SidewaysRL,   RTL => mkBoxStrut p.(bottom) p.(top)    p.(right)  p.(left)
  | VerticalLR,   LTR => mkBoxStrut p.(top)    p.(bottom) p.(left)   p.(right)
  | VerticalLR,   RTL => mkBoxStrut p.(bottom) p.(top)    p.(left)   p.(right)
  | SidewaysLR,   LTR => mkBoxStrut p.(bottom) p.(top)    p.(left)   p.(right)
  | SidewaysLR,   RTL => mkBoxStrut p.(top)    p.(bottom) p.(left)   p.(right)
  end.

Definition logical_to_physical (l : BoxStrut) (wm : WritingMode) (dir : TextDirection) : PhysicalBoxStrut :=
  match wm, dir with
  | HorizontalTB, LTR => mkPhysicalBoxStrut l.(block_start)  l.(inline_end)   l.(block_end)    l.(inline_start)
  | HorizontalTB, RTL => mkPhysicalBoxStrut l.(block_start)  l.(inline_start) l.(block_end)    l.(inline_end)
  | VerticalRL,   LTR => mkPhysicalBoxStrut l.(inline_start) l.(block_start)  l.(inline_end)   l.(block_end)
  | VerticalRL,   RTL => mkPhysicalBoxStrut l.(inline_end)   l.(block_start)  l.(inline_start) l.(block_end)
  | SidewaysRL,   LTR => mkPhysicalBoxStrut l.(inline_start) l.(block_start)  l.(inline_end)   l.(block_end)
  | SidewaysRL,   RTL => mkPhysicalBoxStrut l.(inline_end)   l.(block_start)  l.(inline_start) l.(block_end)
  | VerticalLR,   LTR => mkPhysicalBoxStrut l.(inline_start) l.(block_end)    l.(inline_end)   l.(block_start)
  | VerticalLR,   RTL => mkPhysicalBoxStrut l.(inline_end)   l.(block_end)    l.(inline_start) l.(block_start)
  | SidewaysLR,   LTR => mkPhysicalBoxStrut l.(inline_end)   l.(block_end)    l.(inline_start) l.(block_start)
  | SidewaysLR,   RTL => mkPhysicalBoxStrut l.(inline_start) l.(block_end)    l.(inline_end)   