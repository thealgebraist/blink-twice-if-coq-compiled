### 1. Core Data Structures in Blink Table Border Resolution

In Chromium’s Blink rendering engine (specifically within LayoutNG’s table implementation in `third_party/blink/renderer/core/layout/table/`), collapsed border resolution is decoupled from layout tree construction and represented via flat, cache-efficient structures.

#### `EBorderStyle`
Defined in `computed_style_constants.h`, `EBorderStyle` enumerates the CSS `<line-style>` values. While its memory representation is an `uint8_t` ordered for general style resolution, table border conflict resolution projects it onto a distinct priority space:
```cpp
enum class EBorderStyle : uint8_t {
  kNone, kHidden, kInset, kGroove, kOutset, kRidge, kDotted, kDashed, kSolid, kDouble
};
```

#### `BorderPrecedence` (Box Priority)
Blink encodes the origin of a border specification via an explicit precedence hierarchy representing the structural containment of the table elements:
```cpp
enum class BorderPrecedence : uint8_t {
  kNone = 0,
  kTable = 1,
  kColumnGroup = 2,
  kColumn = 3,
  kRowGroup = 4,
  kRow = 5,
  kCell = 6
};
```

#### `TableBorderEdge` (or `NGTableBorders::Edge`)
The atomic unit of border conflict resolution. To minimize memory footprint across large tables, Blink packs edge properties into a compact structure:
```cpp
struct Edge {
  LayoutUnit width;                 // 26.6 fixed-point representation (or uint32_t pixels)
  EBorderStyle style : 4;           // CSS border-style
  BorderPrecedence precedence : 3;  // Structural origin
  uint32_t box_order : 25;          // Tie-breaker: DOM/visual traversal index
  Color color;                      // Resolved CSS color
};
```
*Note: In modern LayoutNG (`NGTableBorders`), instead of storing `LayoutUnit` directly inside every `Edge` in the grid, Blink stores an index into a deduplicated vector of border specifications, resolving widths on demand via `ComputedStyle`.*

#### `TableBorders` (`NGTableBorders`)
The container managing the 2D grid of resolved edges. For a table with $R$ rows and $C$ columns:
* **Horizontal Edges:** $(R + 1) \times C$ matrix.
* **Vertical Edges:** $R \times (C + 1)$ matrix.

During `NGTableBorders::ComputeTableBorders`, Blink iterates through the structural hierarchy (Table $\to$ ColGroups $\to$ Cols $\to$ RowGroups $\to$ Rows $\to$ Cells) and merges candidate edges into the grid slots using `MergeEdge()`, which implements the CSS 2.1 §17.6.2.1 conflict resolution comparator.

---

### 2. Conflict Resolution Rules (CSS 2.1 §17.6.2.1 vs. Blink)

When two borders $e_1$ and $e_2$ compete for the same grid segment, the winning edge is selected via a lexicographical cascade of predicates. Let $W(e)$, $S(e)$, $P(e)$, and $O(e)$ denote width, style, structural precedence, and spatial/DOM order, respectively.

#### Step 1: Unconditional Suppression (`hidden`)
If either $S(e_1) = \text{kHidden}$ or $S(e_2) = \text{kHidden}$, the resolved border is suppressed. In Blink, `kHidden` maps to the highest priority in the style comparator, or is handled by an early-exit branch that forces the winning edge to have `style = kHidden` and `width = 0`.

#### Step 2: Unconditional Yield (`none`)
If $S(e) = \text{kNone}$ (or effective width is $0$ without being `kHidden`), it yields to any visible border. If both are `kNone`, the result is `kNone`.

#### Step 3: Width Comparison
For two visible, non-hidden edges, the wider border wins:
$$W(e_1) > W(e_2) \implies e_1 \text{ wins}$$
*Blink Implementation Detail:* Widths are compared as `LayoutUnit` (or snapped integer pixels depending on the zoom/subpixel phase) *before* style evaluation.

#### Step 4: Style Priority
If $W(e_1) = W(e_2)$, the border style breaks the tie according to the strict ordering:
$$\text{double} > \text{solid} > \text{dashed} > \text{dotted} > \text{ridge} > \text{outset} > \text{groove} > \text{inset}$$

#### Step 5: Structural Precedence (Tree Hierarchy)
If $W(e_1) = W(e_2)$ and $S(e_1) = S(e_2)$, the structural origin breaks the tie:
$$\text{cell} > \text{row} > \text{rowgroup} > \text{col} > \text{colgroup} > \text{table}$$

#### Step 6: Spatial / DOM Tie-Breaking
If two edges originate from the same structural level (e.g., two adjacent cells sharing an edge, both having `2px solid` borders of different colors), CSS 2.1 specifies:
* **Horizontal conflict (East/West):** The further left (in `ltr`) or right (in `rtl`) wins.
* **Vertical conflict (North/South):** The further top wins.

Blink encodes this by merging edges in a deterministic traversal order (top-to-bottom, inline-start to inline-end). In `MergeEdge(existing, candidate)`, if all properties up to Step 5 are equal, `existing` is retained:
$$\text{if } (e_1 \equiv_{\text{W,S,P}} e_2) \text{ then } (\text{if } O(e_1) < O(e_2) \text{ then } e_1 \text{ else } e_2)$$

---

### 3. Order-Theoretic Properties of the Resolution Operator

Let $\mathcal{E}$ be the set of all valid border edge specifications.

#### Total Preorder on Intrinsic Properties
Define the projection $\pi(e) = (\text{is\_hidden}(e), \text{is\_visible}(e), W(e), \text{rank}_S(S(e)), \text{rank}_P(P(e)))$ mapping $\mathcal{E}$ into $\mathbb{B} \times \mathbb{B} \times \mathbb{N} \times \{0..9\} \times \{0..6\}$.

Equipped with the standard lexicographical order $\le_{\text{lex}}$, the relation $e_1 \precsim e_2 \iff \pi(e_1) \le_{\text{lex}} \pi(e_2)$ is a **total preorder**:
1. **Totality:** For any $e_1, e_2 \in \mathcal{E}$, either $\pi(e_1) \le_{\text{lex}} \pi(e_2)$ or $\pi(e_2) \le_{\text{lex}} \pi(e_1)$ because $\le_{\text{lex}}$ is a product of total orders on finite/countable domains ($\mathbb{B}, \mathbb{N}$).
2. **Transitivity:** Inherited directly from the transitivity of the componentwise total orders on $\mathbb{B}$ and $\mathbb{N}$.
3. **Failure of Antisymmetry:** Two edges with identical widths, styles, and structural origins—but distinct `Color` values—satisfy $e_1 \precsim e_2$ and $e_2 \precsim e_1$, yet $e_1 \neq e_2$. Thus, $\precsim$ is a preorder, not a partial order.

#### Strict Total Order and Determinism via Traversal Indexing
To achieve **antisymmetry** and **determinism**, Blink augments the state space with the unique traversal index $O(e) \in \mathbb{N}$ (representing the strict sequence in which box edges are visited during `ComputeTableBorders`).

Define the extended projection $\Pi(e) = (\pi(e), -O(e))$. Since every candidate edge invocation occurs at a distinct step in the execution trace, $O(e_1) = O(e_2) \iff e_1 = e_2$ (as edge instances).
* **Antisymmetry:** $\Pi(e_1) \le_{\text{lex}} \Pi(e_2) \land \Pi(e_2) \le_{\text{lex}} \Pi(e_1) \implies \pi(e_1) = \pi(e_2) \land O(e_1) = O(e_2) \implies e_1 = e_2$.
* **Determinism (Associativity & Path Independence):** The binary resolution operator $e_1 \oplus e_2 = \max_{\Pi}(e_1, e_2)$ forms a **selective, associative, commutative semilattice** over any set of edges with distinct traversal indices. Consequently, the final border resolved for any grid segment is invariant under the grouping of pairwise comparisons.

---

### 4. Half-Width Distribution in 26.6 `LayoutUnit` Arithmetic

In the collapsed border model, a resolved border of width $W$ straddles the grid line between two adjacent cells. CSS 2.1 §17.6.2 specifies that the border is centered on the grid line. When $W$ is not an even multiple of the minimum layout quantum, symmetric halving is impossible, requiring an asymmetric distribution rule.

#### Blink's `LayoutUnit` Representation
Blink represents lengths using `LayoutUnit`, a 32-bit signed fixed-point number with 26 integer bits and 6 fractional bits (quantum $\epsilon = \frac{1}{64} \text{ px}$). Let $w \in \mathbb{Z}_{\ge 0}$ be the raw integer value backing `LayoutUnit` (i.e., $W = w \cdot 2^{-6}\text{ px}$).

#### Asymmetric Halving Formula
When computing the box geometry (padding-box and content-box offsets) of cells in `NGTableBorders::CellBorder()`, Blink splits the shared edge raw value $w$ into two components: $w_{\text{before}}$ (top or inline-start of the grid line) and $w_{\text{after}}$ (bottom or inline-end of the grid line).

In C++ integer arithmetic:
```cpp
LayoutUnit w_before = border_width / 2;
LayoutUnit w_after = border_width - w_before;
```
At the raw representation level ($w \in \mathbb{N}$):
1. **Inline-Start / Block-Start side of the grid line** (extending into the Top or Left cell, i.e., its *bottom* or *right* border contribution):
   $$w_{\text{before}} = \left\lfloor \frac{w}{2} \right\rfloor$$
2. **Inline-End / Block-End side of the grid line** (extending into the Bottom or Right cell, i.e., its *top* or *left* border contribution):
   $$w_{\text{after}} = w - \left\lfloor \frac{w}{2} \right\rfloor = \left\lceil \frac{w}{2} \right\rceil$$

*(Note: Depending on whether Blink is computing the table's outer intrinsic padding or internal cell offsets, the extra $\frac{1}{64}\text{px}$ (or $1\text{px}$ after pixel-snapping) is consistently biased toward the `after`/`end` side of the grid line so that $w_{\text{before}} + w_{\text{after}} = w$ holds strictly without loss or creation of subpixels).*

---

### 5. Formalization in Rocq / Coq (`BlinkTableBorderConflictSemantics.v`)

The following complete, self-contained Coq vernacular script formalizes the Blink data structures, the conflict resolution cascade, the order-theoretic proofs (reflexivity, transitivity, totality, antisymmetry, associativity), and the `LayoutUnit` conservation laws.

```coq
(** * BlinkTableBorderConflictSemantics.v
    Formal verification of Chromium Blink's CSS 2.1 §17.6.2.1
    Collapsed Table Border Conflict Resolution and 26.6 LayoutUnit Halving. *)

From Coq Require Import Arith PeanoNat Bool List Lia.
Import ListNotations.

(** ** 1. Core Data Structures *)

Inductive EBorderStyle : Type :=
  | kNone
  | kHidden
  | kInset
  | kGroove
  | kOutset
  | kRidge
  | kDotted
  | kDashed
  | kSolid
  | kDouble.

Inductive BorderPrecedence : Type :=
  | kPrecNone
  | kTable
  | kColumnGroup
  | kColumn
  | kRowGroup
  | kRow
  | kCell.

(** Abstract representation of resolved CSS Color. *)
Definition Color := nat.

(** 26.6 Fixed-Point LayoutUnit represented by its raw integer backing (units of 1/64 px). *)
Definition LayoutUnit := nat.

Record TableBorderEdge : Type := mkEdge {
  edge_width      : LayoutUnit;
  edge_style      : EBorderStyle;
  edge_precedence : BorderPrecedence;
  edge_box_order  : nat; (* Strictly monotonic traversal index; smaller = earlier *)
  edge_color      : Color
}.

(** ** 2. Priority Projections and Conflict Resolution Rules *)

(** Style priority ranking per CSS 2.1 §17.6.2.1:
    double > solid > dashed > dotted > ridge > outset > groove > inset > none.
    Note: kHidden is handled at the top of the lexicographical cascade,
    but also given maximum rank here for structural uniformity. *)
Definition style_rank (s : EBorderStyle) : nat :=
  match s with
  | kNone   => 0
  | kInset  => 1
  | kGroove => 2
  | kOutset => 3
  | kRidge  => 4
  | kDotted => 5
  | kDashed => 6
  | kSolid  => 7
  | kDouble => 8
  | kHidden => 9
  end.

(** Structural hierarchy precedence:
    cell > row > rowgroup > col > colgroup > table > none. *)
Definition precedence_rank (p : BorderPrecedence) : nat :=
  match p with
  | kPrecNone    => 0
  | kTable       => 1
  | kColumnGroup => 2
  | kColumn      => 3
  | kRowGroup    => 4
  | kRow         => 5
  | kCell        => 6
  end.

(** Effective width: in Blink, an edge with style 'none' or 'hidden' has 0 effective width
    for visual rendering, though 'hidden' dominates conflict resolution before width is checked. *)
Definition effective_width (e : TableBorderEdge) : LayoutUnit :=
  match edge_style e with
  | kNone | kHidden => 0
  | _ => edge_width e
  end.

Definition is_hidden_rank (e : TableBorderEdge) : nat :=
  match edge_style e with
  