### 1. Core Data Structures in Blink Fragment Builder

In Chromium's LayoutNG (Blink's modern layout engine), the layout phase transforms a mutable input `LayoutInputNode` tree into an immutable output `PhysicalFragment` tree. This separation enforces functional purity during layout calculation and guarantees that geometry and painting pass traversals operate over read-only data structures.

#### `BoxFragmentBuilder` (`third_party/blink/renderer/core/layout/box_fragment_builder.h`)
The mutable accumulator instantiated by a layout algorithm (e.g., `BlockLayoutAlgorithm`, `TableLayoutAlgorithm`) to construct a single `PhysicalBoxFragment`. 
*   **Coordinate System:** Operates exclusively in **logical coordinates** (`LogicalOffset`, `LogicalSize`) dictated by the current element's `WritingMode` and `TextDirection` (`WritingDirectionMode`).
*   **Child Accumulation:** Stores an internal `HeapVector<LogicalFragmentLink>` (where `LogicalFragmentLink` pairs a `Member<const PhysicalFragment>` with a `LogicalOffset`).
*   **Sizing State:** Tracks ` intrinsic_block_size_`, `Size()` (logical inline and block sizes), `MinimalSpaceShortage`, and `InflowBounds`.
*   **Finalization:** Exposes `ToBoxFragment()`, which invokes `PhysicalBoxFragment::Create()`, triggering the coordinate conversion from `LogicalOffset` to `PhysicalOffset` using the resolved physical outer size of the fragment being built.

#### `PhysicalBoxFragment` (`third_party/blink/renderer/core/layout/physical_box_fragment.h`)
The immutable, ref-counted/oilpan-managed output node representing a CSS box (as defined in CSS Display 3 and CSS Box Model 3) or a fragment thereof (if broken across columns/pages per CSS Fragmentation 3).
*   **Memory Layout:** Utilizes a flexible array member (`base::TrailingObjects` pattern) to allocate its `PhysicalFragmentLink` array contiguously in memory immediately following the `PhysicalBoxFragment` header. This eliminates pointer-chasing overhead during Paint, Hit-Testing, and DevTools inspection.
*   **Geometry:** Stores its own `PhysicalSize` (`size_`) representing the **border-box** dimensions (CSS Box Model 3 § 3.4). It optionally stores rare data such as `PhysicalRect scrollable_overflow_`, `PhysicalRect ink_overflow_`, borders (`PhysicalBoxStrut`), and padding (`PhysicalBoxStrut`).
*   **Immutability:** Once constructed, its `children_` span (`base::span<const PhysicalFragmentLink>`) and `size_` cannot be mutated (except via specific, tightly-controlled Clone/Rebuild passes during simplified layout).

#### `PhysicalFragmentLink` (`third_party/blink/renderer/core/layout/physical_fragment_link.h`)
The structural edge in the fragment tree. Because a single `PhysicalFragment` can be shared (e.g., across cached layout passes) and because a fragment represents its own intrinsic box without knowledge of where it sits in its parent's coordinate space, the parent-relative offset is stored on the *edge*, not the *node*.
```cpp
struct PhysicalFragmentLink {
  Member<const PhysicalFragment> fragment;
  PhysicalOffset offset; // Relative to the parent's physical border-box top-left origin.
};
```

---

### 2. Hierarchy Assembly

Consider the assembly of the hierarchy:
`PageRootFragment` $\to$ `BodyFragment` $\to$ `[HeaderFragments, TableFragment` $\to$ `[RowFragments` $\to$ `[CellFragments` $\to$ `[TextFragments]]]]`

LayoutNG executes a top-down constraint-passing, bottom-up fragment-returning recursion. A parent algorithm cannot finalize its `BoxFragmentBuilder` until its children have returned their immutable `PhysicalFragment` instances.

```
[Layout Result Returns (Bottom-Up)]         [Builder Accumulation (Logical)]          [Finalization (Physical)]
-----------------------------------         --------------------------------          -------------------------
1. InlineLayoutAlgorithm
   └─> Returns PhysicalLineBoxFragment
       containing TextFragments             Cell BoxFragmentBuilder
                                            └─> AddChild(LineBox, LogicalOffset) ───> PhysicalBoxFragment (Cell)
                                                                                              │
2. TableCellLayoutAlgorithm <─────────────────────────────────────────────────────────────────┘
   └─> Returns Cell Fragment                Row BoxFragmentBuilder
                                            └─> AddChild(Cell, LogicalOffset) ──────> PhysicalBoxFragment (Row)
                                                                                              │
3. TableRowLayoutAlgorithm <──────────────────────────────────────────────────────────────────┘
   └─> Returns Row Fragment                 TableSection / Table Builder
                                            └─> AddChild(Row, LogicalOffset) ───────> PhysicalBoxFragment (Table)
                                                                                              │
4. BlockLayoutAlgorithm (Header & Table) <────────────────────────────────────────────────────┘
   └─> Returns Header & Table Fragments     Body BoxFragmentBuilder
                                            ├─> AddChild(Header, LogicalOffset)
                                            └─> AddChild(Table, LogicalOffset) ─────> PhysicalBoxFragment (Body)
                                                                                              │
5. PageLayoutAlgorithm <──────────────────────────────────────────────────────────────────────┘
   └─> Returns Body Fragment                PageRoot BoxFragmentBuilder
                                            └─> AddChild(Body, LogicalOffset) ──────> PhysicalBoxFragment (PageRoot)
```

#### Step-by-Step Execution Mechanics:
1.  **Leaf Generation (`TextFragment` / `FragmentItem`):** Inside `CellFragment`, an inline formatting context is established. `InlineLayoutAlgorithm` processes text runs, shaping them via HarfBuzz, and emits `FragmentItem` instances (modern Blink's flattened representation of `PhysicalTextFragment`) into a `FragmentItemsBuilder` attached to the Cell's `BoxFragmentBuilder`. Each text item is given a physical offset relative to the containing line box or block container.
2.  **`CellFragment` Assembly:** The `BlockLayoutAlgorithm` (acting on the `LayoutNGTableCell` node) computes the cell's intrinsic block size from the accumulated line boxes, applies CSS padding and table-collapsed borders, and calls `builder.ToBoxFragment()`. This freezes the cell's `PhysicalSize` and converts child line/text offsets to `PhysicalOffset`s relative to the cell's border-box.
3.  **`RowFragment` Assembly:** `TableRowLayoutAlgorithm` iterates over cells in the row. It passes a `ConstraintSpace` with fixed inline-size (derived from table column sizing) and baseline alignment constraints to each cell. Upon receiving each `CellFragment`, it calls `row_builder.AddChild(cell_fragment, LogicalOffset(cell_inline_offset, 0))`. When all cells are processed, the row's block-size is the maximum of the cells' block-sizes (plus baseline adjustments). `row_builder.ToBoxFragment()` freezes the `RowFragment`.
4.  **`TableFragment` Assembly:** `TableLayoutAlgorithm` accumulates `HeaderFragments` (if `<thead>` is present, or if preceding block headers exist outside the table) and `RowFragments` (often grouped via an intermediate `TableSection` fragment for `<tbody>`). Each row is added at `LogicalOffset(table_border_padding.inline_start, current_block_offset)`.
5.  **`BodyFragment` & `PageRootFragment` Assembly:** The `Body` block layout algorithm stacks the preceding document `HeaderFragments` and the `TableFragment` along the block axis, resolving collapsing margins (CSS Box Model 3 § 5.3) between the headers and the table. Finally, the `PageRootFragment` (representing the `@page` box or initial containing block / `LayoutView`) wraps the `BodyFragment`, offset by the body's margins and the page's border/padding.

---

### 3. Preserving Relative Coordinates and Bounding Rects

A critical invariant of the CSS Box Model 3 and Blink's Fragment Tree is **local coordinate encapsulation**. No fragment knows its global position on the viewport/page.

#### Coordinate Space Transitions (`WritingModeConverter`)
During `BoxFragmentBuilder::AddChild`, the child is placed at a `LogicalOffset` $(i, b)$ relative to the parent's **border-box** origin. The parent's final block size $B_p$ is often unknown until *all* children are added. 
When `ToBoxFragment()` is called, the parent's final `LogicalSize` $(I_p, B_p)$ is locked, converted to a `PhysicalSize` $(W_p, H_p)$, and a `WritingModeConverter` transforms every child's `LogicalOffset` $(i_c, b_c)$ and `PhysicalSize` $(W_c, H_c)$ into a `PhysicalOffset` $(x_c, y_c)$:

*   `horizontal-tb` (LTR): $(x_c, y_c) = (i_c, b_c)$
*   `horizontal-tb` (RTL): $(x_c, y_c) = (W_p - i_c - W_c, b_c)$
*   `vertical-rl` (LTR): $(x_c, y_c) = (W_p - b_c - W_c, i_c)$
*   `vertical-lr` (LTR): $(x_c, y_c) = (b_c, i_c)$

#### Bounding Rect Composition across the Hierarchy
For any fragment $F$, its local bounding box is $R_{\text{local}}(F) = (0, 0, W_F, H_F)$, corresponding to its CSS **border-box** (or line-box/glyph-bounds for text).
When placed inside a parent $P$ via a `PhysicalFragmentLink` with offset $O_{P \to F} = (x, y)$, the bounding rect of $F$ in $P$'s coordinate space is:
$$R_P(F) = (x, y, W_F, H_F)$$

To resolve the absolute (PageRoot-relative) bounding rect of a deeply nested `TextFragment` $T$, Blink's paint and hit-testing traversals accumulate offsets down the ancestor spine:
$$\text{Offset}_{\text{PageRoot} \to T} = O_{\text{PageRoot} \to \text{Body}} + O_{\text{Body} \to \text{Table}} + O_{\text{Table} \to \text{Row}} + O_{\text{Row} \to \text{Cell}} + O_{\text{Cell} \to T}$$
$$R_{\text{PageRoot}}(T) = \left( \text{Offset}_{\text{PageRoot} \to T}.x, \; \text{Offset}_{\text{PageRoot} \to T}.y, \; W_T, \; H_T \right)$$

---

### 4. Mathematical Invariants

To audit Blink's fragment assembly against CSS Box Model 3 and CSS Display 3, we formalize two core structural and geometric invariants.

#### Invariant 1: Structural Acyclicity (Strict DAG / Tree)
Let $\mathcal{F}$ be the set of all allocated `PhysicalFragment` instances, and let $E \subseteq \mathcal{F} \times \mathbb{Z}^2 \times \mathcal{F}$ be the set of directed edges defined by `PhysicalFragmentLink`.
1.  **Strict Acyclicity (DAG):** Because `PhysicalFragment` is strictly immutable upon creation and `BoxFragmentBuilder::ToBoxFragment()` only accepts already-allocated `const PhysicalFragment*` pointers as children, edges in $E$ strictly follow a topological chronological ordering of allocation time $t(\cdot)$:
    $$\forall (p, \vec{o}, c) \in E, \quad t(c) < t(p)$$
    Since $<$ on allocation timestamps is a strict total order, the graph $(\mathcal{F}, E)$ cannot contain any directed cycles.
2.  **Unfolded Tree Isomorphism:** While Blink may cache and reuse an identical `PhysicalFragment` pointer across layout passes (making the raw pointer graph a DAG), the *semantic layout tree* defined by pairing each fragment with its traversal path from `PageRootFragment` is a strict tree.

#### Invariant 2: Geometric Bounding Box Containment (In-Flow Layout)
Under CSS Box Model 3 and CSS Display 3, in the absence of overflowing mechanisms (specifically: `position: absolute/fixed/relative`, negative margins, CSS transforms, or explicit `width/height` constraints smaller than intrinsic content size), every child fragment's border-box is geometrically contained within its parent fragment's content-box, and therefore strictly within its parent's border-box.

For a parent fragment $P$ with size $(W_P, H_P)$, border strut $B_P = (b_{\text{top}}, b_{\text{right}}, b_{\text{bottom}}, b_{\text{left}})$, and padding strut $D_P = (p_{\text{top}}, p_{\text{right}}, p_{\text{bottom}}, p_{\text{left}})$, let its content-box in local coordinates be:
$$C(P) = [x_{\min}, x_{\max}] \times [y_{\min}, y_{\max}]$$
where:
$$x_{\min} = b_{\text{left}} + p_{\text{left}}, \quad x_{\max} = W_P - b_{\text{right}} - p_{\text{right}}$$
$$y_{\min} = b_{\text{top}} + p_{\text{top}}, \quad y_{\max} = H_P - b_{\text{bottom}} - p_{\text{bottom}}$$

For every child link $(O_i, F_i) \in \text{children}(P)$ with $O_i = (x_i, y_i)$ and $F_i$ having size $(W_i, H_i)$:
1.  **Non-negativity of Dimensions:** $W_i \ge 0 \land H_i \ge 0$ and $W_P \ge 0 \land H_P \ge 0$.
2.  **Local Border-Box Containment:**
    $$0 \le x_i \quad \land \quad x_i + W_i \le W_P$$
    $$0 \le y_i \quad \land \quad y_i + H_i \le H_P$$
3.  **Transitive Containment:** If Local Border-Box Containment holds at every parent-child link in the hierarchy, then for any descendant fragment $D$ reachable from `PageRootFragment` via path $\pi$, the global bounding box of $D$ in `PageRootFragment`'s coordinate space is strictly contained within `PageRootFragment`'s bounding box $[0, W_{\text{root}}] \times [0, H_{\text{root}}]$.

---

### 5. Concrete Rocq/Coq Formalization (`BlinkPageFragmentAssemblySemantics.v`)

The following complete, self-contained Rocq/Coq script formalizes Blink's `PhysicalFragment`, `PhysicalFragmentLink`, `BoxFragmentBuilder`, the `horizontal-tb` / `vertical-rl` coordinate conversion, the exact page/body/header/table/row/cell/text assembly hierarchy, structural tree invariants, and a mechanically verified proof of **Transitive Bounding Box Containment**.

```coq
(** * BlinkPageFragmentAssemblySemantics.v
    Formalization of Chromium Blink LayoutNG Fragment Tree Assembly
    audited against CSS Box Model Level 3 and CSS Display Level 3.
    Agent 111 Audit Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Bool.
From Coq Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

(** ** 1. Core Geometric Primitives (Blink Physical & Logical Units) *)

(** Represents Blink's [LayoutUnit] / [PhysicalOffset] in subpixel integers. *)
Record PhysicalOffset : Type := mkPhysicalOffset {
  phys_x