# Formal Verification Report: CSS Grid `minmax()` Track Sizing Resolution under Min-Content and Max-Content Constraints

**Agent:** Formal Verification Agent 690 (W3C/WHATWG Layout Rules — Grid, Tables, Shapes)  
**Topic:** `minmax()` Track Sizing Resolution under Min-Content and Max-Content Constraints  
**Chromium Source:** `third_party/blink/renderer/core/layout/grid/grid_track_sizing_algorithm.cc`  
**Specification:** CSS Grid Layout Module Level 1 ( and Level 2) §11.1–§11.8 (specifically §11.4 Track Sizing Initialization and §11.5–§11.7 Resolution)  
**Formal Theory Target:** `BlinkGridTrackSizingMinMaxResolutionSemantics.v`  
**Core Mathematical Property:** $\text{resolve\_minmax}(\text{avail}, \text{min\_t}, \text{max\_t}) = \max(\text{min\_t}, \min(\text{avail}, \text{max\_t}))$

---

## 1. Normative W3C CSS Grid Layout Specification Requirements

In the W3C CSS Grid Layout Module Level 1 & 2 specifications, the `minmax(min, max)` functional notation defines a size range greater than or equal to `min` and less than or equal to `max`.

### 1.1 Normative Definition of `minmax(min, max)` (§7.2.1.1)
> **W3C CSS Grid Layout §7.2.1.1:**  
> *"Defines a size range greater than or equal to `min` and less than or equal to `max`. If `max` < `min`, then `max` is ignored and `minmax(min, max)` is treated as `min`. As a maximum, a `<flex>` value sets the track’s flex factor; it is invalid as a minimum."*

### 1.2 Track Sizing Algorithm & Constraint Resolution (§11.1 – §11.7)
The Grid Track Sizing Algorithm converts declarative `GridTrackSize` definitions (`<track-breadth>`, `minmax(min, max)`, `fit-content(limit)`) into concrete layout lengths: a **base size** ($b$) and a **growth limit** ($L$).

1. **Initialize Track Sizes (§11.4):**
   For each track, initialize its base size $b$ and growth limit $L$:
   - **Min Track Sizing Function (`min_t`):**
     - If fixed length or resolvable percentage: $b = \text{resolved\_value}(\text{min\_t})$.
     - If intrinsic (`min-content`, `max-content`, `auto`): $b = 0$.
   - **Max Track Sizing Function (`max_t`):**
     - If fixed length or resolvable percentage: $L = \text{resolved\_value}(\text{max\_t})$.
     - If intrinsic (`min-content`, `max-content`, `auto`, `fit-content`) or flexible (`<flex>`): $L = \infty$ (represented as `kIndefiniteSize` / `-1` in Blink during initialization).
   - **Fundamental Clamping Invariant (§11.4 / §11.5):**
     > *"In all cases, if the growth limit is less than the base size, increase the growth limit to match the base size."*  
     Formally: $L' = \max(b, L)$ whenever $L \neq \infty$.

2. **Resolve Intrinsic Track Sizes (§11.5) & Maximize Tracks (§11.6):**
   - Intrinsic minimum and maximum sizing functions are evaluated using the grid items' min-content and max-content contributions ($C_{\min}, C_{\max}$).
   - After intrinsic contributions are accumulated, tracks are **maximized** (§11.6): the base size $b$ is increased up to the growth limit $L$ using the available free space (`avail`).
   - If `avail` is **definite** ($\ge 0$): tracks grow by distributing free space up to their growth limit $L$, yielding $\min(\text{avail\_for\_track}, L)$, while never dropping below their base size $b = \text{min\_t}$.
   - Putting Initialization (§11.4), Intrinsic Resolution (§11.5), and Maximization (§11.6) together for a resolved minimum bound `min_t`, resolved maximum bound `max_t`, and available space allocation `avail`:
     $$\text{resolve\_minmax}(\text{avail}, \text{min\_t}, \text{max\_t}) = \max(\text{min\_t}, \min(\text{avail}, \text{max\_t}))$$
   - Under a **min-content constraint** ($\text{avail} = 0$):
     $$\text{resolve\_minmax}(0, \text{min\_t}, \text{max\_t}) = \max(\text{min\_t}, \min(0, \text{max\_t})) = \text{min\_t} \quad (\text{for } \text{min\_t}, \text{max\_t} \ge 0)$$
   - Under a **max-content constraint** ($\text{avail} \to \infty$, i.e., $\text{avail} \ge \max(\text{min\_t}, \text{max\_t})$):
     $$\text{resolve\_minmax}(\text{avail}, \text{min\_t}, \text{max\_t}) = \max(\text{min\_t}, \text{max\_t})$$

---

## 2. Chromium Blink Implementation Details & Invariants

In Chromium Blink (`third_party/blink/renderer/core/layout/grid/grid_track_sizing_algorithm.cc`), track sizing operates over `GridSet` structures within `GridTrackCollection`.

### 2.1 Key Data Structures and Constants
- **`LayoutUnit`**: Fixed-point 32-bit signed arithmetic (`kIndefiniteSize = LayoutUnit(-1)`). All resolved physical/logical track sizes are non-negative integers ($z \in \mathbb{Z}_{\ge 0}$) in subpixel units ($\frac{1}{64}\text{px}$).
- **`GridTrackSize`**: Normalizes standalone `<track-breadth>` into `minmax(breadth, breadth)` during style resolution or `GridSet` initialization.
- **` SizingConstraint`**: Enum `{ kLayout, kMinContent, kMaxContent }` controlling how indefinite available space is interpreted.

### 2.2 Core Functions in `grid_track_sizing_algorithm.cc`

1. **`GridTrackSizingAlgorithm::InitializeTrackSizes`**:
   ```cpp
   // Conceptual excerpt from third_party/blink/renderer/core/layout/grid/grid_track_sizing_algorithm.cc
   if (track_size.HasFixedMaxTrackBreadth()) {
     set.SetGrowthLimit( ResolveFixedTrackSize(track_size.MaxTrackBreadth()) );
   } else {
     set.SetGrowthLimit(kIndefiniteSize);
   }
   if (track_size.HasFixedMinTrackBreadth()) {
     set.SetBaseSize( ResolveFixedTrackSize(track_size.MinTrackBreadth()) );
   } else {
     set.SetBaseSize(LayoutUnit());
   }
   // Enforce invariant: GrowthLimit >= BaseSize when definite
   set.EnsureGrowthLimitIsNotLessThanBaseSize();
   ```
   Where `GridSet::EnsureGrowthLimitIsNotLessThanBaseSize()` enforces:
   ```cpp
   if (growth_limit_ != kIndefiniteSize && growth_limit_ < base_size_)
     growth_limit_ = base_size_;
   ```

2. **Intrinsic Resolution (`ResolveIntrinsicTrackSizes`) & Constraint Evaluation**:
   - When evaluating an intrinsic `min_track_breadth` (`min-content` or `max-content`), Blink queries item contributions via `ContributionSizeForGridItem`.
   - Under `SizingConstraint::kMinContent`, available grid space is treated as `0`, forcing `auto` and percentage minimums to resolve against `0` and preventing free-space expansion in `MaximizeTracks`.
   - Under `SizingConstraint::kMaxContent`, available space is unbounded (`kIndefiniteSize`), causing tracks in `MaximizeTracks` to grow directly to their resolved `growth_limit_` (or keep `base_size_` if `growth_limit_ == kIndefiniteSize`).

3. **Track Maximization (`MaximizeTracks` / `DistributeExtraSpaceToSets`)**:
   - For a track with base size `min_t` ($b$) and resolved effective growth limit $\max(\text{min\_t}, \text{max\_t})$ ($L' = \max(b, L)$):
   - When available space `avail` ($\ge 0$) is distributed to the track, its target size is bounded above by `avail` and `max_t`, and bounded below by `min_t`:
     $$\text{final\_size} = \max(\text{min\_t}, \min(\text{avail}, \text{max\_t}))$$
   - Notice the exact algebraic equivalence between:
     1. **Blink's two-step clamped growth**: Start at $b = \text{min\_t}$, clamp growth limit $L' = \max(\text{min\_t}, \text{max\_t})$, and expand up to $\min(\text{avail}, L')$ if $\text{avail} \ge b$:
        $$\text{clamp}(\text{avail}, \text{min\_t}, \max(\text{min\_t}, \text{max\_t})) = \min(\max(\text{avail}, \text{min\_t}), \max(\text{min\_t}, \text{max\_t}))$$
     2. **The direct specification formula**:
        $$\text{resolve\_minmax}(\text{avail}, \text{min\_t}, \text{max\_t}) = \max(\text{min\_t}, \min(\text{avail}, \text{max\_t}))$$

---

## 3. Formal Specification in Rocq / Coq (`BlinkGridTrackSizingMinMaxResolutionSemantics.v`)

Below is the complete, self-contained, admitted-free Rocq/Coq formalization of `BlinkGridTrackSizingMinMaxResolutionSemantics.v`. It models:
1. Track breadths (`Fixed`, `MinContent`, `MaxContent`, `Auto`).
2. `SizingConstraint` (`LayoutConstraint`, `MinContentConstraint`, `MaxContentConstraint`).
3. Intrinsic contribution pairs (`ItemContributions`) and breadth evaluation.
4. Both the algebraic `resolve_minmax` operator and Blink's stateful `GridSet` initialization/maximization pipeline (`EnsureGrowthLimitIsNotLessThanBaseSize` + `MaximizeTracks`).
5. Complete verification of equivalence, monotonicity, idempotence, W3C `max < min` dominance, and constraint specialization.

```coq
(** * BlinkGridTrackSizingMinMaxResolutionSemantics.v
    Formal Verification of W3C CSS Grid Layout §11.4-§11.6 minmax(min, max)
    Track Sizing Resolution in Chromium Blink
    (third_party/blink/renderer/core/layout/grid/grid_track_sizing_algorithm.cc)
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ========================================================================= *)
(** ** 1. Core Types and W3C / Blink Domain Definitions                       *)
(** ========================================================================= *)

(** In Blink, LayoutUnit represents subpixel lengths. Resolved sizes are
    non-negative integers (Z >= 0), while kIndefiniteSize is -1. *)
Definition LayoutUnit := Z.

Definition kIndefiniteSize : LayoutUnit := -1.

Definition is_definite (u : LayoutUnit) : Prop := u >= 0.

(** CSS Grid <track-breadth> sizing functions relevant to minmax(min, max)
    intrinsic & fixed resolution (CSS Grid 1 §7.2.1). *)
Inductive TrackBreadth : Type :=
  | BreadthFixed      (len : LayoutUnit) (* <length-percentage> resolved >= 0 *)
  | BreadthMinContent                    (* min-content *)
  | BreadthMaxContent                    (* max-content *)
  | BreadthAuto.                         (* auto *)

(** W3C / Blink minmax(min, max) track sizing definition *)
Record MinMaxTrackSize : Type := mkMinMax {
  min_breadth : TrackBreadth;
  max_breadth : TrackBreadth
}.

(** Blink SizingConstraint enum in grid_track_sizing_algorithm.h *)
Inductive SizingConstraint : Type :=
  | kLayout     (avail_space : LayoutUnit) (* Definite available space >= 0 *)
  | kMinContent                            (* Sizing under min-content (0) *)
  | kMaxContent.                           (* Sizing under max-content (+inf) *)

(** Grid item intrinsic size contributions for a track (CSS Grid §11.5).
    Wait-free invariant: 0 <= min_contrib <= max_contrib. *)
Record ItemContributions : Type := mkContrib {
  min_contrib : LayoutUnit;
  max_contrib : LayoutUnit
}.

Definition wf_contrib (c : ItemContributions) : Prop :=
  0 <= min_contrib c /\ min_contrib c <= max_contrib c.

Definition wf_breadth (b : TrackBreadth) : Prop :=
  match b with
  | BreadthFixed len => 0 <= len
  | _ => True
  end.

Definition wf_minmax (mm : MinMaxTrackSize) : Prop :=
  wf_breadth (min_breadth mm) /\ wf_breadth (max_breadth mm).

(** ========================================================================= *)
(** ** 2. Mathematical Specification of minmax() Resolution                   *)
(** ========================================================================= *)

(** The core mathematical property required for W3C CSS Grid §11.4-§11.6:
    resolve_minmax(avail, min_t, max_t) = max(min_t, min(avail, max_t)). *)
Definition resolve_minmax (avail min_t max_t : LayoutUnit) : LayoutUnit :=
  Z.max min_t (Z.min avail max_t).

(** Blink's two-step clamped growth model in grid_track_sizing_algorithm.cc:
    Step 1 (EnsureGrowthLimitIsNotLessThanBaseSize):
      growth_limit = max(base_size, raw_limit)
    Step 2 (MaximizeTracks / DistributeExtraSpaceToSets):
      grow base_size toward growth_limit bounded by avail:
      min(max(base_size, avail), growth_limit) *)
Definition blink_ensure_growth_limit (base_size raw_limit : LayoutUnit) : LayoutUnit :=
  Z.max base_size raw_limit.

Definition blink_maximize_track (avail base_size raw_limit : LayoutUnit) : LayoutUnit :=
  let effective_limit := blink_ensure_growth_limit base_size raw_limit in
  Z.min (Z.max base_size avail) effective_limit.

(** ========================================================================= *)
(** ** 3. Resolving TrackBreadth under Constraints (CSS Grid §11.4 - §11.5)   *)
(** ========================================================================= *)

(** Resolve the minimum sizing function to a concrete base size [min_t].
    Per CSS Grid §11.5:
    - Fixed(d) -> d
    - min-content -> min_contrib
    - max-content -> max_contrib
    - auto -> under