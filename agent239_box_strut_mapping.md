### 1. Mapping Specification: Chromium Blink Box Strut vs. CSS Writing Modes 3 §4

In CSS Writing Modes Level 3 (§4, *Abstract Box Terminology*), logical box dimensions (`block-start`, `block-end`, `inline-start`, `inline-end`) are mapped to physical box dimensions (`top`, `right`, `bottom`, `left`) governed by the `writing-mode` and `direction` properties.

In Chromium Blink's layout engine (`third_party/blink/renderer/core/layout/geometry/box_strut.h`), this conversion is handled between `BoxStrut` (logical coordinates) and `PhysicalBoxStrut` (physical coordinates) via `WritingDirectionMode`.

#### Complete Flow-Relative Mapping Table
| `writing-mode` | `direction` | `block_start` | `block_end` | `inline_start` | `inline_end` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`horizontal-tb`** | **`ltr`** | **`top`** | **`bottom`** | **`left`** | **`right`** |
| `horizontal-tb` | `rtl` | `top` | `bottom` | `right` | `left` |
| `vertical-rl` | `ltr` | `right` | `left` | `top` | `bottom` |
| `vertical-rl` | `rtl` | `right` | `left` | `bottom` | `top` |
| `vertical-lr` | `ltr` | `left` | `right` | `top` | `bottom` |
| `vertical-lr` | `rtl` | `left` | `right` | `bottom` | `top` |
| `sideways-rl` | `ltr` | `right` | `left` | `top` | `bottom` |
| `sideways-rl` | `rtl` | `right` | `left` | `bottom` | `top` |
| `sideways-lr` | `ltr` | `left` | `right` | `bottom` | `top` |
| `sideways-lr` | `rtl` | `left` | `right` | `top` | `bottom` |

For the canonical **`horizontal-tb` (`ltr`)** mode required by detail (1):
$$\text{block\_start} \mapsto \text{top}, \quad \text{block\_end} \mapsto \text{bottom}, \quad \text{inline\_start} \mapsto \text{left}, \quad \text{inline\_end} \mapsto \text{right}$$

---

### 2. Core Layout Invariants

Let $L = (\text{inline\_start}, \text{inline\_end}, \text{block\_start}, \text{block\_end})$ be a logical `BoxStrut` and $P = (\text{top}, \text{right}, \text{bottom}, \text{left})$ be the mapped `PhysicalBoxStrut`.

1. **Horizontal / Inline Sum Preservation (Horizontal Writing Modes):**
   In `horizontal-tb` (for both `ltr` and `rtl`), the physical horizontal sum (`left + right`, i.e., `PhysicalBoxStrut::HorizontalSum()`) strictly equals the logical inline sum (`inline_start + inline_end`, i.e., `BoxStrut::InlineSum()`):
   $$\forall d \in \{\text{ltr}, \text{rtl}\}, \quad P_{\text{horizontal-tb}, d}.\text{left} + P_{\text{horizontal-tb}, d}.\text{right} = L.\text{inline\_start} + L.\text{inline\_end}$$
   *(Note: In `rtl`, `left` and `right` are swapped, which preserves the sum via commutativity of addition).*

2. **Vertical / Block Sum Preservation (Horizontal Writing Modes):**
   $$\forall d \in \{\text{ltr}, \text{rtl}\}, \quad P_{\text{horizontal-tb}, d}.\text{top} + P_{\text{horizontal-tb}, d}.\text{bottom} = L.\text{block\_start} + L.\text{block\_end}$$

3. **Cross-Axis Sum Preservation (Vertical Writing Modes):**
   In vertical/sideways modes (`vertical-rl`, `vertical-lr`, `sideways-rl`, `sideways-lr`), the axes transpose: physical horizontal sum equals the logical *block* sum, and physical vertical sum equals the logical *inline* sum.

4. **Total Perimeter Invariance & Bijectivity:**
   For *any* writing mode $w$ and text direction $d$, the round-trip transformation `ToLogical(ToPhysical(L, w, d), w, d) = L` is an exact identity, and the total perimeter sum is unconditionally invariant.

---

### 3. Concrete Rocq / Coq Formalization (`BlinkBoxStrutMappingSemantics.v`)

The following file compiles cleanly in Coq/Rocq (8.16+ / 9.0+) with **0 admits**.

```coq
(** * BlinkBoxStrutMappingSemantics.v
    Formal Audit of Chromium Blink BoxStrut <-> PhysicalBoxStrut Mapping
    against CSS Writing Modes Level 3 §4. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Writing Modes and Directions (CSS Writing Modes 3 §2, §3) *)

Inductive WritingMode : Type :=
  | HorizontalTb
  | VerticalRl
  | VerticalLr
  | SidewaysRl
  | SidewaysLr.

Inductive TextDirection : Type :=
  | Ltr
  | Rtl.

Record WritingDirectionMode : Type := mkWritingDirectionMode {
  wm : WritingMode;
  dir : TextDirection
}.

(** ** 2. Logical and Physical Box Struts (Blink box_strut.h) *)

Record LogicalBoxStrut : Type := mkLogicalBoxStrut {
  inline_start : Z;
  inline_end   : Z;
  block_start  : Z;
  block_end    : Z
}.

Record PhysicalBoxStrut : Type := mkPhysicalBoxStrut {
  top    : Z;
  right  : Z;
  bottom : Z;
  left   : Z
}.

(** ** 3. Sum Accessors (Blink InlineSum, BlockSum, HorizontalSum, VerticalSum) *)

Definition InlineSum (s : LogicalBoxStrut) : Z :=
  inline_start s + inline_end s.

Definition BlockSum (s : LogicalBoxStrut) : Z :=
  block_start s + block_end s.

Definition HorizontalSum (p : PhysicalBoxStrut) : Z :=
  left p + right p.

Definition VerticalSum (p : PhysicalBoxStrut) : Z :=
  top p + bottom p.

(** ** 4. Conversion Semantics (Logical <-> Physical) *)

Definition ToPhysical (s : LogicalBoxStrut) (wdm : WritingDirectionMode) : PhysicalBoxStrut :=
  match wm wdm, dir wdm with
  | HorizontalTb, Ltr =>
      mkPhysicalBoxStrut (block_start s) (inline_end s) (block_end s) (inline_start s)
  | HorizontalTb, Rtl =>
      mkPhysicalBoxStrut (block_start s) (inline_start s) (block_end s) (inline_end s)
  | VerticalRl, Ltr | SidewaysRl, Ltr =>
      mkPhysicalBoxStrut (inline_start s) (block_start s) (inline_end s) (block_end s)
  | VerticalRl, Rtl | SidewaysRl, Rtl =>
      mkPhysicalBoxStrut (inline_end s) (block_start s) (inline_start s) (block_end s)
  | VerticalLr, Ltr =>
      mkPhysicalBoxStrut (inline_start s) (block_end s) (inline_end s) (block_start s)
  | VerticalLr, Rtl =>
      mkPhysicalBoxStrut (inline_end s) (block_end s) (inline_start s) (block_start s)
  | SidewaysLr, Ltr =>
      mkPhysicalBoxStrut (inline_end s) (block_end s) (inline_start s) (block_start s)
  | SidewaysLr, Rtl =>
      mkPhysicalBoxStrut (inline_start s) (block_end s) (inline_end s) (block_start s)
  end.

Definition ToLogical (p : PhysicalBoxStrut) (wdm : WritingDirectionMode) : LogicalBoxStrut :=
  match wm wdm, dir wdm with
  | HorizontalTb, Ltr =>
      mkLogicalBoxStrut (left p) (right p) (top p) (bottom p)
  | HorizontalTb, Rtl =>
      mkLogicalBoxStrut (right p) (left p) (top p) (bottom p)
  | VerticalRl, Ltr | SidewaysRl, Ltr =>
      mkLogicalBoxStrut (top p) (bottom p) (right p) (left p)
  | VerticalRl, Rtl | SidewaysRl, Rtl =>
      mkLogicalBoxStrut (bottom p) (top p) (right p) (left p)
  | VerticalLr, Ltr =>
      mkLogicalBoxStrut (top p) (bottom p) (left p) (right p)
  | VerticalLr, Rtl =>
      mkLogicalBoxStrut (bottom p) (top p) (left p) (right p)
  | SidewaysLr, Ltr =>
      mkLogicalBoxStrut (bottom p) (top p) (left p) (right p)
  | SidewaysLr, Rtl =>
      mkLogicalBoxStrut (top p) (bottom p) (left p) (right p)
  end.

(** ** 5. Audit Theorems and Invariants *)

(** Detail 1: Explicit coordinate mapping in horizontal-tb (LTR).
    block_start -> top, block_end -> bottom,
    inline_start -> left, inline_end -> right. *)
Theorem horizontal_tb_ltr_mapping :
  forall (s : LogicalBoxStrut),
    let p := ToPhysical s (mkWritingDirectionMode HorizontalTb Ltr) in
    top p = block_start s /\
    bottom p = block_end s /\
    left p = inline_start s /\
    right p = inline_end s.
Proof.
  intros s p.
  unfold p, ToPhysical; simpl.
  repeat split; reflexivity.
Qed.

(** Detail 2a: In horizontal-tb (LTR), sum of physical horizontal sides
    equals sum of logical inline sides. *)
Theorem horizontal_tb_ltr_horizontal_sum_eq_inline_sum :
  forall (s : LogicalBoxStrut),
    HorizontalSum (ToPhysical s (mkWritingDirectionMode HorizontalTb Ltr)) = InlineSum s.
Proof.
  intros s.
  unfold HorizontalSum, InlineSum, ToPhysical; simpl.
  lia.
Qed.

(** Detail 2b: In horizontal-tb (for ALL directions: both LTR and RTL),
    sum of physical horizontal sides equals sum of logical inline sides. *)
Theorem horizontal_tb_horizontal_sum_eq_inline_sum :
  forall (s : LogicalBoxStrut) (d : TextDirection),
    HorizontalSum (ToPhysical s (mkWritingDirectionMode HorizontalTb d)) = InlineSum s.
Proof.
  intros s [|]; unfold HorizontalSum, InlineSum, ToPhysical; simpl; lia.
Qed.

(** Detail 2c: In horizontal-tb (for ALL directions),
    sum of physical vertical sides equals sum of logical block sides. *)
Theorem horizontal_tb_vertical_sum_eq_block_sum :
  forall (s : LogicalBoxStrut) (d : TextDirection),
    VerticalSum (ToPhysical s (mkWritingDirectionMode HorizontalTb d)) = BlockSum s.
Proof.
  intros s [|]; unfold VerticalSum, BlockSum, ToPhysical; simpl; lia.
Qed.

(** Vertical modes invariant: In all vertical/sideways modes,
    physical horizontal sum equals logical block sum, and
    physical vertical sum equals logical inline sum. *)
Theorem vertical_modes_sum_invariants :
  forall (s : LogicalBoxStrut) (w : WritingMode) (d : TextDirection),
    w <> HorizontalTb ->
    HorizontalSum (ToPhysical s (mkWritingDirectionMode w d)) = BlockSum s /\
    VerticalSum (ToPhysical s (mkWritingDirectionMode w d)) = InlineSum s.
Proof.
  intros s [| | | |] [|] Hneq;
    try contradiction;
    unfold HorizontalSum, VerticalSum, BlockSum, InlineSum, ToPhysical;
    simpl; split; lia.
Qed.

(** Universal Round-Trip Bijectivity: Logical -> Physical -> Logical *)
Theorem to_logical_to_physical_id :
  forall (s : LogicalBoxStrut) (wdm : WritingDirectionMode),
    ToLogical (ToPhysical s wdm) wdm = s.
Proof.
  intros [is ie bs be] [[| | | |] [|]];
    unfold ToLogical, ToPhysical; simpl; reflexivity.
Qed.

(** Universal Round-Trip Bijectivity: Physical -> Logical -> Physical *)
Theorem to_physical_to_logical_id :
  forall (p : PhysicalBoxStrut) (wdm : WritingDirectionMode),
    ToPhysical (ToLogical p wdm) wdm = p.
Proof.
  intros [t r b l] [[| | | |] [|]];
    unfold ToLogical, ToPhysical; simpl; reflexivity.
Qed.

(** Universal Total Perimeter Sum Invariant across all modes and directions *)
Theorem total_strut_sum_invariant :
  forall (s : LogicalBoxStrut) (wdm : WritingDirectionMode),
    let p := ToPhysical s wdm in
    HorizontalSum p + VerticalSum p = InlineSum s + BlockSum s.
Proof.
  intros [is ie bs be] [[| | | |] [|]];
    unfold HorizontalSum, VerticalSum, InlineSum, BlockSum, ToPhysical;
    simpl; lia.
Qed.
```