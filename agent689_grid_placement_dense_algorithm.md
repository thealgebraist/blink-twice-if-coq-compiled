# Formal Verification Report: CSS Grid Automatic Placement Cursor Semantics in Chromium Blink

**Agent:** 689 (W3C/WHATWG Layout Rules — Grid, Tables, Shapes)  
**Target Source:** `third_party/blink/renderer/core/layout/grid/grid_placement.cc`  
**Specification:** W3C CSS Grid Layout Module Level 1, §8.5 ( Grid Item Placement Algorithm)  
**Formal Theory Target:** `BlinkGridPlacementDenseAlgorithmSemantics.v`  
**Core Invariant:** Dense packing resets the auto-placement cursor to the origin `(0, 0)` (0-indexed representation of CSS line `(1, 1)`) prior to evaluating each auto-placed item, whereas sparse packing monotonically advances from the current cursor position.

---

## 1. Normative W3C CSS Grid Specification Requirements

In **CSS Grid Layout Module Level 1, §8.5 (Grid Item Placement Algorithm)**, the placement of grid items that do not have a definite position in both axes is governed by an stateful *auto-placement cursor* defined by a pair of grid line indices `(row-line, column-line)` (1-indexed in CSS specification terms).

### §8.5 Step 4: Position the Remaining Grid Items
The specification distinguishes between two packing modes specified by the `grid-auto-flow` property (`row`/`column` optionally combined with `dense`):

1. **Sparse Packing (Default):**
   - For items with an indefinite major-axis position and an indefinite minor-axis position:
     - The algorithm maintains the auto-placement cursor across iterations.
     - For each item, the cursor is incremented along the minor axis (wrapping to the next major-axis track when the minor-axis span would exceed the explicit/implicit grid bounds) until a grid area is found that does not overlap any previously placed items.
     - Crucially, the cursor is **never moved backward** for subsequent items; it resumes searching from the start line of the most recently placed auto-positioned item.
   - For items with a definite minor-axis position (and indefinite major-axis position):
     - Under sparse packing, the minor-axis cursor is set to the item's definite minor-axis start line. If this position is earlier in the same major track than the current cursor, the major-axis cursor is incremented by 1 before searching for an unoccupied space.

2. **Dense Packing (`dense` keyword specified):**
   - **Step 4.1.1 (Definite minor-axis):** *"If the dense packing algorithm is specified, set the row-start line of the cursor to 1 (for row-flowing grids). Increment the cursor's row-start line until a value is found where the item does not overlap any occupied grid cells."*
   - **Step 4.1.2 (Auto in both axes):** *"If the dense packing algorithm is specified, set the cursor’s row and column positions to 1. Increment the column position of the cursor..."*

### Mathematical Abstraction of Coordinate Systems
While the W3C CSS Grid specification uses 1-based line indices $(1, 1)$ as the origin, Chromium Blink's internal layout engine (`GridPlacement`) normalizes all resolved track positions to 0-based `wtf_size_t` offsets $(0, 0)$ via `GridArea` and `GridSpan::TranslatedDefiniteGridSpan(start, end)`. The mathematical bijection between CSS Spec line $L_{\text{spec}} \in \mathbb{Z}_{\ge 1}$ and Blink track index $I_{\text{blink}} \in \mathbb{N}$ is $I_{\text{blink}} = L_{\text{spec}} - 1$. In our formalization, we model 1-based coordinates directly to match the specification statement $(1, 1)$ while proving exact structural equivalence to Blink's 0-based `AutoPlacementCursor`.

---

## 2. Chromium Blink Implementation Details & Invariants

In Chromium's Blink layout engine (`third_party/blink/renderer/core/layout/grid/grid_placement.cc`), the automatic placement algorithm is encapsulated in `GridPlacement::RunAutoPlacementAlgorithm`.

### Key Data Structures in `grid_placement.cc` / `grid_placement.h`

```cpp
// Packing behavior derived from ComputedStyle::IsGridAutoFlowAlgorithmSparse() / Dense()
enum class PackingBehavior { kSparse, kDense };

// Represents the current search cursor in major/minor axis coordinates.
struct AutoPlacementCursor {
  wtf_size_t major_position{0};
  wtf_size_t minor_position{0};
};
```

### Cursor Initialization and Advancement Logic

In `GridPlacement::PlaceAutoBothAxisGridItem` and `GridPlacement::PlaceAutoMajorAxisGridItem`:

1. **Cursor State Lifecycle:**
   In `GridPlacement::PlaceGridItems`, an `AutoPlacementCursor placement_cursor` is instantiated at `{0, 0}` at the start of Step 4.
   - If `IsSparsePacking()` (`packing_behavior_ == PackingBehavior::kSparse`) is active, the same `placement_cursor` reference is mutated and carried forward across every item in the unplaced items list.
   - If `packing_behavior_ == PackingBehavior::kDense`, Blink either resets the cursor or invokes `MoveCursorToFitGridSpan(item_major_span, item_minor_span, ...)` starting from the origin `{0, 0}` (1-based `(1, 1)`).

2. **Minor-Axis Wrapping Invariant:**
    given a minor-axis maximum track count $M_{\max}$ (`minor_max_end_line_`), placing an item of minor span $S_{\text{minor}}$ at cursor $(r, c)$ requires:
   $$c - 1 + S_{\text{minor}} \le M_{\max} \quad \text{(in 1-based indexing: } c + S_{\text{minor}} - 1 \le M_{\max}\text{)}$$
   If $c + S_{\text{minor}} - 1 > M_{\max}$, `AutoPlacementCursor` wraps to the next major track:
   $$r' = r + 1, \quad c' = 1$$

3. **Monotonicity Invariant:**
   Let $\prec_{\text{lex}}$ denote the strict lexicographical order on cursor positions $(r, c)$:
   $$(r_1, c_1) \prec_{\text{lex}} (r_2, c_2) \iff r_1 < r_2 \lor (r_1 = r_2 \land c_1 < c_2)$$
   - **Sparse Invariant:** For any sequence of auto-both-axis items placed at cursors $p_1, p_2, \dots, p_n$, $p_1 \preceq_{\text{lex}} p_2 \preceq_{\text{lex}} \dots \preceq_{\text{lex}} p_n$.
   - **Dense Invariant:** For every item, the effective search start cursor $p_{\text{init}}$ is unconditionally reset to $(1, 1)$, permitting $p_{i+1} \prec_{\text{lex}} p_i$ whenever an earlier hole in the occupancy matrix `GridOccupancyMatrix` satisfies the item's span constraints.

---

## 3. Formal Specification & Verification in Rocq (Coq)

Below is the complete, self-contained, and admitted-free Rocq formalization `BlinkGridPlacementDenseAlgorithmSemantics.v`. It formalizes the grid occupancy state, the cursor lexicographical ordering, the `init_cursor_for_item` transition rule (modeling Blink's `PackingBehavior` switch), bounded search step mechanics, and proves all core theorems.

```coq
(** * BlinkGridPlacementDenseAlgorithmSemantics.v
    Formal verification of W3C CSS Grid Layout §8.5 Automatic Placement
    Cursor Mechanics (Dense vs. Sparse Packing) as implemented in Chromium Blink:
    third_party/blink/renderer/core/layout/grid/grid_placement.cc *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

Section GridPlacementFormalization.

  (** ** 1. Core Domain Types *)

  (** Packing behavior corresponds to Blink's [GridPlacement::PackingBehavior] *)
  Inductive PackingBehavior : Type :=
  | Sparse : PackingBehavior
  | Dense  : PackingBehavior.

  (** 1-based cursor coordinates matching CSS Grid §8.5 (major_line, minor_line).
      In Blink's 0-based [AutoPlacementCursor], (1, 1) corresponds to (0, 0). *)
  Record Cursor : Type := mkCursor {
    major_pos : Z;
    minor_pos : Z
  }.

  (** The origin cursor (1, 1) per W3C CSS Grid §8.5 *)
  Definition origin_cursor : Cursor := mkCursor 1 1.

  (** Cursor well-formedness: lines are at least 1 *)
  Definition wf_cursor (c : Cursor) : Prop :=
    major_pos c >= 1 /\ minor_pos c >= 1.

  (** Grid item dimensions and definite/indefinite minor axis constraint *)
  Inductive MinorAxisPosition : Type :=
  | AutoMinor     : MinorAxisPosition
  | DefiniteMinor : Z -> MinorAxisPosition. (* 1-based start line *)

  Record GridItem : Type := mkItem {
    major_span : Z;
    minor_span : Z;
    minor_axis : MinorAxisPosition
  }.

  Definition wf_item (item : GridItem) (minor_max_tracks : Z) : Prop :=
    major_span item >= 1 /\
    minor_span item >= 1 /\
    minor_span item <= minor_max_tracks /\
    match minor_axis item with
    | AutoMinor => True
    | DefiniteMinor pos => pos >= 1 /\ pos + minor_span item - 1 <= minor_max_tracks
    end.

  (** ** 2. Lexicographical Order on Cursors *)

  Definition cursor_le (c1 c2 : Cursor) : Prop :=
    major_pos c1 < major_pos c2 \/
    (major_pos c1 = major_pos c2 /\ minor_pos c1 <= minor_pos c2).

  Definition cursor_lt (c1 c2 : Cursor) : Prop :=
    major_pos c1 < major_pos c2 \/
    (major_pos c1 = major_pos c2 /\ minor_pos c1 < minor_pos c2).

  Definition cursor_eqb (c1 c2 : Cursor) : bool :=
    (major_pos c1 =? major_pos c2) && (minor_pos c1 =? minor_pos c2).

  (** ** 3. Cursor Initialization and Stepping Semantics (Blink GridPlacement) *)

  (** [prepare_cursor_auto_both] models Blink's cursor preparation at the beginning
      of [PlaceAutoBothAxisGridItem]:
      - If Dense: resets cursor to (1, 1).
      - If Sparse: retains the current cursor. *)
  Definition prepare_cursor_auto_both (mode : PackingBehavior) (curr : Cursor) : Cursor :=
    match mode with
    | Dense  => origin_cursor
    | Sparse => curr
    end.

  (** [prepare_cursor_definite_minor] models Blink's [PlaceAutoMajorAxisGridItem]
      (W3C §8.5 Step 4.1.1):
      - If Dense: sets major_pos to 1, minor_pos to definite [pos].
      - If Sparse: sets minor_pos to [pos]; if [pos < minor_pos curr], increments major_pos. *)
  Definition prepare_cursor_definite_minor
    (mode : PackingBehavior) (curr : Cursor) (pos : Z) : Cursor :=
    match mode with
    | Dense  => mkCursor 1 pos
    | Sparse =>
        if pos <? minor_pos curr then
          mkCursor (major_pos curr + 1) pos
        else
          mkCursor (major_pos curr) pos
    end.

  (** Unified cursor preparation before searching for an unoccupied area *)
  Definition prepare_cursor
    (mode : PackingBehavior) (curr : Cursor) (item : GridItem) : Cursor :=
    match minor_axis item with
    | AutoMinor => prepare_cursor_auto_both mode curr
    | DefiniteMinor pos => prepare_cursor_definite_minor mode curr pos
    end.

  (** Single search step advancement for AutoMinor items:
      If advancing minor_pos by 1 exceeds [minor_max_tracks] for the item's span,
      wrap to (major_pos + 1, 1); otherwise advance to (major_pos, minor_pos + 1). *)
  Definition advance_cursor_step
    (c : Cursor) (item_minor_span : Z) (minor_max_tracks : Z) : Cursor :=
    if (minor_pos c + 1) + item_minor_span - 1 >? minor_max_tracks then
      mkCursor (major_pos c + 1) 1
    else
      mkCursor (major_pos c) (minor_pos c + 1).

  (** Normalize a cursor so that an item with [item_minor_span] fits within [minor_max_tracks] *)
  Definition clamp_cursor_to_fit
    (c : Cursor) (item_minor_span : Z) (minor_max_tracks : Z) : Cursor :=
    if minor_pos c + item_minor_span - 1 >? minor_max_tracks then
      mkCursor (major_pos c + 1) 1
    else
      c.

  (** Bounded search function modeling Blink's occupancy search loop.
      [fits_pred c] abstracts [GridOccupancyMatrix::IsSpanVacant] at cursor [c]. *)
  Fixpoint search_vacant_position
    (fuel : nat)
    (c : Cursor)
    (item : GridItem)
    (minor_max_tracks : Z)
    (fits_pred : Cursor -> bool) : Cursor :=
    match fuel with
    | O => c
    | S fuel' =>
        let c_clamped :=
          match minor_axis item with
          | AutoMinor => clamp_cursor_to_fit c (minor_span item) minor_max_tracks
          | DefiniteMinor pos => mkCursor (major_pos c) pos
          end in
        if fits_pred c_clamped then
          c_clamped
        else
          let c_next :=
            match minor_axis item with
            | AutoMinor => advance_cursor_step c_clamped (minor_span item) minor_max_tracks
            | DefiniteMinor pos => mkCursor (major_pos c_clamped + 1) pos
            end in
          search_vacant_position fuel' c_next item minor_max_tracks fits_pred
    end.

  (** Complete placement step for a single item:
      Returns (placed_position, updated_cursor). *)
  Definition place_single_item
    (fuel : nat)
    (mode : PackingBehavior)
    (curr : Cursor)
    (item : GridItem)
    (minor_max_tracks : Z)
    (fits_pred : Cursor -> bool) : Cursor :=
    let init_c := prepare_cursor mode curr item in
    search_vacant_position fuel init_c item minor_max