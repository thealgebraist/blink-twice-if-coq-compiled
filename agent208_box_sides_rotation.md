### 1. Logical to Physical Sides Mapping (CSS Writing Modes 3 §4.2 vs. Chromium Blink)

In CSS Writing Modes Level 3 (§4.2) and Chromium Blink's layout engine (`third_party/blink/renderer/platform/text/writing_direction_mode.cc` and `ng_box_strut.h`), box edges (margins, borders, padding) are defined logically (`block-start`, `block-end`, `inline-start`, `inline-end`) and resolved into physical coordinates (`top`, `right`, `bottom`, `left`) depending on the `writing-mode` and `direction` properties.

Assuming a standard `ltr` (left-to-right) inline base direction, the transformation matrices between Logical Sides $(bs, be, is, ie)$ and Physical Sides $(top, bottom, left, right)$ are defined as follows:

| Writing Mode | Direction | Block-Start ($bs$) | Block-End ($be$) | Inline-Start ($is$) | Inline-End ($ie$) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`horizontal-tb`** | `ltr` | `top` | `bottom` | `left` | `right` |
| **`horizontal-tb`** | `rtl` | `top` | `bottom` | `right` | `left` |
| **`vertical-rl`** | `ltr` | `right` | `left` | `top` | `bottom` |
| **`vertical-rl`** | `rtl` | `right` | `left` | `bottom` | `top` |
| **`vertical-lr`** | `ltr` | `left` | `right` | `top` | `bottom` |
| **`vertical-lr`** | `rtl` | `left` | `right` | `bottom` | `top` |
| **`sideways-rl`** | `ltr` | `right` | `left` | `top` | `bottom` |
| **`sideways-lr`** | `ltr` | `left` | `right` | `bottom` | `top` |

#### Audit Focus:
1. **`horizontal-tb` (`ltr`)**: The block flow is top-to-bottom; inline flow is left-to-right.
   * $bs \mapsto \text{top}$, $be \mapsto \text{bottom}$, $is \mapsto \text{left}$, $ie \mapsto \text{right}$.
2. **`vertical-rl` (`ltr`)**: The block flow is right-to-left ($90^\circ$ clockwise rotation of the block axis); inline flow is top-to-bottom.
   * $bs \mapsto \text{right}$, $be \mapsto \text{left}$, $is \mapsto \text{top}$, $ie \mapsto \text{bottom}$.

---

### 2. Core Invariants

1. **Perimeter Sum Preservation ($L_1$-Norm Invariance)**:
   Because any valid CSS writing-mode and direction combination induces a bijective permutation $P \in S_4$ mapping the four logical edges to the four physical edges, the total scalar sum of the box sides (e.g., total border/padding/margin thickness) is strictly invariant under directional rotation:
   $$\text{top} + \text{bottom} + \text{left} + \text{right} = bs + be + is + ie$$

2. **Axis-Sum Preservation / Orthogonal Swapping**:
   * For horizontal writing modes (`horizontal-tb`), the vertical physical sum equals the block sum ($\text{top} + \text{bottom} = bs + be$) and the horizontal physical sum equals the inline sum ($\text{left} + \text{right} = is + ie$).
   * For vertical writing modes (`vertical-rl`, `vertical-lr`, `sideways-*`), the axes swap orthogonally: the vertical physical sum equals the inline sum ($\text{top} + \text{bottom} = is + ie$) and the horizontal physical sum equals the block sum ($\text{left} + \text{right} = bs + be$).

3. **Bijective Invertibility**:
   Mapping from Logical to Physical sides and back using the identical `WritingDirectionMode` yields the exact identity transformation: $\text{ToLogical}(\text{ mode }, \text{ToPhysical}(\text{ mode }, L)) = L$.

---

### 3. Concrete Rocq / Coq Formalization (`BlinkBoxSidesRotationSemantics.v`)

The following file provides a complete, self-contained Rocq/Coq specification and verification of Chromium Blink's box side rotational semantics.

```coq
(** * BlinkBoxSidesRotationSemantics.v
    Agent 208 Audit: Chromium Blink Box Sides Directional Rotation 
    vs CSS Writing Modes Level 3 §4.2 *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
Open Scope Z_scope.

(** ** 1. Data Types for Writing Modes, Directions, and Box Struts *)

Inductive WritingMode : Type :=
  | HorizontalTb
  | VerticalRl
  | VerticalLr
  | SidewaysRl
  | SidewaysLr.

Inductive TextDirection : Type :=
  | Ltr
  | Rtl.

Record WritingDirectionMode : Type := mkWritingDirection {
  wm  : WritingMode;
  dir : TextDirection
}.

(** Logical Box Sides:對應 Blink's NGBoxStrut *)
Record LogicalSides : Type := mkLogicalSides {
  bs : Z; (* block-start  *)
  be : Z; (* block-end    *)
  is : Z; (* inline-start *)
  ie : Z  (* inline-end   *)
}.

(** Physical Box Sides:對應 Blink's NGPhysicalBoxStrut *)
Record PhysicalSides : Type := mkPhysicalSides {
  top    : Z;
  right  : Z;
  bottom : Z;
  left   : Z
}.

(** ** 2. Rotational Mapping Semantics (Logical <-> Physical) *)

Definition to_physical (wd : WritingDirectionMode) (l : LogicalSides) : PhysicalSides :=
  match wm wd, dir wd with
  | HorizontalTb, Ltr =>
      mkPhysicalSides (bs l) (ie l) (be l) (is l)
  | HorizontalTb, Rtl =>
      mkPhysicalSides (bs l) (is l) (be l) (ie l)
  | VerticalRl, Ltr | SidewaysRl, Ltr =>
      mkPhysicalSides (is l) (bs l) (ie l) (be l)
  | VerticalRl, Rtl | SidewaysRl, Rtl =>
      mkPhysicalSides (ie l) (bs l) (is l) (be l)
  | VerticalLr, Ltr =>
      mkPhysicalSides (is l) (be l) (ie l) (bs l)
  | VerticalLr, Rtl =>
      mkPhysicalSides (ie l) (be l) (is l) (bs l)
  | SidewaysLr, Ltr =>
      mkPhysicalSides (ie l) (be l) (is l) (bs l)
  | SidewaysLr, Rtl =>
      mkPhysicalSides (is l) (be l) (ie l) (bs l)
  end.

Definition to_logical (wd : WritingDirectionMode) (p : PhysicalSides) : LogicalSides :=
  match wm wd, dir wd with
  | HorizontalTb, Ltr =>
      mkLogicalSides (top p) (bottom p) (left p) (right p)
  | HorizontalTb, Rtl =>
      mkLogicalSides (top p) (bottom p) (right p) (left p)
  | VerticalRl, Ltr | SidewaysRl, Ltr =>
      mkLogicalSides (right p) (left p) (top p) (bottom p)
  | VerticalRl, Rtl | SidewaysRl, Rtl =>
      mkLogicalSides (right p) (left p) (bottom p) (top p)
  | VerticalLr, Ltr =>
      mkLogicalSides (left p) (right p) (top p) (bottom p)
  | VerticalLr, Rtl =>
      mkLogicalSides (left p) (right p) (bottom p) (top p)
  | SidewaysLr, Ltr =>
      mkLogicalSides (left p) (right p) (bottom p) (top p)
  | SidewaysLr, Rtl =>
      mkLogicalSides (left p) (right p) (top p) (bottom p)
  end.

(** ** 3. Perimeter Sum Definitions *)

Definition logical_perimeter (l : LogicalSides) : Z :=
  bs l + be l + is l + ie l.

Definition physical_perimeter (p : PhysicalSides) : Z :=
  top p + bottom p + left p + right p.

(** ** 4. Audited Theorems and Invariants *)

(** Specification Check 1: horizontal-tb (LTR) mapping *)
Theorem audit_horizontal_tb_ltr_mapping :
  forall (l : LogicalSides),
    let p := to_physical (mkWritingDirection HorizontalTb Ltr) l in
    top p = bs l /\ bottom p = be l /\ left p = is l /\ right p = ie l.
Proof.
  intros l. simpl. repeat split; reflexivity.
Qed.

(** Specification Check 2: vertical-rl (LTR) mapping *)
Theorem audit_vertical_rl_ltr_mapping :
  forall (l : LogicalSides),
    let p := to_physical (mkWritingDirection VerticalRl Ltr) l in
    right p = bs l /\ left p = be l /\ top p = is l /\ bottom p = ie l.
Proof.
  intros l. simpl. repeat split; reflexivity.
Qed.

(** Core Invariant 1: Total Perimeter Sum is Preserved Under Rotation *)
Theorem perimeter_sum_invariant :
  forall (wd : WritingDirectionMode) (l : LogicalSides),
    physical_perimeter (to_physical wd l) = logical_perimeter l.
Proof.
  intros [w d] [bs_v be_v is_v ie_v].
  unfold physical_perimeter, logical_perimeter, to_physical; simpl.
  destruct w, d; simpl; lia.
Qed.

(** Core Invariant 2: Round-Trip Bijection (Logical -> Physical -> Logical) *)
Theorem to_logical_to_physical_id :
  forall (wd : WritingDirectionMode) (l : LogicalSides),
    to_logical wd (to_physical wd l) = l.
Proof.
  intros [w d] [bs_v be_v is_v ie_v].
  destruct w, d; simpl; reflexivity.
Qed.

(** Core Invariant 3: Round-Trip Bijection (Physical -> Logical -> Physical) *)
Theorem to_physical_to_logical_id :
  forall (wd : WritingDirectionMode) (p : PhysicalSides),
    to_physical wd (to_logical wd p) = p.
Proof.
  intros [w d] [t r b l].
  destruct w, d; simpl; reflexivity.
Qed.

(** Core Invariant 4: Non-negativity Preservation *)
Definition non_negative_logical (l : LogicalSides) : Prop :=
  0 <= bs l /\ 0 <= be l /\ 0 <= is l /\ 0 <= ie l.

Definition non_negative_physical (p : PhysicalSides) : Prop :=
  0 <= top p /\ 0 <= bottom p /\ 0 <= left p /\ 0 <= right p.

Theorem non_negative_preserved :
  forall (wd : WritingDirectionMode) (l : LogicalSides),
    non_negative_logical l <-> non_negative_physical (to_physical wd l).
Proof.
  intros [w d] [bs_v be_v is_v ie_v].
  unfold non_negative_logical, non_negative_physical.
  destruct w, d; simpl; lia.
Qed.
```