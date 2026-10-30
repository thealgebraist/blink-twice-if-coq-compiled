### Audit Report: Agent 202 — Chromium Blink Logical to Physical Offset Mapping vs. CSS Writing Modes 3 §4

**Target:** `third_party/blink/renderer/core/layout/geometry/writing_mode_converter.h`  
**Specification:** CSS Writing Modes Level 3 §4 (Inline-level Alignment) & §6 (Abstract Box Terminology)

---

### 1. Mapping Semantics

In Chromium Blink’s LayoutNG architecture, layout algorithms operate purely in flow-relative **logical coordinates** (`LogicalOffset`: `inline_offset`, `block_offset`). Once layout is finalized, `WritingModeConverter` translates these into **physical coordinates** (`PhysicalOffset`: `left` ($x$), `top` ($y$)) relative to the containing block's outer physical size (`outer_size`) and the child box's physical size (`inner_size`).

Assuming a standard `ltr` (left-to-right) inline base direction for isolating the `writing-mode` axis transformations, the conversion equations implemented in Blink are:

1. **`horizontal-tb` (Horizontal Top-to-Bottom):**
   * Inline flow is horizontal (left-to-right); block flow is vertical (top-to-bottom).
   * $x = \text{inline\_offset}$
   * $y = \text{block\_offset}$

2. **`vertical-lr` (Vertical Left-to-Right):**
   * Inline flow is vertical (top-to-bottom); block flow is horizontal (left-to-right).
   * $x = \text{block\_offset}$
   * $y = \text{inline\_offset}$

3. **`vertical-rl` (Vertical Right-to-Left):**
   * Inline flow is vertical (top-to-bottom); block flow is horizontal (right-to-left).
   * Because physical $x$ is measured from the *left* edge of the containing block to the *left* edge of the child box, while logical `block_offset` is measured from the *right* edge of the containing block to the *right* edge of the child box, the transformation must invert the coordinate space by subtracting both the offset and the child box's physical width (`box_w`) from the container's physical width (`outer_w`):
   * $x = \text{outer\_w} - (\text{block\_offset} + \text{box\_w})$
   * $y = \text{inline\_offset}$

---

### 2. Core Invariants

1. **Bijectivity (Invertibility):**
   For any fixed writing mode, outer container size, and inner box size, the functions `ToPhysical` and `ToLogical` form an exact bijection. Applying `ToLogical` to the output of `ToPhysical` yields the exact original `LogicalOffset` without loss of precision (over exact arithmetic `Z`), and vice versa. This is critical in Blink for hit-testing, layout invalidation, and incremental layout passes where physical fragment offsets are converted back into logical space.

2. **Bounding Preservation (In-Bounds Invariant):**
   If a child box is logically contained within its parent container—meaning its logical offsets are non-negative and its logical extent (offset + size) does not exceed the container's logical size—then the resulting physical box is guaranteed to be physically contained within the parent container's physical bounds ($0 \le x$, $x + \text{box\_w} \le \text{outer\_w}$, $0 \le y$, $y + \text{box\_h} \le \text{outer\_h}$).

---

### 3. Concrete Rocq/Coq Verification (`BlinkLogicalOffsetMappingSemantics.v`)

The following file is a complete, self-contained Rocq/Coq formalization of the semantics and proofs of the invariants above.

```coq
(** * BlinkLogicalOffsetMappingSemantics.v
    Formal Audit of Chromium Blink WritingModeConverter against CSS Writing Modes 3 §4.
    Agent 202. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
Open Scope Z_scope.

(** ** 1. Data Types *)

Inductive WritingMode : Type :=
  | HorizontalTB
  | VerticalLR
  | VerticalRL.

Record LogicalOffset : Type := mkLogicalOffset {
  inline_offset : Z;
  block_offset : Z
}.

Record PhysicalOffset : Type := mkPhysicalOffset {
  left : Z; (* x *)
  top  : Z  (* y *)
}.

Record PhysicalSize : Type := mkPhysicalSize {
  width  : Z;
  height : Z
}.

Record LogicalSize : Type := mkLogicalSize {
  inline_size : Z;
  block_size  : Z
}.

(** ** 2. Size and Offset Mapping Definitions *)

(** Maps physical dimensions to logical dimensions based on writing mode. *)
Definition to_logical_size (wm : WritingMode) (ps : PhysicalSize) : LogicalSize :=
  match wm with
  | HorizontalTB => mkLogicalSize (width ps) (height ps)
  | VerticalLR   => mkLogicalSize (height ps) (width ps)
  | VerticalRL   => mkLogicalSize (height ps) (width ps)
  end.

(** Blink's WritingModeConverter::ToPhysical(LogicalOffset, PhysicalSize) *)
Definition to_physical_offset
  (wm : WritingMode)
  (outer_size : PhysicalSize)
  (inner_size : PhysicalSize)
  (l : LogicalOffset) : PhysicalOffset :=
  match wm with
  | HorizontalTB =>
      mkPhysicalOffset (inline_offset l) (block_offset l)
  | VerticalLR =>
      mkPhysicalOffset (block_offset l) (inline_offset l)
  | VerticalRL =>
      mkPhysicalOffset (width outer_size - (block_offset l + width inner_size))
                       (inline_offset l)
  end.

(** Blink's WritingModeConverter::ToLogical(PhysicalOffset, PhysicalSize) *)
Definition to_logical_offset
  (wm : WritingMode)
  (outer_size : PhysicalSize)
  (inner_size : PhysicalSize)
  (p : PhysicalOffset) : LogicalOffset :=
  match wm with
  | HorizontalTB =>
      mkLogicalOffset (left p) (top p)
  | VerticalLR =>
      mkLogicalOffset (top p) (left p)
  | VerticalRL =>
      mkLogicalOffset (top p)
                      (width outer_size - (left p + width inner_size))
  end.

(** ** 3. Invariant 1: Bijective Mapping Proofs *)

Theorem to_logical_to_physical_id :
  forall (wm : WritingMode) (outer inner : PhysicalSize) (l : LogicalOffset),
    to_logical_offset wm outer inner (to_physical_offset wm outer inner l) = l.
Proof.
  intros wm outer inner [i b].
  destruct wm; simpl; f_equal; lia.
Qed.

Theorem to_physical_to_logical_id :
  forall (wm : WritingMode) (outer inner : PhysicalSize) (p : PhysicalOffset),
    to_physical_offset wm outer inner (to_logical_offset wm outer inner p) = p.
Proof.
  intros wm outer inner [x y].
  destruct wm; simpl; f_equal; lia.
Qed.

(** Bijectivity implies injectivity of the physical mapping. *)
Corollary to_physical_offset_injective :
  forall (wm : WritingMode) (outer inner : PhysicalSize) (l1 l2 : LogicalOffset),
    to_physical_offset wm outer inner l1 = to_physical_offset wm outer inner l2 ->
    l1 = l2.
Proof.
  intros wm outer inner l1 l2 H.
   rewrite <- (to_logical_to_physical_id wm outer inner l1).
  rewrite <- (to_logical_to_physical_id wm outer inner l2).
   rewrite H. reflexivity.
Qed.

(** ** 4. Invariant 2: Bounds Preservation Proofs *)

(** A box is logically in bounds if its offset is non-negative and its
    extent (offset + inner_size) does not exceed the outer container size. *)
Definition logically_in_bounds
  (wm : WritingMode)
  (outer_p inner_p : PhysicalSize)
  (l : LogicalOffset) : Prop :=
  let outer_l := to_logical_size wm outer_p in
  let inner_l := to_logical_size wm inner_p in
  0 <= inline_offset l /\
  inline_offset l + inline_size inner_l <= inline_size outer_l /\
  0 <= block_offset l /\
  block_offset l + block_size inner_l <= block_size outer_l.

(** A box is physically in bounds if its x/y coordinates are non-negative and
    its physical extent (x + w, y + h) does not exceed the outer physical size. *)
Definition physically_in_bounds
  (outer_p inner_p : PhysicalSize)
  (p : PhysicalOffset) : Prop :=
  0 <= left p /\
  left p + width inner_p <= width outer_p /\
  0 <= top p /\
  top p + height inner_p <= height outer_p.

(** Main Bounds Preservation Theorem:
    Logical containment is strictly equivalent to physical containment across all writing modes. *)
Theorem bounds_preservation :
  forall (wm : WritingMode) (outer inner : PhysicalSize) (l : LogicalOffset),
    logically_in_bounds wm outer inner l <->
    physically_in_bounds outer inner (to_physical_offset wm outer inner l).
Proof.
  intros wm [ow oh] [iw ih] [i b].
  unfold logically_in_bounds, physically_in_bounds.
  destruct wm; simpl; split; intros [H1 [H2 [H3 H4]]]; repeat split; lia.
Qed.
```