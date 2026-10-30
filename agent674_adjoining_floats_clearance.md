# Formal Verification Report: Clearance Mathematics Over Adjoining Margins with Floats in Chromium Blink

**Agent Identifier:** Formal Verification Agent 674  
**Specialization:** W3C/WHATWG Layout Rules (Block, Inline, Flexbox) in Chromium Blink  
**Target Source:** `third_party/blink/renderer/core/layout/floats_utils.cc` (and Block Layout Integration in `block_layout_algorithm.cc` / `exclusion_space.cc`)  
**Specification:** CSS 2.1 §9.5.2 — Controlling flow next to floats: the `'clear'` property  
**Formal Theory Target:** `BlinkAdjoiningFloatsClearanceSemantics.v`  

---

## 1. Normative W3C Specification Requirements

In CSS 2.1 §9.5.2 (*Controlling flow next to floats: the `'clear'` property*), clearance is introduced as extra space added above the `margin-top` of an element to push its border edge vertically past the bottom outer edge of relevant floating boxes (`left`, `right`, or `both`).

### 1.1 Exact Normative Rules (CSS 2.1 §9.5.2 & §8.3.1)

1. **Applicability & Values**:
   - `clear: none`: No constraint on the box's position with respect to floats.
   - `clear: left`: Requires the top border edge of the box to be below the bottom outer edge of any earlier left-floating boxes resulted from elements earlier in the source document.
   - `clear: right`: Requires the top border edge to be below the bottom outer edge of any earlier right-floating boxes.
   - `clear: both`: Requires the top border edge to be below the bottom outer edge of both earlier left- and right-floating boxes.

2. **Hypothetical Position & Margin Collapsing Prevention**:
   To determine whether clearance is needed, the user agent first computes the *hypothetical position* of the element's top border edge. This is the position the top border edge would have had if the element's `clear` property had been `none`.
   - Under CSS 2.1 §8.3.1 (*Collapsing margins*), when an element's top margin is adjoining to previous margins (or parent margins), its hypothetical top border edge is evaluated with all adjoining margins collapsed.
   - If the hypothetical top border edge is *not* past the relevant floats, then **clearance is introduced**, and **margins do not collapse** across the clearance boundary.

3. **Clearance Computation Formula**:
   Once clearance is introduced on a block-level element, its top margin no longer collapses with preceding adjoining margins. Let:
   - $B_{\text{hyp}}$ be the y-coordinate (block-offset) where the block's top margin edge sits after resolving preceding collapsed margins (the uncollapsed baseline, denoted `hypothetical_top` prior to applying the block's own `margin_top`).
   - $M_{\text{top}}$ be the element's own top margin.
   - $F_{\text{bottom}}$ be the maximum bottom outer edge (`block-end` offset) among all relevant floats (`left`, `right`, or `both`) within the same Block Formatting Context (BFC).

   The element's top border edge without clearance is located at:
   $$Y_{\text{border\_unadjusted}} = B_{\text{hyp}} + M_{\text{top}}$$

   To place the element's top border edge exactly at $F_{\text{bottom}}$ (Option 1 of CSS 2.1 §9.5.2, which matches Blink's LayoutNG canonical non-collapsing behavior once isolated at a BFC offset), the required clearance $C$ is:
   $$C = \max\left(0, F_{\text{bottom}} - (B_{\text{hyp}} + M_{\text{top}})\right)$$

   The resulting resolved top border edge offset is:
   $$Y_{\text{border\_final}} = B_{\text{hyp}} + M_{\text{top}} + C = \max\left(B_{\text{hyp}} + M_{\text{top}}, F_{\text{bottom}}\right)$$

---

## 2. Chromium Blink Implementation Details & Invariants

In Chromium Blink's modern LayoutNG architecture (`third_party/blink/renderer/core/layout/`), float tracking, adjoining object resolution, and clearance math are distributed across `floats_utils.cc`, `exclusion_space.h/.cc`, and `block_layout_algorithm.cc`.

### 2.1 Architecture in `floats_utils.cc` and `ExclusionSpace`

1. **Float Ceiling / Clearance Offset Query (`ExclusionSpace::ClearanceOffset`)**:
   - The `ExclusionSpace` tracks two monotonic offsets in BFC block-coordinates: `left_clear_offset_` and `right_clear_offset_`.
   - When querying `ExclusionSpace::ClearanceOffset(EClear clear_type)`:
     - `EClear::kNone` returns `LayoutUnit::Min()` (modeled formally as $0$ or $-\infty$ relative to the non-negative float horizon).
     - `EClear::kLeft` returns `left_clear_offset_`.
     - `EClear::kRight` returns `right_clear_offset_`.
     - `EClear::kBoth` returns `std::max(left_clear_offset_, right_clear_offset_)`.

2. **Adjoining Floats and Unpositioned Float Resolution (`floats_utils.cc`)**:
   - In `floats_utils.cc`, `PositionFloat(UnpositionedFloat*, ExclusionSpace*)` computes the exact `BfcOffset` and outer margins of a float before inserting it into the `ExclusionSpace`.
   - When floats are *adjoining* to an unresolved BFC block-offset (i.e., preceded only by collapsible margins), Blink's `BlockLayoutAlgorithm` tracks `AdjoiningObjectTypes`. If an element has `clear != EClear::kNone` or is pushed by floats, the BFC block-offset is forced to resolve, positioning all pending adjoining floats via `floats_utils.cc` *before* evaluating the clearing element's final BFC offset.

3. **Clearance Adjustments (`AdjustToClearance`)**:
   - In `block_layout_algorithm.cc` / `layout_Opportunity_utils`, once the BFC block-offset of the element's margin-box or border-box is calculated as `bfc_block_offset = hypothetical_top + margin_top`:
   ```cpp
   LayoutUnit clearance_offset = exclusion_space.ClearanceOffset(child_style.Clear(style));
   if (bfc_block_offset < clearance_offset) {
     clearance = clearance_offset - bfc_block_offset;
     bfc_block_offset = clearance_offset;
   }
   ```
   - This directly implements:
     $$\text{clearance} = \max\left(0, \text{float\_bottom} - (\text{hypothetical\_top} + \text{margin\_top})\right)$$

### 2.2 Core Blink Layout Invariants

- **Invariant 1 (Non-Negativity of Clearance)**: Clearance applied to a block formatting context offset is never negative ($C \ge 0$). `clear` can only push a box downwards (in the block-progression direction), never pull it upwards.
- **Invariant 2 (Float Dominance)**: After applying clearance, if `clear` is active (`left`, `right`, or `both`), the final top border edge of the box is guaranteed to be $\ge$ the bottom outer edge of all relevant floats in the `ExclusionSpace`.
- **Invariant 3 (Monotonicity under `EClear::kBoth`)**: The clearance computed for `EClear::kBoth` is equal to the maximum of the clearances computed independently for `EClear::kLeft` and `EClear::kRight`, and dominates both.
- **Invariant 4 (Idempotence)**: Once a block's position has been adjusted by its required clearance, re-evaluating clearance at the new adjusted position yields exactly $0$.

---

## 3. Formal Specification & Proofs in Rocq/Coq

Below is the complete, self-contained, and admitted-free formalization of `BlinkAdjoiningFloatsClearanceSemantics.v`. It models CSS 2.1 §9.5.2 clearance over adjoining margins and floats in $\mathbb{Z}$ (`ZArith`), corresponding to Blink's fixed-point `LayoutUnit` arithmetic.

```coq
(** * BlinkAdjoiningFloatsClearanceSemantics.v
    Formal verification of W3C CSS 2.1 §9.5.2 clearance mathematics over
    adjoining margins and floats in Chromium Blink (floats_utils.cc). *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.

Import ListNotations.
Open Scope Z_scope.

(* ========================================================================== *)
(* 1. DATA TYPES & SYNTAX                                                     *)
(* ========================================================================== *)

(** Represents CSS 'float' values relevant to exclusion spaces. *)
Inductive FloatSide : Type :=
  | FloatLeft
  | FloatRight.

(** Scheme for decidable equality on FloatSide. *)
Definition float_side_eqb (s1 s2 : FloatSide) : bool :=
  match s1, s2 with
  | FloatLeft, FloatLeft => true
  | FloatRight, FloatRight => true
  | _, _ => false
  end.

(** Represents CSS 'clear' property values (EClear in Blink). *)
Inductive ClearType : Type :=
  | ClearNone
  | ClearLeft
  | ClearRight
  | ClearBoth.

(** A positioned float in the BFC ExclusionSpace.
    - [float_side]: left or right float
    - [float_top]: block-start outer edge in BFC coordinates
    - [float_height]: outer block-size (margin-box height, typically >= 0) *)
Record FloatBox : Type := mkFloatBox {
  float_side   : FloatSide;
  float_top    : Z;
  float_height : Z
}.

(** The bottom outer edge (block-end) of a float box. *)
Definition float_bottom_edge (f : FloatBox) : Z :=
  float_top f + float_height f.

(** Represents the adjoining margin state and element box parameters prior
    to clearance resolution.
    - [hypothetical_top]: BFC block-offset before the element's top margin
    - [margin_top]: the element's own top margin (can be positive, zero, or negative)
    - [clear_prop]: the element's resolved 'clear' property *)
Record ClearingBox : Type := mkClearingBox {
  hypothetical_top : Z;
  margin_top       : Z;
  clear_prop       : ClearType
}.

(* ========================================================================== *)
(* 2. EXCLUSION SPACE & FLOAT HORIZON SEMANTICS                               *)
(* ========================================================================== *)

(** Checks if a float is relevant to a given ClearType. *)
Definition is_relevant_float (c : ClearType) (s : FloatSide) : bool :=
  match c with
  | ClearNone  => false
  | ClearLeft  => float_side_eqb s FloatLeft
  | ClearRight => float_side_eqb s FloatRight
  | ClearBoth  => true
  end.

(** Computes the maximum bottom edge among relevant floats in the exclusion space,
    given a baseline floor (0 in standard non-negative BFC coordinates, or
    hypothetical_top + margin_top when no floats constrain the box).
    Here we model the raw float bottom horizon over a list of floats with a
    default sentinel [default_floor]. *)
Fixpoint max_relevant_float_bottom (c : ClearType) (floats : list FloatBox) (default_floor : Z) : Z :=
  match floats with
  | [] => default_floor
  | f :: rest =>
      let rest_max := max_relevant_float_bottom c rest default_floor in
      if is_relevant_float c (float_side f)
      then Z.max (float_bottom_edge f) rest_max
      else rest_max
  end.

(** Direct abstraction of Blink's ExclusionSpace state:
    [left_float_bottom] and [right_float_bottom] represent the accumulated
    maximum bottom outer edges of left and right floats respectively. *)
Record ExclusionSpaceState : Type := mkExclusionSpaceState {
  left_float_bottom  : Z;
  right_float_bottom : Z
}.

(** Computes the effective float_bottom (ClearanceOffset in Blink) for a ClearType
    given an ExclusionSpaceState and the unadjusted border-top offset as fallback
    for ClearNone. *)
Definition resolve_float_bottom (es : ExclusionSpaceState) (c : ClearType) (unadjusted_top : Z) : Z :=
  match c with
  | ClearNone  => unadjusted_top
  | ClearLeft  => left_float_bottom es
  | ClearRight => right_float_bottom es
  | ClearBoth  => Z.max (left_float_bottom es) (right_float_bottom es)
  end.

(* ========================================================================== *)
(* 3. CORE CLEARANCE MATHEMATICS                                              *)
(* ========================================================================== *)

(** Core mathematical property from specification:
    clearance = max(0, float_bottom - (hypothetical_top + margin_top)) *)
Definition compute_clearance (hyp_top marg_top flt_bottom : Z) : Z :=
  Z.max 0 (flt_bottom - (hyp_top + marg_top)).

(** Unadjusted top border edge (when clear: none or before clearance). *)
Definition unadjusted_border_top (hyp_top marg_top : Z) : Z :=
  hyp_top + marg_top.

(** Final top border edge after applying clearance. *)
Definition final_border_top (hyp_top marg_top flt_bottom : Z) : Z :=
  unadjusted_border_top hyp_top marg_top + compute_clearance hyp_top marg_top flt_bottom.

(** High-level clearance calculation for a ClearingBox in an ExclusionSpaceState. *)
Definition compute_box_clearance (es : ExclusionSpaceState) (box : ClearingBox) : Z :=
  let unadj := unadjusted_border_top (hypothetical_top box) (margin_top box) in
  let flt_bot := resolve_float_bottom es (clear_prop box) unadj in
  compute_clearance (hypothetical_top box) (margin_top box) flt_bot.

(** High-level final border-top position for a ClearingBox in an ExclusionSpaceState. *)
Definition resolve_box_border_top (es : ExclusionSpaceState) (box : ClearingBox) : Z :=
  let unadj := unadjusted_border_top (hypothetical_top box) (margin_top box) in
  unadj + compute_box_clearance es box.

(* ========================================================================== *)
(* 4. CONCRETE THEOREMS & PROOFS                                              *)
(* ========================================================================== *)

(** Theorem 1: Non-negativity of clearance.
    Clearance can never be negative, regardless of margin signs or float positions. *)
Theorem clearance_non_negative :
  forall (hyp_top marg_top flt_bottom : Z),
    0 <= compute_clearance hyp_top marg_top flt_bottom.
Proof.
  