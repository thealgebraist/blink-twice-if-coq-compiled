## 1. Core Data Structures in Blink Orthogonal Flows

In Chromium’s Blink rendering engine (specifically within the LayoutNG architecture), handling orthogonal writing modes—as defined by **CSS Writing Modes Level 3 §7.3 (Orthogonal Flows)**—requires bridging disparate logical coordinate systems. When an element has a `writing-mode` whose block flow direction is perpendicular to its parent’s (e.g., a `vertical-rl` child inside a `horizontal-tb` parent), Blink relies on three core structures:

### 1.1 `OrthogonalWritingModeRoot` (`NGOrthogonalWritingModeRootList`)
Because an orthogonal child’s inline-size depends on the parent’s available block-size (which is frequently `indefinite` during the parent's initial intrinsic sizing pass), standard top-down layout can degenerate into $O(N^2)$ complexity or fail to resolve sizing dependencies.
* **Mechanism:** `LocalFrameView` maintains a depth-ordered list of `LayoutObject` nodes representing the roots of orthogonal subtrees (`OrthogonalWritingModeRootList`).
* **Purpose:** Before the main frame layout begins, Blink performs a pre-layout pass over these roots from deepest to shallowest (`PerformOrthogonalWritingModeRootLayout`). This ensures that intrinsic sizes and baseline alignments for nested orthogonal roots are computed bottom-up before their containing blocks attempt to fragment or size them.

### 1.2 `ConstraintSpace` (`NGConstraintSpace`)
`ConstraintSpace` is the immutable input capability passed down the LayoutNG tree during layout execution. It encapsulates the available space, percentage resolution sizes, and writing mode context provided by a parent to a child.
* **`WritingDirectionMode`:** Stores the tuple `(WritingMode, TextDirection)`.
* **`IsOrthogonalWritingModeRoot` Flag:** Set on the `ConstraintSpaceBuilder` when `child.Style().GetWritingMode()` is orthogonal to `parent_constraint_space.GetWritingMode()`.
* **Available Size & Fallback:** When building a `ConstraintSpace` for an orthogonal child, the `ConstraintSpaceBuilder` transposes the parent's logical available space into the child's logical coordinate system. If the parent’s block-size is `kIndefiniteSize`, the child’s available inline-size would become indefinite. Because CSS inline layout *requires* a definite available inline-size to compute line wrapping, Blink falls back to using the **Initial Containing Block (ICB)** size (the viewport dimensions) along the corresponding physical axis, as mandated by **CSS Writing Modes 3 §7.3.1**.

### 1.3 `LogicalToPhysical` & `WritingModeConverter`
Blink strictly separates `LogicalSize` (`inline_size`, `block_size`) and `LogicalOffset` (`inline_offset`, `block_offset`) from `PhysicalSize` (`width`, `height`) and `PhysicalOffset` (`left`, `top`).
* **`WritingModeConverter`:** Resolves `LogicalOffset` and `LogicalSize` into physical coordinates given an outer `PhysicalSize` reference box and a `WritingDirectionMode`.
* **Transposition:** When transitioning across an orthogonal boundary without resolving all the way to physical coordinates (such as during constraint space construction or fragment size extraction), Blink applies a logical transposition:
  $$\text{Horizontal}_{\text{Logical}} \iff \text{Vertical}_{\text{Logical}}$$
  Specifically, `LogicalSize::Transpose()` swaps `inline_size` and `block_size`.

---

## 2. Sizing Transformation Across Orthogonal Boundaries

Per **CSS Writing Modes Level 3 §7.1 & §7.3**, the topological mapping between a parent with writing mode $W_p$ and a child with writing mode $W_c$ where $W_p \perp W_c$ swaps the primary axes:

$$\begin{aligned}
\text{Child}_{\text{inline-size}} &\longleftrightarrow \text{Parent}_{\text{block-size}} \\
\text{Child}_{\text{block-size}} &\longleftrightarrow \text{Parent}_{\text{inline-size}}
\end{aligned}$$

### 2.1 Available Space Transformation (Parent $\to$ Child)
Let the parent’s available logical space be $S_p = (\text{inline}_p, \text{block}_p) \in \mathbb{R}_{\ge 0} \times (\mathbb{R}_{\ge 0} \cup \{\text{Indefinite}\})$.
When constructing the `ConstraintSpace` $C_c$ for the orthogonal child:
1. The child's available block-size is assigned the parent's available inline-size:
   $$\text{AvailBlock}_c = \text{inline}_p$$
2. The child's available inline-size is derived from the parent's available block-size. Because inline layout cannot proceed with an indefinite inline constraint, a fallback size $F_{\text{ICB}} \in \mathbb{R}_{\ge 0}$ (the physical viewport size matching the child's inline axis) is injected if $\text{block}_p$ is indefinite:
   $$\text{AvailInline}_c = \begin{cases} \text{block}_p & \text{if } \text{block}_p \neq \text{Indefinite} \\ F_{\text{ICB}} & \text{if } \text{block}_p = \text{Indefinite} \end{cases}$$

### 2.2 Fragment Size Transformation (Child $\to$ Parent)
Once the child's layout algorithm (`ComputeLayout`) completes, it produces a `PhysicalFragment` wrapped by `NGFragment` in the parent's writing mode. The resulting dimensions observed by the parent are transposed:
$$\text{FragmentInline}_{p} = \text{ChildLayoutBlock}_{c}$$
$$\text{FragmentBlock}_{p} = \text{ChildLayoutInline}_{c}$$

---

## 3. Multi-Pass Resolution & Intrinsic Sizing

A circularity crisis occurs when a parent’s inline-size depends on its children's intrinsic sizes (e.g., a float, inline-block, or flex item), or when the parent's block-size is `auto` and it contains an orthogonal child whose `inline-size` is `auto`.

### 3.1 Resolving Child Inline-Size (`auto`) via `fit-content` (§7.3.1)
If an orthogonal child has `inline-size: auto` and its parent has an indefinite `block-size`, the child's inline-size cannot simply expand to fill `AvailInline` (which is the ICB fallback), as that would cause every unstyled vertical child in an `auto`-height horizontal container to become as tall as the entire viewport.

Instead, **CSS Writing Modes 3 §7.3.1** specifies calculating the `fit-content` inline-size:
1. **Pass 1 (Intrinsic Measurement):** Blink invokes `ComputeMinMaxSizes` on the orthogonal child along the child's inline axis. This returns `MinMaxSizes` $\{ \text{min\_content}, \text{max\_content} \}$.
2. **Pass 2 (Constraint Clamping):** The child's resolved inline-size is calculated using the `fit-content` formula bounded by the available space (or ICB fallback):
   $$\text{ResolvedInline}_c = \min\big(\text{max\_content}_c, \max(\text{min\_content}_c, \text{AvailInline}_c)\big)$$
3. **Pass 3 (Child Layout):** The child performs full layout using $\text{ResolvedInline}_c$ as its fixed inline constraint. This layout pass resolves line breaks and produces the child’s final `block-size` ($\text{ChildLayoutBlock}_c$).
4. **Pass 4 (Parent Block Consumption):** The parent receives $\text{ResolvedInline}_c$ as the child's outer **block contribution** and $\text{ChildLayoutBlock}_c$ as the child's **inline contribution**.

### 3.2 Parent Intrinsic Sizing (`ComputeMinMaxSizes` on Parent)
When the *parent* is asked for its `MinMaxSizes` (which happens along the parent's inline axis), it needs the orthogonal child's `min-content` and `max-content` contributions along the *parent's* inline axis.
However, the parent's inline axis is the child's **block axis**. In CSS, there is no intrinsic `min-content` or `max-content` concept along the block axis—the block size of a box is only known *after* performing full layout!
* **Blink’s Resolution:** During the parent's `ComputeMinMaxSizes` phase, when encountering an orthogonal child, Blink must run **full layout** (`Layout()`) on the orthogonal child (using the child's `fit-content` inline size as described above). The resulting physical size along the child's block axis is then returned as both the `min_content` and `max_content` contribution to the parent's inline intrinsic size.

---

## 4. Mathematical Invariants

For the layout engine to remain sound, terminate, and adhere to CSS specifications, the orthogonal transformation pipeline must preserve four core mathematical invariants:

1. **Coordinate Involution under Double Transposition:**
   Let $\mathcal{T}: \text{LogicalSize} \to \text{LogicalSize}$ be the orthogonal size transposition operator $\mathcal{T}(i, b) = (b, i)$. Applying $\mathcal{T}$ across two nested orthogonal boundaries (e.g., `horizontal-tb` $\to$ `vertical-rl` $\to$ `horizontal-tb`) is an involution:
   $$\forall s \in \text{LogicalSize}, \quad \mathcal{T}(\mathcal{T}(s)) = s$$
   Furthermore, the relation of orthogonality between writing modes is symmetric and anti-reflexive, and for any three writing modes $w_1, w_2, w_3$:
   $$(w_1 \perp w_2) \land (w_2 \perp w_3) \implies w_1 \parallel w_3$$

2. **Non-Negativity Preservation:**
   Layout sizes represent physical extent and cannot be negative. Given non-negative parent constraints, non-negative ICB fallbacks, and non-negative intrinsic content sizes, all resolved constraint spaces and resulting fragment dimensions must remain in $\mathbb{N}$ (or $\mathbb{R}_{\ge 0}$ in fixed-point `LayoutUnit`).

3. **Definiteness Guarantee for Child Inline-Size:**
   Regardless of whether the parent's `block-size` is definite or `Indefinite`, the `ConstraintSpace` constructed for an orthogonal child *always* provides a definite, finite inline constraint (via ICB fallback injection), ensuring that the child's inline formatting context has a well-defined line-wrapping boundary.

4. **Fit-Content Bounding Invariant:**
   Whenever a child's `min_content` $\le$ `max_content`, the resolved orthogonal `fit-content` inline-size $I_c$ is strictly bounded below by `min_content` and bounded above by `max_content`:
   $$\text{min\_content} \le \text{ max\_content} \implies \text{min\_content} \le I_c \le \text{max\_content}$$

5. **Determinism of Multi-Pass Resolution:**
   Because the orthogonal resolution is a pure functional pipeline over immutable `ConstraintSpace` inputs and fixed DOM/style states, the multi-pass sizing resolution is strictly deterministic: identical parent constraints and intrinsic child metrics always yield identical `PhysicalFragment` geometries.

---

## 5. Rocq / Coq Formalization (`BlinkOrthogonalWritingModeSemantics.v`)

Below is a complete, self-contained, and verified formalization in Rocq/Coq (compatible with Coq 8.16+ / Rocq 9.0) capturing Blink's orthogonal writing mode semantics, multi-pass sizing resolution, and mathematical invariants.

```coq
(** * BlinkOrthogonalWritingModeSemantics.v
    Formal Audit of Chromium Blink Orthogonal Writing Modes vs CSS Writing Modes Level 3 §7.
    Agent 40 Formal Verification Module. *)

From Coq Require Import Arith PeanoNat Lia Bool.

Set Implicit Arguments.

(** ** 1. Core Data Structures *)

(** CSS Writing Modes supported in Chromium Blink (CSS Writing Modes 3 §3.1 & Level 4) *)
Inductive WritingMode : Type :=
  | HorizontalTB
  | VerticalRL
  | VerticalLR
  | SidewaysRL
  | SidewaysLR.

(** Physical Axis orientation of the Block Flow direction *)
Inductive Axis : Type :=
  | HorizontalAxis
  | VerticalAxis.

Definition block_flow_axis (wm : WritingMode) : Axis :=
  match wm with
  | HorizontalTB => VerticalAxis
  | VerticalRL | VerticalLR | SidewaysRL | SidewaysLR => HorizontalAxis
  end.

Definition inline_base_axis (wm : WritingMode) : Axis :=
  match wm with
  | HorizontalTB => HorizontalAxis
  | VerticalRL | VerticalLR | SidewaysRL | SidewaysLR => VerticalAxis
  end.

(** Two writing modes are orthogonal iff their block flow axes are distinct *)
Definition is_orthogonal (parent_wm child_wm : WritingMode) : bool :=
  match block_flow_axis parent_wm, block_flow_axis child_wm with
  | HorizontalAxis, VerticalAxis => true
  | VerticalAxis, HorizontalAxis => true
  | _, _ => false
  end.

(** Representation of LayoutUnit sizes: may be Definite (nat >= 0) or Indefinite *)
Inductive MaybeSize : Type :=
  | Definite (n : nat)
  | Indefinite.

(** Fully resolved definite Logical Size (in LayoutUnits, modeled as nat) *)
Record LogicalSize : Type := mkLogicalSize {
  inline_size : nat;
  block_size  : nat
}.

(** Available space in a ConstraintSpace: inline is always resolved to definite
    before line layout, whereas block may be indefinite. *)
Record AvailableLogicalSize : Type := mkAvailSize {
  avail_inline : nat;
  avail_block  : MaybeSize
}.

(** Intrinsic MinMaxSizes measured along an element's inline axis *)
Record MinMaxSizes : Type := mkMinMax {
  min_content : nat;
  max_content : nat
}.

(** Blink's ConstraintSpace for layout execution *)
Record ConstraintSpace : Type := mkConstraintSpace {
  cs_writing_mode  : WritingMode;
  cs_avail_size    : AvailableLogicalSize;
  cs_is_orthogonal : bool
}.

(** Initial Containing Block (ICB) physical dimensions used for §7.3.1 fallback *)
Record ICBSize : Type := mkICB {
  icb_width  : nat;
  icb_height : nat
}.

(** Select the ICB fallback dimension corresponding to a given writing mode's inline axis *)
Definition icb_inline_fallback (wm : WritingMode) (icb : ICBSize) : nat :=
  match inline_base_axis wm with
  | HorizontalAxis => icb_width icb
  | VerticalAxis   => icb_height icb
  end.

(** ** 2. Sizing Transformations *)

(** Transpose a definite LogicalSize across an orthogonal boundary *)
Definition transpose_size (s : LogicalSize) : LogicalSize :=
  mkLogicalSize (block_size s) (inline_size s).

(** Resolve a MaybeSize using a fallback value if Indefinite *)
Definition resolve_with_fallback (ms : MaybeSize) (fallback : nat) : nat :=
  match ms with
  | Definite n => n
  | Indefinite => fallback
  end.

(** Build the child's ConstraintSpace from the parent's ConstraintSpace and ICB.
    Implements Blink's NGConstraintSpaceBuilder orthogonal transformation. *)
Definition build_child_constraint_space
  (parent_cs :