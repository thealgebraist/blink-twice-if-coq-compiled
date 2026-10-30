### 1. Core Data Structures in Blink Float Exclusions (LayoutNG)

In Chromium’s Blink engine (`third_party/blink/renderer/core/layout/`), float placement is governed by the Block Formatting Context (BFC) coordinate system and managed via an immutable, copy-on-write state container called `ExclusionSpace`.

#### `BfcOffset` and `BfcRect`
Coordinates within a BFC are represented in logical space (abstracting writing modes into `line_offset` $\equiv x$ and `block_offset` $\equiv y$).
* **`BfcOffset`**: `{ LayoutUnit line_offset; LayoutUnit block_offset; }`. Represents a 2D point $(x, y)$ relative to the BFC origin.
* **`BfcRect`**: `{ BfcOffset start_offset; BfcOffset end_offset; }`. Defines a half-open logical bounding box $[x_{\text{start}}, x_{\text{end}}) \times [y_{\text{start}}, y_{\text{end}})$.
  * $\text{InlineSize} = \max(0, x_{\text{end}} - x_{\text{start}})$
  * $\text{BlockSize} = \max(0, y_{\text{end}} - y_{\text{start}})$

#### `EFloat` / `ExclusionType`
Categorizes the float alignment relative to the BFC edges:
* `kFloatLeft`: Aligned against the left BFC boundary or the right edge of prior left-aligned exclusions.
* `kFloatRight`: Aligned against the right BFC boundary or the left edge of prior right-aligned exclusions.

#### `ExclusionShapeData`
Optional geometric payload attached to an exclusion when `shape-outside` is specified:
* Encapsulates the CSS shape geometry (`LayoutBox`, `MarginStrut`, shape insets) used to compute non-rectangular inline intervals at specific block bands $[y_1, y_2)$. Under CSS 2.1 §9.5 (rectangular margin boxes), this pointer is `nullptr`.

#### `Exclusion`
An immutable representation of a placed float inside the BFC:
* `const BfcRect rect`: The margin box of the float in BFC coordinates.
* `const EFloat type`: `kFloatLeft` or `kFloatRight`.
* `const ExclusionShapeData* shape_data`: Optional shape descriptor.

#### `LayoutOpportunity`
Represents a contiguous, rectangular region in the BFC that is completely free of float exclusions and available for placing inline content, new floats, or formatting context roots (`new BFCs`):
* `BfcRect rect`: The bounding box $[x_{\text{start}}, x_{\text{end}}) \times [y_{\text{start}}, y_{\text{end}})$. Note that $y_{\text{end}}$ may be `LayoutUnit::Max()` if the opportunity is unbounded below.
* `ExclusionShapeData* shape_data`: Present if the opportunity is constrained by non-rectangular float shapes.

#### `ExclusionSpace` (Internal Architecture: `ExclusionSpaceInternal`)
To avoid $O(N^2)$ searches when placing $N$ floats, Blink segments the BFC along the block axis into **`Shelf`** structures:
* **Shelf (`NGExclusionShelf`)**: A horizontal band at a specific `block_offset` ($y$) that tracks the innermost protruding edges of all floats intersecting that band:
  * `LayoutUnit block_offset`: The $y$-coordinate where this shelf begins (typically the bottom edge of a terminated float).
  * `LayoutUnit line_left`: $\max \{ x_{\text{end}} \mid \text{float } f \in \text{LeftFloats}, y \in [f.y_{\text{start}}, f.y_{\text{end}}) \}$.
  * `LayoutUnit line_right`: $\min \{ x_{\text{start}} \mid \text{float } f \in \text{RightFloats}, y \in [f.y_{\text{start}}, f.y_{\text{end}}) \}$.
* **Clearance & High-Water Marks**:
  * `left_clear_offset_`: $\max_{f \in \text{LeftFloats}} (f.y_{\text{end}})$.
  * `right_clear_offset_`: $\max_{f \in \text{RightFloats}} (f.y_{\text{end}})$.
  * `last_float_block_start_`: $\max_{f \in \text{AllFloats}} (f.y_{\text{start}})$. Enforces CSS 2.1 §9.5.1 Rule 6 (a float’s top may not be higher than the top of any earlier float).

---

### 2. Layout Opportunity Finding Algorithm

Given an `ExclusionSpace` $\mathcal{E}$, a starting `BfcOffset` $O_{\text{origin}} = (x_{\text{orig}}, y_{\text{orig}})$, an available inline size $W_{\text{avail}}$, and a minimum required inline size $W_{\text{req}}$ (for the target box), Blink computes layout opportunities via a **Shelf-Sweep Algorithm**:

#### Step 1: Effective Search Origin
To enforce CSS 2.1 §9.5.1 Rule 6 for floats (or BFC roots), the starting block offset is clamped to the highest prior float top if searching for a float placement:
$$y_0 = \max(y_{\text{orig}}, \mathcal{E}.\text{last\_float\_block\_start})$$
For regular inline line-boxes or inflow BFCs, $y_0 = y_{\text{orig}}$.
The initial inline bounds of the container are $[L_{\text{base}}, R_{\text{base}}] = [x_{\text{orig}}, \max(x_{\text{orig}}, x_{\text{orig}} + W_{\text{avail}})]$.

#### Step 2: Active Interval Extraction at Block Offset $y$
For any block offset $y \ge y_0$, the set of active exclusions $\mathcal{A}(y)$ consists of all exclusions $e \in \mathcal{E}$ where $e.y_{\text{end}} > y$.
Specifically, at slice $y$, the available inline interval $[L(y), R(y))$ is bounded by:
$$L(y) = \max \left( L_{\text{base}}, \max \{ e.x_{\text{end}} \mid e \in \mathcal{E}_{\text{left}} \land y \in [e.y_{\text{start}}, e.y_{\text{end}}) \} \right)$$
$$R(y) = \min \left( R_{\text{base}}, \min \{ e.x_{\text{start}} \mid e \in \mathcal{E}_{\text{right}} \land y \in [e.y_{\text{start}}, e.y_{\text{end}}) \} \right)$$
To ensure well-formedness when left and right floats overlap horizontally (e.g., inside an over-constrained container), Blink normalizes the interval:
$$R_{\text{norm}}(y) = \max(L(y), R(y))$$

#### Step 3: Vertical Sweeping (Shelf Iteration & "Closed-Out" Areas)
Blink maintains a sorted list of shelves at the bottom edges ($e.y_{\text{end}}$) of all exclusions, plus a sentinel shelf at $y = +\infty$.
For each shelf $S_i$ at $y_{\text{shelf}} \ge y_0$:
1. Initialize the candidate opportunity top: $y_{\text{top}} = \max(y_0, S_i.\text{block\_offset})$.
2. Initialize inline bounds $[x_L, x_R] = [S_i.\text{line\_left}, S_i.\text{line\_right}]$ clamped to $[L_{\text{base}}, R_{\text{base}}]$.
3. **Downward Intersection Scan**: Iterate through subsequent exclusions/shelves $S_j$ ($j > i$) whose block start $y_{\text{start}} > y_{\text{top}}$:
   * If an exclusion $e$ starts below $y_{\text{top}}$ and narrows the interval $[x_L, x_R]$:
     * Emit a bounded `LayoutOpportunity`: $[x_L, \max(x_L, x_R)) \times [y_{\text{top}}, e.y_{\text{start}})$.
     * Update $[x_L, x_R]$ by intersecting with $e$’s inline bounds:
       $$x_L \leftarrow \max(x_L, e.x_{\text{end}}) \text{ (if Left)}, \quad x_R \leftarrow \min(x_R, e.x_{\text{start}}) \text{ (if Right)}$$
   * If $x_R - x_L < W_{\text{req}}$, terminate the downward extension for shelf $S_i$ and advance to $S_{i+1}$.
4. The first emitted `LayoutOpportunity` whose inline size $(x_R - x_L) \ge W_{\text{req}}$ and block size $(y_{\text{end}} - y_{\text{top}}) \ge H_{\text{req}}$ is selected to place the float or BFC box.
   * **Fallback Rule (CSS 2.1 §9.5.1 Rule 7)**: If an opportunity is vertically unbounded ($y_{\text{end}} = +\infty$) and has no active exclusions ($x_L = L_{\text{base}}, x_R = R_{\text{base}}$), it is unconditionally selected even if $x_R - x_L < W_{\text{req}}$ (preventing infinite downward loops when a float is wider than the BFC container itself).

---

### 3. Clearance Calculation (`clear: left | right | both`)

In CSS 2.1 §9.5.2, the `clear` property requires the border edge (or for a float, the top margin edge) of the box to be placed at or below the bottom outer (margin) edges of all relevant earlier floats in the same BFC.

In Blink’s `ExclusionSpace`, clearance is resolved in $O(1)$ time via maintained high-water marks:

$$\text{ClearOffset}(\mathcal{E}, \text{type}) = \begin{cases} 
-\infty \text{ (or } 0\text{)} & \text{if } \text{type} = \texttt{EClear::kNone} \\
\mathcal{E}.\text{left\_clear\_offset\_} & \text{if } \text{type} = \texttt{EClear::kLeft} \\
\mathcal{E}.\text{right\_clear\_offset\_} & \text{if } \text{type} = \texttt{EClear::kRight} \\
\max(\mathcal{E}.\text{left\_clear\_offset\_}, \mathcal{E}.\text{right\_clear\_offset\_}) & \text{if } \text{type} = \texttt{EClear::kBoth}
\end{cases}$$

When advancing the block cursor $y_{\text{cursor}}$ (either in `BlockLayoutAlgorithm::ResolveBfcBlockOffset` for inflow boxes or `UnpositionedFloat` placement for floats):
$$y_{\text{cleared}} = \max\left(y_{\text{cursor}}, \text{ClearOffset}(\mathcal{E}, \text{clear\_type})\right)$$

---

### 4. Mathematical Invariants

1. **Layout Opportunity Well-Formedness**:
   For every `LayoutOpportunity` $O = ([x_1, x_2), [y_1, y_2))$ generated by `FindLayoutOpportunity`:
   $$x_1 \le x_2 \quad \land \quad y_1 \le y_2$$
2. **Monotonicity of Clearance & High-Water Marks**:
   For any `ExclusionSpace` $\mathcal{E}$ and any newly added exclusion $e$, let $\mathcal{E}' = \text{Add}(\mathcal{E}, e)$ and $y \in \mathbb{Z}$. For all $\text{c} \in \{\texttt{None}, \texttt{Left}, \texttt{Right}, \texttt{Both}\}$:
   $$\text{ClearOffset}(\mathcal{E}, c) \le \text{ClearOffset}(\mathcal{E}', c) \quad \text{and} \quad y \le \text{ApplyClearance}(\mathcal{E}, c, y)$$
3. **Float Non-Overlapping Property (CSS 2.1 §9.5.1 Rules 2, 3, 5, 6)**:
   For any sequence of floats $f_1, f_2, \dots, f_n$ placed sequentially via `PlaceFloat` into an initially empty `ExclusionSpace`, no two placed floats $f_i, f_j$ ($i \neq j$) have intersecting interiors:
   $$\forall i \neq j, \quad \text{Interior}(f_i.\text{rect}) \cap \text{Interior}(f_j.\text{rect}) = \emptyset$$
   where $\text{Interior}([x_1, x_2) \times [y_1, y_2)) \cap \text{Interior}([x'_1, x'_2) \times [y'_1, y'_2)) = \emptyset \iff (x_2 \le x'_1 \lor x'_2 \le x_1 \lor y_2 \le y'_1 \lor y'_2 \le y_1)$.
4. **Determinism**:
   Because `ExclusionSpace` transitions and `FindLayoutOpportunity` are pure mathematical functions over fixed-point `LayoutUnit` ($\cong \mathbb{Z}$) arithmetic, identical input states and float sequences produce bit-identical `BfcRect` placements.

---

### 5. Rocq / Coq Formalization (`BlinkFloatExclusionSemantics.v`)

The following self-contained Rocq (Coq 8.18+) script formalizes the core data structures, the interval extraction, the clearance computation, the float placement algorithm, and proves all four mathematical invariants without any admitted axioms.

```coq
(** * BlinkFloatExclusionSemantics.v
    Formal verification of Chromium Blink's LayoutNG ExclusionSpace,
    LayoutOpportunity finding, Clearance, and CSS 2.1 Section 9.5 invariants. *)

From Coq Require Import ZArith List Bool Lia.
Import ListNotations.
Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** Blink LayoutUnit is a 32-bit fixed-point integer (1/64th pixel).
    We model it exactly in Z. *)
Definition LayoutUnit := Z.

Record BfcOffset : Type := mkBfcOffset {
  line_offset : LayoutUnit;
  block_offset : LayoutUnit
}.

Record BfcRect : Type := mkBfcRect {
  start_offset : BfcOffset;
  end_offset : BfcOffset
}.

Definition rect_x_start (r : BfcRect) : LayoutUnit := line_offset (start_offset r).
Definition rect_y_start (r : BfcRect) : LayoutUnit := block_offset (start_offset r).
Definition rect_x_end   (r : BfcRect) : LayoutUnit := line_offset (end_offset r).
Definition rect_y_end   (r : BfcRect) : LayoutUnit := block_offset (end_offset r).

Definition inline_size (r : BfcRect) : LayoutUnit :=
  Z.max 0 (rect_x_end r - rect_x_start r).

Definition block_size (r : BfcRect) : LayoutUnit :=
  Z.max 0 (rect_y_end r - rect_y_start