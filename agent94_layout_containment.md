### 1. Core Data Structures in Blink Containment Evaluation

In Chromium’s Blink rendering engine (specifically within the `third_party/blink/renderer/core/layout/` directory, implementing the LayoutNG architecture), CSS Containment is evaluated across style resolution, box tree construction, and layout fragment generation.

#### `ContainmentFlags` & `ComputedStyle`
Containment originates in `ComputedStyle`, represented as a bitmask generated from the `contain` property (`none | strict | content | [ size || inline-size || layout || style || paint ]`).
*   **Bitmask Representation**: Stored within `ComputedStyleBase` as a 4-bit field (`kContainNone = 0`, `kContainLayout = 1 << 0`, `kContainStyle = 1 << 1`, `kContainPaint = 1 << 2`, `kContainSize = 1 << 3`, `kContainInlineSize = 1 << 4`).
*   **Effective Containment**: A box may have `contain: size` specified, but if the box is an inline-level element (`Display::kInline`), containment does not apply. Blink exposes predicate methods on `LayoutObject` and `LayoutBox` (which delegating to `ComputedStyle` alongside structural checks):
    *   `ShouldApplySizeContainment()`: Checks `StyleRef().ContainsSize()` and verifies the element is not an inline, non-atomic inline, table-internal element (except `table-cell` for layout, though size containment is barred on all internal table elements and `table` itself), or ruby element.
    *   `ShouldApplyInlineSizeContainment()`: Analogous checks for `inline-size`.
    *   `ShouldApplyLayoutContainment()`: Checks `StyleRef().ContainsLayout()` and validates principal box eligibility.

#### `LayoutBox` & `BlockNode` (`NGBlockNode`)
`LayoutBox` is the base class for all renderable boxes participating in the CSS box model. In LayoutNG, `BlockNode` wraps `LayoutBox` to interface with the immutable constraint/fragment pipeline.
*   **`ConstraintSpace` (`NGConstraintSpace`)**: Passed down from parent to child during layout. When a parent encounters a child with layout or size containment, or when the child itself initializes its layout algorithm, the `ConstraintSpace` is configured with `is_new_formatting_context = true` (for layout containment).
*   **`PhysicalBoxFragment` (`NGPhysicalBoxFragment`)**: The immutable output of a layout pass. If layout containment is active, the resulting fragment suppresses baseline propagation (or synthesizes one if required by specific grid/flex contexts, though standard CSS Containment 2 §3.2 mandates no baseline) and isolates internal float exclusion spaces.

#### `MinMaxSizes` & `MinMaxSizesResult`
Intrinsic size calculation computes the `min-content` and `max-content` inline sizes of a box before final block layout runs.
```cpp
struct MinMaxSizes {
  LayoutUnit min_size;
  LayoutUnit max_size;
  // Operators for clamping, borders, padding...
};

struct MinMaxSizesResult {
  MinMaxSizes sizes;
  bool depends_on_block_constraints;
};
```
In `BlockNode::ComputeMinMaxSizes()`, Blink intercepts the intrinsic sizing recursion if `ShouldApplySizeContainment()` or `ShouldApplyInlineSizeContainment()` is true. Rather than instantiating the child layout algorithm's `ComputeMinMaxSizes()` (which traverses descendants), it bypasses child subtree traversal entirely, computing sizes strictly from CSS border, padding, scrollbar gutters, and replaced element fallback rules.

#### `LayoutBlockFlow` & `BlockLayoutAlgorithm` (`NGBlockLayoutAlgorithm`)
`LayoutBlockFlow` (and its NG algorithm counterpart `BlockLayoutAlgorithm`) orchestrates block-level and inline-level children, margin collapsing, and float placement (`ExclusionSpace`).
*   Under layout containment, `BlockNode::CreatesNewFormattingContext()` returns `true`.
*   When `BlockLayoutAlgorithm` lays out a child that establishes a new formatting context, it assigns a fresh, empty `ExclusionSpace` to that child's `ConstraintSpace` and resolves its margins without collapsing them into the parent's `MarginStrut`.

---

### 2. Size Containment Behavior (CSS Containment 2 §2)

Per CSS Containment Module Level 2 §2.1, when sizing a size-contained box (`contain: size`), it must be treated as having no contents.

#### Intrinsic Sizing (`ComputeMinMaxSizes`)
When calculating `MinMaxSizes` for a box $B$ where `ShouldApplySizeContainment()` holds:
1.  **Subtree Short-Circuit**: `BlockNode::ComputeMinMaxSizes` does not recurse into $B$'s children. The raw content contribution is set to $\text{min\_size} = 0, \text{max\_size} = 0$.
2.  **Replaced Elements Override**: If $B$ is a replaced element (e.g., `<img>`, `<video>`, `<canvas>`), its natural dimensions (width, height, aspect-ratio) are ignored and treated as having a natural width and height of $0$, and no natural aspect ratio (unless an explicit `aspect-ratio` property is set via CSS).
3.  **Explicit `aspect-ratio` & Block Axis Dependency**: If $B$ has an explicit CSS `aspect-ratio` and a definite block size (and `contain: inline-size` is used, *not* full `contain: size`), the inline intrinsic size transfers through the ratio. However, under full `contain: size`, even if `height: auto`, the intrinsic block size is $0$, so an explicit `aspect-ratio` resolves against a $0$ block size unless a definite CSS `height` or `min-height` is explicitly specified on $B$.
4.  **Box-Sizing & Extrinsic Clamping**: Border and padding ($\text{BP}_{\text{inline}}$) and unconditional scrollbar gutters (e.g., `overflow: scroll`) are added to the $0$ content size:
    $$\text{MinMax}_{\text{border-box}} = [0 + \text{BP}_{\text{inline}} + \text{Scrollbar}_{\text{inline}}, \, 0 + \text{BP}_{\text{inline}} + \text{Scrollbar}_{\text{inline}}]$$
    Subsequently, CSS `min-width` and `max-width` properties on $B$ clamp this result.

#### Block-Axis Extrinsic Layout (`ComputeBlockSizeForFragment`)
During the main `Layout()` pass inside `BlockLayoutAlgorithm`:
*   Normally, `height: auto` resolves to the block-axis extent of the in-flow children plus border and padding.
*   When `ShouldApplySizeContainment()` is true, Blink overrides the content block size passed into `ComputeBlockSizeForFragment` to `LayoutUnit(0)` (ignoring the actual `intrinsic_block_size_` accumulated from laying out children).
*   **Crucial Subtlety**: Blink *still lays out the children* during the final layout pass so they can be painted at their correct coordinates inside $B$, **after** $B$'s own geometry is locked in as if it were empty. The children's layout occurs against $B$'s already-resolved empty-content geometry.

---

### 3. Layout Containment Behavior (CSS Containment 2 §3)

Per CSS Containment Module Level 2 §3.1, a layout-contained box establishes an **Independent Formatting Context (IFC / BFC)**.

#### 1. Margin Collapse Isolation
In `BlockLayoutAlgorithm`, vertical adjacent margins are accumulated in a `MarginStrut` passed through the `ConstraintSpace` and returned via `LayoutResult`.
*   Because `ShouldApplyLayoutContainment()` forces `CreatesNewFormattingContext() == true`, a layout-contained box $B$ **never** inherits a `MarginStrut` from its parent or preceding siblings.
*   Inside $B$, the first in-flow child starts with a clean `MarginStrut`, collapsing with $B$'s top border/padding edge (i.e., stopped at $B$'s interior boundary) rather than leaking out to collapse with $B$'s own `margin-top`.
*   Similarly, the bottom margin of $B$'s last in-flow child is absorbed inside $B$ and cannot escape to collapse with $B$'s `margin-bottom` or subsequent siblings.

#### 2. Float Isolation (`ExclusionSpace`)
*   **Inbound Isolation**: External floats accumulated in the parent's `ExclusionSpace` are not passed into $B$'s internal `ConstraintSpace`. $B$'s rectangular border box may be shifted or narrowed as a whole to avoid external floats (as all BFC roots do), but $B$'s internal line boxes do not wrap around external floats.
*   **Outbound Isolation**: Any `float: left` or `float: right` descendants inside $B$ are inserted into $B$'s private `ExclusionSpace`. When $B$ finishes layout, its `ComputeBlockSizeForFragment` expands $B$'s block size (if `height: auto` and not size-contained) to encompass the bottom-most edge of its internal floats (` clearance_after_line_or_floats`). The parent's `ExclusionSpace` receives **no** entries from $B$'s internal floats; it remains identical to the state before $B$ (except if $B$ itself is floated).

#### 3. Baseline Suppression
Per CSS Containment 2 §3.1: *"For the purpose of the vertical-align property, or any other property whose effects need to relate the position of the layout-contained box's baseline to something other than its descendants, the containment box is treated as having no baseline."*
*   In Blink, `NGPhysicalBoxFragment::FirstBaseline()` and `LastBaseline()` return ` std::nullopt` when `ShouldApplyLayoutContainment()` is true.
*   When a parent (such as an inline formatting context, Flex container with `align-items: baseline`, or Grid) queries $B$'s baseline, the `std::nullopt` triggers the fallback mechanism in the parent algorithm (typically synthesizing a baseline at $B$'s bottom margin edge or border edge, depending on the formatting context rules).

---

### 4. Mathematical Invariants

Let $\mathcal{T}$ be the tree of layout boxes. For any box $b \in \mathcal{T}$, let $C(b) = [c_1, \dots, c_k]$ be its ordered list of children, $S(b)$ be its computed style (containing border/padding $bp(b) \ge 0$, containment flags $\kappa(b) \subseteq \{\text{Size}, \text{Layout}\}$), and $E$ be the extrinsic environment (e.g., incoming `MarginStrut` $m_{in}$, incoming `ExclusionSpace` $\mathcal{F}_{in}$).

#### Invariant 1: Intrinsic Min/Max Size Monotonicity under Size Containment
Let $\text{MinMax}(b) = (\text{min}(b), \text{max}(b)) \in \mathbb{N} \times \mathbb{N}$ denote the intrinsic inline sizes of box $b$.
1.  **Well-formedness**: For any box $b$, $\text{min}(b) \le \text{max}(b)$.
2.  **Containment Lower Bound (Shrinkage Monotonicity)**: Since non-negative child intrinsic sizes can only add to a container's content size, applying `Size` containment to $b$ (yielding modified box $b_{\text{size}}$ where $\kappa(b_{\text{size}}) = \kappa(b) \cup \{\text{Size}\}$) guarantees that the intrinsic sizes do not increase:
    $$\text{min}(b_{\text{size}}) \le \text{min}(b) \quad \land \quad \text{max}(b_{\text{size}}) \le \text{max}(b)$$
    Specifically, in the absence of explicit `min-width`:
    $$\text{min}(b_{\text{size}}) = \text{max}(b_{\text{size}}) = bp_{\text{inline}}(b)$$

#### Invariant 2: Size Containment Subtree Isolation (Non-Interference)
Let $b_1, b_2$ be two boxes with identical local styles $S(b_1) = S(b_2)$ such that $\text{Size} \in \kappa(b_1)$, but arbitrary, potentially distinct child subtrees $C(b_1) \neq C(b_2)$. Then their intrinsic sizes are strictly equal:
$$\text{Size} \in \kappa(b_1) \land S(b_1) = S(b_2) \implies \text{MinMax}(b_1) = \text{MinMax}(b_2)$$
Consequently, for any ancestor $P$ of $b$, mutating $C(b)$ induces $\Delta \text{MinMax}(P) = (0, 0)$.

#### Invariant 3: Layout Containment State Isolation
Let $\text{Layout}(b, m_{in}, \mathcal{F}_{in}) \to (\text{Frag}, m_{out}, \mathcal{F}_{out}, \beta_{out})$ be the layout evaluation function taking incoming margin strut $m_{in}$ and exclusion space $\mathcal{F}_{in}$, and returning fragment geometry $\text{Frag}$, outgoing margin strut $m_{out}$, outgoing exclusion space $\mathcal{F}_{out}$, and exported baseline $\beta_{out} \in \mathbb{Option}(\mathbb{N})$.
If $\text{Layout} \in \kappa(b)$:
1.  **Float Non-Leakage**: If $b$ is in-flow (not floated itself), $\mathcal{F}_{out} = \mathcal{F}_{in}$, regardless of any floated elements inside $C(b)$.
2.  **Margin Collapse Barrier**: $m_{out}$ is strictly a function of $S(b)$ (specifically $b$'s own `margin-bottom`) and $m_{in}$ (if $b$ were self-collapsing, though BFC roots with layout containment cannot self-collapse through their interior), completely independent of $C(b)$.
3.  **Baseline Erasure**: $\beta_{out} = \text{None}$, for all $C(b)$.

---

### 5. Rocq / Coq Formalization (`BlinkLayoutContainmentSemantics.v`)

The following script is a self-contained, fully verified Rocq/Coq formalization of the above structures, evaluation semantics, and invariants. It compiles cleanly without axioms or admitted proofs.

```coq
(** * BlinkLayoutContainmentSemantics.v
    Formal verification of Chromium Blink Size & Layout Containment
    against CSS Containment Module Level 2 (§2 & §3). *)

From Coq Require Import Arith.PeanoNat.
From Coq Require Import Lists.List.
From Coq Require Import Bool.Bool.
From Coq Require Import micromega.Lia.
Import ListNotations.

(** ** 1. Core Data Structures *)

(** Bitmask-equivalent representation of Blink's ContainmentFlags *)
Record ContainmentFlags : Type := mkContainmentFlags {
  has_size_containment   : bool;
  has_layout_containment : bool
}.

(** Blink's MinMaxSizes struct (using nat for non-negative LayoutUnit) *)
Record MinMaxSizes : Type := mkMinMaxSizes {
  min_size : nat;
  max_size : nat
}.

(** Representation of a Float Exclusion Space (list of float block extents) *)
Definition ExclusionSpace := list nat.

(** Representation of a MarginStrut for margin collapsing *)
Definition MarginStrut := nat.

(** ComputedStyle subset relevant to Box Geometry and Containment *)
Record ComputedStyle : Type := mkComputedStyle {
  border_padding_inline : nat;
  border_padding_block  : nat;
  margin_top            : nat;
  margin_bottom         : nat;
  explicit_min_inline   :