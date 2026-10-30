### Audit Report: Agent 203
**Target:** Chromium Blink Orthogonal Size Transposition (`LogicalSize` ↔ `PhysicalSize`)  
**Specification:** CSS Writing Modes Level 3 §7.3 (Orthogonal Flows) & §6.2 (Flow-Relative Mappings)

---

### 1. Size Transposition Semantics
In CSS Writing Modes Level 3 §7.3, if an element has a writing mode whose block-flow direction is perpendicular to that of its containing block, it establishes an *orthogonal flow*. 

In Chromium Blink's layout engine (`third_party/blink/renderer/core/layout/geometry/logical_size.h` and `writing_mode_converter.h`), coordinate spaces are separated into `LogicalSize` (`inline_size`, `block_size`) and `PhysicalSize` (`width`, `height`).

* **Horizontal Writing Modes (`horizontal-tb`):** 
  $$\text{physical\_w} = \text{logical\_inline}, \quad \text{physical\_h} = \text{logical\_block}$$
* **Vertical / Orthogonal Writing Modes (`vertical-rl`, `vertical-lr`, `sideways-rl`, `sideways-lr`):** 
  The inline axis runs vertically and the block axis runs horizontally. Therefore, converting a logical size to a physical size (or converting between two orthogonal logical coordinate spaces) requires exact dimension transposition:
  $$\text{physical\_w} = \text{logical\_block}, \quad \text{physical\_h} = \text{logical\_inline}$$

---

### 2. Core Invariants
To prevent layout oscillation, infinite sizing loops, and subpixel rounding loss during orthogonal constraint resolution, Blink's transposition functions (`Transpose()`, `ToPhysicalSize()`, `ToLogicalSize()`) must satisfy two strict algebraic invariants:

1. **Involution:** Transposing a size twice (e.g., mapping from parent logical space $\to$ orthogonal child logical space $\to$ parent logical space, or Round-Tripping `Logical` $\to$ `Physical` $\to$ `Logical` in a vertical mode) is an identity operation:
   $$\forall s, \quad \text{transpose}(\text{transpose}(s)) = s$$
2. **Area Preservation:** The 2D scalar area of a layout box is invariant under writing mode transposition (relying on the commutativity of fixed-point layout unit multiplication):
   $$\forall s, \quad \text{area}(\text{transpose}(s)) = \text{area}(s)$$

---

### 3. Concrete Rocq / Coq Formalization

Below is the complete, self-contained formalization for `BlinkLogicalSizeOrthogonalSemantics.v`.

```coq
(** * BlinkLogicalSizeOrthogonalSemantics.v
    Formal Audit by Agent 203: Chromium Blink Orthogonal Size Transposition
    vs. CSS Writing Modes Level 3 §7.3. *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Bool.Bool.

Open Scope Z_scope.

(** ** 1. Basic Types & Geometry Primitives *)

(** Blink represents layout dimensions using fixed-point LayoutUnits (1/64th px).
    We model LayoutUnit raw values over integer Z. *)
Definition LayoutUnit := Z.

(** CSS Writing Modes as implemented in Blink (writing_mode.h) *)
Inductive WritingMode : Type :=
  | HorizontalTb
  | VerticalRl
  | VerticalLr
  | SidewaysRl
  | SidewaysLr.

(** Classification of horizontal vs vertical (orthogonal to horizontal) modes *)
Definition is_horizontal (wm : WritingMode) : bool :=
  match wm with
  | HorizontalTb => true
  | _ => false
  end.

(** Two writing modes are orthogonal iff one is horizontal and the other is vertical *)
Definition is_orthogonal (wm1 wm2 : WritingMode) : bool :=
  xorb (is_horizontal wm1) (is_horizontal wm2).

(** Flow-relative LogicalSize (logical_size.h) *)
Record LogicalSize : Type := mkLogicalSize {
  inline_size : LayoutUnit;
  block_size  : LayoutUnit
}.

(** Physical coordinate PhysicalSize (physical_size.h) *)
Record PhysicalSize : Type := mkPhysicalSize {
  phys_width  : LayoutUnit;
  phys_height : LayoutUnit
}.

(** ** 2. Transposition and Conversion Operations *)

(** Raw transposition of a LogicalSize (Blink's LogicalSize::Transpose) *)
Definition transpose_logical (s : LogicalSize) : LogicalSize :=
  mkLogicalSize (block_size s) (inline_size s).

(** Raw transposition of a PhysicalSize (Blink's PhysicalSize::Transpose) *)
Definition transpose_physical (p : PhysicalSize) : PhysicalSize :=
  mkPhysicalSize (phys_height p) (phys_width p).

(** Convert LogicalSize to PhysicalSize (Blink's ToPhysicalSize) *)
Definition to_physical_size (s : LogicalSize) (wm : WritingMode) : PhysicalSize :=
  if is_horizontal wm then
    mkPhysicalSize (inline_size s) (block_size s)
  else
    mkPhysicalSize (block_size s) (inline_size s).

(** Convert PhysicalSize to LogicalSize (Blink's ToLogicalSize) *)
Definition to_logical_size (p : PhysicalSize) (wm : WritingMode) : LogicalSize :=
  if is_horizontal wm then
    mkLogicalSize (phys_width p) (phys_height p)
  else
    mkLogicalSize (phys_height p) (phys_width p).

(** Convert LogicalSize from container writing mode [wm_from] to child [wm_to] *)
Definition convert_logical_size (wm_from wm_to : WritingMode) (s : LogicalSize) : LogicalSize :=
  if is_orthogonal wm_from wm_to then
    transpose_logical s
  else
    s.

(** Area computations *)
Definition logical_area (s : LogicalSize) : Z :=
  (inline_size s) * (block_size s).

Definition physical_area (p : PhysicalSize) : Z :=
  (phys_width p) * (phys_height p).

(** ** 3. Audit Verification Theorems *)

(** *** Requirement 1: Orthogonal Physical Mapping Specification *)

Theorem orthogonal_to_physical_spec :
  forall (s : LogicalSize) (wm : WritingMode),
    is_horizontal wm = false ->
    phys_width (to_physical_size s wm) = block_size s /\
    phys_height (to_physical_size s wm) = inline_size s.
Proof.
  intros s wm H_ortho.
  unfold to_physical_size.
  rewrite H_ortho.
  simpl.
  split; reflexivity.
Qed.

(** *** Requirement 2a: Involution Invariants *)

(** Transposing a LogicalSize twice restores the exact original size. *)
Theorem transpose_logical_involutive :
  forall (s : LogicalSize),
    transpose_logical (transpose_logical s) = s.
Proof.
  intros [i b].
  unfold transpose_logical.
  simpl.
  reflexivity.
Qed.

(** Transposing a PhysicalSize twice restores the exact original size. *)
Theorem transpose_physical_involutive :
  forall (p : PhysicalSize),
    transpose_physical (transpose_physical p) = p.
Proof.
  intros [w h].
  unfold transpose_physical.
  simpl.
  reflexivity.
Qed.

(** Round-tripping Logical -> Physical -> Logical under the same writing mode is an identity. *)
Theorem logical_physical_roundtrip :
  forall (s : LogicalSize) (wm : WritingMode),
    to_logical_size (to_physical_size s wm) wm = s.
Proof.
  intros [i b] wm.
  unfold to_logical_size, to_physical_size.
  destruct (is_horizontal wm); simpl; reflexivity.
Qed.

(** Converting logical size across writing modes and back is an involution. *)
Theorem convert_logical_size_involutive :
  forall (wm1 wm2 : WritingMode) (s : LogicalSize),
    convert_logical_size wm2 wm1 (convert_logical_size wm1 wm2 s) = s.
Proof.
  intros wm1 wm2 [i b].
  unfold convert_logical_size, is_orthogonal.
  rewrite xorb_comm.
  destruct (xorb (is_horizontal wm1) (is_horizontal wm2));
    simpl; reflexivity.
Qed.

(** *** Requirement 2b: Area Preservation Invariants *)

(** Logical transposition preserves area. *)
Theorem transpose_logical_preserves_area :
  forall (s : LogicalSize),
    logical_area (transpose_logical s) = logical_area s.
Proof.
  intros [i b].
  unfold logical_area, transpose_logical.
  simpl.
  apply Z.mul_comm.
Qed.

(** Conversion to PhysicalSize preserves area across all writing modes. *)
Theorem to_physical_preserves_area :
  forall (s : LogicalSize) (wm : WritingMode),
    physical_area (to_physical_size s wm) = logical_area s.
Proof.
  intros [i b] wm.
  unfold physical_area, logical_area, to_physical_size.
  destruct (is_horizontal wm); simpl.
  - reflexivity.
  - apply Z.mul_comm.
Qed.

(** Cross-writing-mode logical conversion preserves area. *)
Theorem convert_logical_preserves_area :
  forall (wm1 wm2 : WritingMode) (s : LogicalSize),
    logical_area (convert_logical_size wm1 wm2 s) = logical_area s.
Proof.
  intros wm1 wm2 s.
  unfold convert_logical_size.
  destruct (is_orthogonal wm1 wm2).
  - apply transpose_logical_preserves_area.
  - reflexivity.
Qed.
```