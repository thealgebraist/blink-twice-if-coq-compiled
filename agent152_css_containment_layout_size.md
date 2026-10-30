Here is the architectural audit of Chromium Blink’s implementation of CSS Containment (`contain: layout size`) against the W3C CSS Containment Module Level 2 specification (§2 and §3), accompanied by its formalization in Rocq (Coq).

---

### 1. Representation of Containment Flags in `ComputedStyle` and `LayoutBox`

In Blink, the `contain` property is parsed as a bitflag enumeration (`EContain`), stored in `ComputedStyle`, and then queried through `LayoutObject` / `LayoutBox` predicates that filter the computed flags based on the box’s display geometry and element type.

#### `ComputedStyle` Layer (`computed_style_constants.h` / `computed_style.h`)
The raw CSS values are represented as a bitmask:
```cpp
enum class EContain : unsigned {
  kNone = 0,
  kStrict = kSize | kLayout | kPaint | kStyle,
  kContent = kLayout | kPaint | kStyle,
  kSize = 1 << 0,
  kLayout = 1 << 1,
  kStyle = 1 << 2,
  kPaint = 1 << 3,
  kInlineSize = 1 << 4,
};
```
In `ComputedStyle`, `Contain()` returns the explicit `contain` property value, while `EffectiveContainment()` returns the combined bitmask of explicit `contain`, `content-visibility` implied containment, and `container-type` implied containment.

#### `LayoutObject` / `LayoutBox` Layer (`layout_object.h` / `layout_box.h`)
Per CSS Containment 2 §3.1 and §3.2, neither `size` nor `layout` containment applies to non-atomic inlines, table-internal boxes (other than table cells for layout containment), or principal boxes that do not generate a box at all. Blink enforces this distinction in `LayoutObject`:

```cpp
// Checks if the element is eligible to apply containment at all
bool LayoutObject::IsEligibleForSizeContainment() const {
  return !IsInline() || IsAtomicInlineLevel(); // Plus table-internal exclusions
}

bool LayoutObject::ShouldApplyLayoutContainment(const ComputedStyle& style) const {
  return (style.EffectiveContainment() & kContainLayout) &&
         IsEligibleForLayoutContainment();
}

bool LayoutObject::ShouldApplySizeContainment(const ComputedStyle& style) const {
  return (style.EffectiveContainment() & kContainSize) &&
         IsEligibleForSizeContainment();
}
```
On `LayoutBox` (and `NGBlockNode` / `BlockNode` in LayoutNG), the hot-path helper methods `ShouldApplyLayoutContainment()` and `ShouldApplySizeContainment()` (historically aliased or wrapped by `HasLayoutContainment()` / `HasSizeContainment()`) govern layout algorithms.

---

### 2. Layout Isolation and Independent Formatting Context (IFC)

Per CSS Containment 2 §3.2 (Layout Containment):
> *"The layout-contained box establishes an independent formatting context."*

#### Blink LayoutNG Enforcement
1. **Formatting Context Creation**:
   In `ComputedStyle::CreatesNewFormattingContext()` and `LayoutBlock::CreatesNewFormattingContext()`, Blink explicitly checks `ShouldApplyLayoutContainment()` (as well as `ShouldApplyPaintContainment()`). When true, `BlockNode::CreatesNewFormattingContext()` returns `true`.
2. **Margin Collapsing Prevention**:
   In Blink’s `BlockLayoutAlgorithm` (`ng_block_layout_algorithm.cc`), child boxes that establish a new formatting context are processed via `HandleNewFormattingContext()`, whereas same-formatting-context flow children are processed via `HandleInFlow()`.
   * **Internal-to-External Isolation**: Because a layout-contained box uses `HandleNewFormattingContext()`, its internal `ConstraintSpace` is constructed with `is_new_formatting_context = true`. In `ConstraintSpaceBuilder`, this resets the `MarginStrut` passed into the subtree and prevents the child's internal first/last child margins from adjoining or collapsing with the box's own external top/bottom margins.
   * **External Sibling Interaction**: The layout-contained box itself still participates in its *parent's* formatting context as an atomic unit, so its own exterior `margin-top` and `margin-bottom` can collapse with adjacent external siblings. However, the boundary between its border-box/padding-box and its descendants is completely opaque to `MarginStrut` propagation.
   * **Floats and Clearance**: Because it establishes an IFC, the internal `ExclusionSpace` is initialized empty, preventing external floats from intruding into the layout-contained box and preventing internal floats from leaking out to affect subsequent external siblings' `clear` properties.

---

### 3. Core Invariants: Margin Collapse Suppression & Intrinsic Size Computation

#### Invariant A: External-Internal Margin Collapse Suppression (`contain: layout`)
Let $B$ be a `LayoutBox` with `ShouldApplyLayoutContainment() == true`.
* **Top Edge**: $\text{MarginTop}_{\text{collapsed}}(B) = \text{MarginTop}_{\text{specified}}(B)$ (with respect to $B$'s first inflow child $C_1$; $\text{MarginTop}(C_1)$ is trapped inside $B$'s content area).
* **Bottom Edge**: $\text{MarginBottom}_{\text{collapsed}}(B) = \text{MarginBottom}_{\text{specified}}(B)$ (with respect to $B$'s last inflow child $C_n$).
* **Self-Collapsing Prevention**: Even if $B$ has zero height, zero border, and zero padding, $B$'s own top and bottom margins collapse with *each other* outside only if $B$ is considered empty by external rules, **Wait**: Under CSS Sizing/Containment, because $B$ establishes an IFC, its own top and bottom margins *never* collapse through its interior with its children, nor do they collapse with each other through the box boundary if its formatting context rules forbid self-collapsing across IFC boundaries. Specifically, in CSS 2.1 §8.3.1, boxes that establish a new BFC never collapse their bottom margin with their last child's bottom margin, nor do their own top and bottom margins collapse *through* the box unless the box itself is non-BFC. (In fact, BFC roots still have an external margin box, and their own top/bottom margins only collapse through if they do not establish a BFC; in Blink, `HandleNewFormattingContext` resolves the BFC box's block-size first, even if `0px`, and appends its end margin to the external `MarginStrut` *after* resolving the BFC placement, preventing self-collapse through a BFC).

#### Invariant B: Intrinsic Size Computation as an Empty Box (`contain: size`)
Per CSS Containment 2 §3.1 (Size Containment):
> *"When calculating the size of the size-contained box (both intrinsic size and layout size)... it must be treated as having no contents."*

In Blink (`BlockNode::ComputeMinMaxSizes` and `BlockLayoutAlgorithm`):
1. **Intrinsic Inline Sizes (`MinMaxSizes`)**: When `ShouldApplySizeContainment()` is true, `BlockNode::ComputeMinMaxSizes()` bypasses the child layout algorithm's `ComputeMinMaxSizes` traversal entirely. Instead, it computes the `MinMaxSizes` solely from the box's own `border`, `padding`, and any scrollbar gutters (if `overflow: scroll`). Descendant intrinsic contributions are treated as `{0, 0}`.
2. **Intrinsic Block Size**: During `BlockLayoutAlgorithm::Layout()`, when `ShouldApplySizeContainment()` is true and `height` is `auto` (or intrinsic keywords like `min-content` / `max-content` / `fit-content`), the intrinsic block size (`intrinsic_block_size_`) is clamped/overridden to just the sum of `BorderScrollbarPadding().BlockSum()`, ignoring the block offset reached by laying out the children.

---

### 4. Concrete Rocq (Coq) Formalization

Below is the complete, self-contained Rocq file `BlinkCSSContainmentLayoutSizeSemantics.v` formalizing the bitflags, eligibility, IFC promotion, margin-collapsing isolation, and empty-subtree intrinsic sizing semantics, along with machine-checked proofs of the audit invariants.

```coq
(** * BlinkCSSContainmentLayoutSizeSemantics.v
    Formal Audit of Chromium Blink CSS Containment (contain: layout size)
    against W3C CSS Containment Module Level 2 (§2 & §3). *)

From Coq Require Import Bool.Bool.
From Coq Require Import Arith.PeanoNat.
From Coq Require Import Lists.List.
From Coq Require Import Lia.
Import ListNotations.

(** ** 1. Representation of Containment Flags (ComputedStyle & LayoutBox) *)

(** Represents the [EContain] bitflags in Blink's [ComputedStyle]. *)
Record ContainFlags : Type := mkContainFlags {
  cf_size   : bool;
  cf_layout : bool;
  cf_style  : bool;
  cf_paint  : bool
}.

Definition kContainNone : ContainFlags :=
  mkContainFlags false false false false.

Definition kContainLayoutSize : ContainFlags :=
  mkContainFlags true true false false.

Definition kContainStrict : ContainFlags :=
  mkContainFlags true true true true.

(** Display geometry classification for eligibility checks in [LayoutObject]. *)
Inductive BoxDisplayType : Type :=
  | DisplayBlock
  | DisplayAtomicInline
  | DisplayNonAtomicInline
  | DisplayTableInternalNotCell
  | DisplayTableCell
  | DisplayContents
  | DisplayNone.

(** Blink's [LayoutObject::IsEligibleForLayoutContainment] (§3.2). *)
Definition is_eligible_for_layout_containment (dt : BoxDisplayType) : bool :=
  match dt with
  | DisplayBlock => true
  | DisplayAtomicInline => true
  | DisplayTableCell => true
  | _ => false
  end.

(** Blink's [LayoutObject::IsEligibleForSizeContainment] (§3.1).
    Note: Size containment does not apply to table cells or internal table boxes. *)
Definition is_eligible_for_size_containment (dt : BoxDisplayType) : bool :=
  match dt with
  | DisplayBlock => true
  | DisplayAtomicInline => true
  | _ => false
  end.

(** Representation of a Blink [LayoutBox] and its subtree. *)
Inductive LayoutBox : Type :=
  | mkLayoutBox (style_contain : ContainFlags)
                (display       : BoxDisplayType)
                (border_pad_inline : nat)
                (border_pad_block  : nat)
                (margin_top        : nat)
                (margin_bottom     : nat)
                (explicit_block_sz : option nat)
                (intrinsic_inline_content : nat)
                (children          : list LayoutBox).

(** Accessors for [LayoutBox]. *)
Definition box_contain (b : LayoutBox) : ContainFlags :=
  match b with mkLayoutBox c _ _ _ _ _ _ _ _ => c end.

Definition box_display (b : LayoutBox) : BoxDisplayType :=
  match b with mkLayoutBox _ d _ _ _ _ _ _ _ => d end.

Definition box_bp_inline (b : LayoutBox) : nat :=
  match b with mkLayoutBox _ _ bpi _ _ _ _ _ _ => bpi end.

Definition box_bp_block (b : LayoutBox) : nat :=
  match b with mkLayoutBox _ _ _ bpb _ _ _ _ _ => bpb end.

Definition box_margin_top (b : LayoutBox) : nat :=
  match b with mkLayoutBox _ _ _ _ mt _ _ _ _ => mt end.

Definition box_margin_bottom (b : LayoutBox) : nat :=
  match b with mkLayoutBox _ _ _ _ _ mb _ _ _ => mb end.

Definition box_explicit_block_sz (b : LayoutBox) : option nat :=
  match b with mkLayoutBox _ _ _ _ _ _ ebs _ _ => ebs end.

Definition box_intrinsic_inline_content (b : LayoutBox) : nat :=
  match b with mkLayoutBox _ _ _ _ _ _ _ iic _ => iic end.

Definition box_children (b : LayoutBox) : list LayoutBox :=
  match b with mkLayoutBox _ _ _ _ _ _ _ _ ch => ch end.

(** Blink's [LayoutObject::ShouldApplyLayoutContainment] / [HasLayoutContainment]. *)
Definition has_layout_containment (b : LayoutBox) : bool :=
  cf_layout (box_contain b) && is_eligible_for_layout_containment (box_display b).

(** Blink's [LayoutObject::ShouldApplySizeContainment] / [HasSizeContainment]. *)
Definition has_size_containment (b : LayoutBox) : bool :=
  cf_size (box_contain b) && is_eligible_for_size_containment (box_display b).


(** ** 2. Layout Isolation & Independent Formatting Context (IFC) *)

(** Blink's [LayoutBlock::CreatesNewFormattingContext].
    Atomic inlines and table cells already establish an IFC; layout or paint
    containment forces any eligible box to establish a new IFC. *)
Definition establishes_ifc (b : LayoutBox) : bool :=
  has_layout_containment b ||
  (cf_paint (box_contain b) && is_eligible_for_layout_containment (box_display b)) ||
  match box_display b with
  | DisplayAtomicInline | DisplayTableCell => true
  | _ => false
  end.

(** Margin collapsing model (non-negative margins for simplicity, modeled via [Nat.max]).
    In Blink LayoutNG, a [MarginStrut] accumulates adjoining margins across boundaries
    that do NOT establish an IFC and have zero border/padding. *)

(** Extracts the collapsible top margin of a box's first inflow child if no IFC
    and zero border/padding; otherwise 0. *)
Fixpoint effective_top_margin (b : LayoutBox) : nat :=
  let own_mt := box_margin_top b in
  if establishes_ifc b || (0 <? box_bp_block b) then
    own_mt
  else
    match box_children b with
    | [] => own_mt
    | c1 :: _ => Nat.max own_mt (effective_top_margin c1)
    end.

(** Extracts the collapsible bottom margin of a box's last inflow child if no IFC
    and zero border/padding; otherwise 0. *)
Fixpoint effective_bottom_margin (b : LayoutBox) : nat :=
  let own_mb := box_margin_bottom b in
  if establishes_ifc b || (0 <? box_bp_block b) then
    own_mb
  else
    match rev (box_children b) with
    | [] => own_mb
    | cn :: _ => Nat.max own_mb (effective_bottom_margin cn)
    end.

(** External sibling margin collapse between two adjacent boxes [b1] and [b2]. *)
Definition collapsed_sibling_margin (b1 b2 : LayoutBox) : nat :=
  Nat.max (effective_bottom_margin b1) (effective_top_margin b2).


(** ** 3. Size Containment & Intrinsic Sizing Semantics *)

(** Helper: maximum inline size across a list of child contributions. *)
Fixpoint max_list (l : list nat) : nat :=
  match l with
  | [] => 