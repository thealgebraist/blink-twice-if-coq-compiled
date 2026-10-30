### 1. Core Data Structures in Blink `aspect-ratio`

In Chromium’s Blink rendering engine (specifically within `third_party/blink/renderer/core/style/` and `core/layout/`), the CSS `aspect-ratio` property is represented and resolved using physical and logical layout primitives.

*   **`EAspectRatioType`**: An enumeration representing the syntactic structure of the CSS property:
    *   `kAuto`: Represents `aspect-ratio: auto`. No preferred aspect ratio is applied unless the element is a replaced element with an intrinsic ratio.
    *   `kRatio`: Represents `aspect-ratio: <width> / <height>`. The box's preferred aspect ratio is explicitly defined by the given ratio.
    *   `kAutoAndRatio`: Represents `aspect-ratio: auto <width> / <height>`. For replaced elements with an intrinsic aspect ratio, `auto` is used; otherwise, the specified `<width> / <height>` ratio is used.

*   **`StyleAspectRatio`**: Stored on `ComputedStyle`, encapsulating `EAspectRatioType` and a floating-point `gfx::SizeF` representing the raw parsed ratio before layout snapping.

*   **`LogicalAspectRatio` (`LogicalSize`)**: During layout (LayoutNG), the physical ratio from `ComputedStyle` is converted into writing-mode-relative logical coordinates (`inline_size` $W$ and `block_size` $H$), represented using fixed-point `LayoutUnit` values (1/64th of a pixel). A `LogicalSize` is considered degenerate/empty if $W \le 0$ or $H \le 0$.

---

### 2. Dimension Transfer Algorithm

In CSS Box Sizing Level 4, an aspect ratio relates the inline size ($I$) and block size ($B$) via $\frac{I}{B} = \frac{W}{H}$. Blink implements this transfer in `ng_length_utils.cc` (`InlineSizeFromAspectRatio` and `BlockSizeFromAspectRatio`).

Given a valid `LogicalAspectRatio` $(W, H)$ where $W > 0 \land H > 0$:

1.  **Inline-to-Block Transfer** (resolving $B$ from a definite $I$):
    $$B = \left\lfloor \frac{I \times H}{W} \right\rfloor$$

2.  **Block-to-Inline Transfer** (resolving $I$ from a definite $B$):
    $$I = \left\lfloor \frac{B \times W}{H} \right\rfloor$$

#### Box Sizing Adjustment (`EBoxSizing`)
The CSS `aspect-ratio` applies to the box specified by `box-sizing` (`content-box` by default, or `border-box`). Because Blink’s internal layout algorithms operate primarily on border-box dimensions, transferring across the ratio requires stripping and re-applying `BoxStrut` (the sum of border and padding in the respective axis, denoted $BP_{\text{inline}}$ and $BP_{\text{block}}$):

*   **If `box-sizing: border-box`**: The ratio applies directly to the border-box dimensions.
*   **If `box-sizing: content-box`**:
    $$B_{\text{border}} = \left(\max(0, I_{\text{border}} - BP_{\text{inline}}) \times \frac{H}{W}\right) + BP_{\text{block}}$$

---

### 3. Interaction with Min/Max Sizing Constraints

Per CSS Box Sizing Level 4 § 5.1, `min-*` and `max-*` constraints clamp the aspect-ratio-derived sizes, and constraints on one axis can transfer through the aspect ratio to constrain the other axis.

#### Standard Clamping Precedence
In CSS, when both `min` and `max` constraints exist on a single axis, **min overrides max**. This is resolved via the standard CSS clamping function:
$$\text{Clamp}(v, \text{min}, \text{max}) = \max(\text{min}, \min(v, \text{max}))$$

#### Constraint Transfer Across Axes
1.  **Definite Inline, Auto Block**:
    The definite inline size $I$ is first clamped by $[I_{\min}, I_{\max}]$. Then $I$ is transferred to $B_{\text{raw}} = \lfloor I \cdot H / W \rfloor$. Finally, $B_{\text{raw}}$ is clamped by the block-axis constraints:
    $$B = \max(B_{\min}, \min(B_{\text{raw}}, B_{\max}))$$
2.  **Unconstrained (Auto) Inline, Unconstrained (Auto) Block with Transferred Constraints**:
    If an axis is `auto` and receives a base size (e.g., stretching to fill the containing block's available inline size), and the resulting block size violates $B_{\min}$ or $B_{\max}$, the constraint transfers back to the inline axis if the inline axis is not explicitly fixed (`width: auto`). Specifically, `[B_min, B_max]` transfers via $W/H$ to become transferred inline constraints `[I_transferred_min, I_transferred_max]`, which then clamp the automatic inline size before the final block size is computed.

---

### 4. Mathematical Invariants

To verify Blink's implementation against CSS Box Sizing Level 4, the layout engine must preserve the following invariants over $\mathbb{N}$ (representing non-negative `LayoutUnit` quanta):

1.  **Non-Negativity**: Since layout lengths and valid aspect ratios are non-negative, transferring any non-negative dimension yields a non-negative dimension.
2.  **Determinism**: For any given state of constraints, box-sizing mode, and aspect ratio, the resolved `(inline_size, block_size)` pair is unique.
3.  **Clamping Dominance (Min-Overrides-Max)**: If $\text{min\_size} > \text{max\_size}$, the resolved dimension equals $\text{min\_size}$.
4.  **Ratio Transfer Involution (Exactness under Divisibility)**: In continuous real arithmetic, transferring $I \to B \to I'$ is an exact involution: $(I \cdot \frac{H}{W}) \cdot \frac{W}{H} = I$. In Blink's discrete fixed-point arithmetic (`LayoutUnit`), integer division truncation introduces a loss of precision bounded by $\frac{W}{H}$. Exact involution holds whenever $W$ divides $I \cdot H$.

---

### 5. Rocq / Coq Formalization: `BlinkAspectRatioTransferSemantics.v`

The following self-contained Rocq (Coq) script formalizes the Blink data structures, the dimension transfer functions, constraint clamping, and proves the core invariants.

```coq
(** * BlinkAspectRatioTransferSemantics.v
    Formalization of Chromium Blink CSS aspect-ratio Dimension Transfer 
    vs CSS Box Sizing Module Level 4.
    Author: Agent 68 *)

Require Import Coq.Arith.Arith.
Require Import Coq.Arith.PeanoNat.
Require Import Coq.micromega.Lia.

Module BlinkAspectRatio.

(** ** 1. Core Data Structures *)

(** Represents Blink's [EAspectRatioType] *)
Inductive EAspectRatioType : Type :=
  | kAuto
  | kRatio
  | kAutoAndRatio.

(** Represents Blink's [EBoxSizing] *)
Inductive EBoxSizing : Type :=
  | kContentBox
  | kBorderBox.

(** Represents Blink's [LogicalAspectRatio] using discrete LayoutUnits (nat).
    In Blink, a ratio is valid iff inline_ratio > 0 and block_ratio > 0. *)
Record LogicalAspectRatio : Type := mkLogicalAspectRatio {
  inline_ratio : nat;
  block_ratio  : nat
}.

Definition is_valid_ratio (r : LogicalAspectRatio) : Prop :=
  inline_ratio r > 0 /\ block_ratio r > 0.

(** Represents border + padding struts in logical axes ([NGBoxStrut] sums) *)
Record BoxStrut : Type := mkBoxStrut {
  inline_strut : nat;
  block_strut  : nat
}.

(** Represents min/max sizing constraints on a single axis *)
Record MinMaxConstraint : Type := mkMinMax {
  min_size : nat;
  max_size : option nat (* None represents LayoutUnit::Max() / infinity *)
}.

(** ** 2. Clamping and Dimension Transfer Algorithms *)

(** Standard CSS clamping: max(min_val, min(val, max_val)).
    Notice that min_size takes precedence over max_size. *)
Definition clamp_dimension (val : nat) (c : MinMaxConstraint) : nat :=
  match max_size c with
  | None => Nat.max (min_size c) val
  | Some max_v => Nat.max (min_size c) (Nat.min val max_v)
  end.

(** Core ratio transfer: Inline -> Block (B = I * H / W) *)
Definition transfer_inline_to_block_raw (inline_sz : nat) (r : LogicalAspectRatio) : nat :=
  (inline_sz * block_ratio r) / inline_ratio r.

(** Core ratio transfer: Block -> Inline (I = B * W / H) *)
Definition transfer_block_to_inline_raw (block_sz : nat) (r : LogicalAspectRatio) : nat :=
  (block_sz * inline_ratio r) / block_ratio r.

(** Full Blink [BlockSizeFromAspectRatio] accounting for box-sizing and struts *)
Definition block_size_from_aspect_ratio 
  (inline_border_box : nat) 
  (strut : BoxStrut) 
  (sizing : EBoxSizing) 
  (r : LogicalAspectRatio) 
  (block_constraints : MinMaxConstraint) : nat :=
  let raw_block :=
    match sizing with
    | kBorderBox => 
        transfer_inline_to_block_raw inline_border_box r
    | kContentBox =>
        let content_inline := inline_border_box - inline_strut strut in
        let content_block  := transfer_inline_to_block_raw content_inline r in
        content_block + block_strut strut
    end
  in clamp_dimension raw_block block_constraints.

(** Full Blink [InlineSizeFromAspectRatio] accounting for box-sizing and struts *)
Definition inline_size_from_aspect_ratio 
  (block_border_box : nat) 
  (strut : BoxStrut) 
  (sizing : EBoxSizing) 
  (r : LogicalAspectRatio) 
  (inline_constraints : MinMaxConstraint) : nat :=
  let raw_inline :=
    match sizing with
    | kBorderBox => 
        transfer_block_to_inline_raw block_border_box r
    | kContentBox =>
        let content_block  := block_border_box - block_strut strut in
        let content_inline := transfer_block_to_inline_raw content_block r in
        content_inline + inline_strut strut
    end
  in clamp_dimension raw_inline inline_constraints.

(** ** 3. Formal Verification of Mathematical Invariants *)

(** Theorem 1: Determinism of Aspect Ratio Transfer *)
Theorem transfer_deterministic : forall i s sz r c b1 b2,
  b1 = block_size_from_aspect_ratio i s sz r c ->
  b2 = block_size_from_aspect_ratio i s sz r c ->
  b1 = b2.
Proof.
  intros. subst. reflexivity.
Qed.

(** Theorem 2: Non-negativity of Resolved Dimensions *)
Theorem block_size_non_negative : forall i s sz r c,
  0 <= block_size_from_aspect_ratio i s sz r c.
Proof.
  intros. lia.
Qed.

(** Theorem 3: Min Constraint Always Overrides Max Constraint (CSS Box Sizing 4) *)
Theorem min_overrides_max : forall val min_v max_v,
  min_v > max_v ->
  clamp_dimension val (mkMinMax min_v (Some max_v)) = min_v.
Proof.
  intros val min_v max_v Hgt.
  unfold clamp_dimension. simpl.
  assert (Nat.min val max_v <= max_v) by apply Nat.le_min_r.
  apply Nat.max_l. lia.
Qed.

(** Theorem 4: Clamped Value Always Respects Min Size *)
Theorem clamp_respects_min : forall val c,
  min_size c <= clamp_dimension val c.
Proof.
  intros val [min_v [max_v | ]].
  - unfold clamp_dimension; simpl. apply Nat.le_max_l.
  - unfold clamp_dimension; simpl. apply Nat.le_max_l.
Qed.

(** Theorem 5: Clamped Value Respects Max Size When Min <= Max *)
Theorem clamp_respects_max : forall val min_v max_v,
  min_v <= max_v ->
  clamp_dimension val (mkMinMax min_v (Some max_v)) <= max_v.
Proof.
  intros val min_v max_v Hle.
  unfold clamp_dimension; simpl.
  apply Nat.max_lub.
  - exact Hle.
  - apply Nat.le_min_r.
Qed.

(** Theorem 6: Ratio Transfer Involution (Exactness under Divisibility).
    If inline_ratio divides (inline_sz * block_ratio), transferring 
    Inline -> Block -> Inline recovers the exact original inline_sz. *)
Theorem ratio_transfer_involution_exact : forall (inline_sz : nat) (r : LogicalAspectRatio),
  is_valid_ratio r ->
  Nat.divide (inline_ratio r) (inline_sz * block_ratio r) ->
  transfer_block_to_inline_raw (transfer_inline_to_block_raw inline_sz r) r = inline_sz.
Proof.
  intros inline_sz [W H] [HW HH] Hdiv.
  unfold transfer_inline_to_block_raw, transfer_block_to_inline_raw in *.
  simpl in *.
  destruct Hdiv as [k Hk].
  rewrite Hk.
  rewrite Nat.div_mul by lia.
  (* Now we have (k * W) / H, and we know k * W = inline_sz * H *)
  assert (HkW : k * W = inline_sz * H) by lia.
  rewrite HkW.
  rewrite Nat.div_mul by lia.
  reflexivity.
Qed.

(** Theorem 7: Monotonicity of Aspect Ratio Transfer.
    Larger inline sizes never produce smaller block sizes. *)
Theorem transfer_inline_to_block_monotonic : forall i1 i2 r,
  i1 <= i2 ->
  transfer_inline_to_block_raw i1 r <= transfer_inline_to_block_raw i2 r.
Proof.
  intros i1 i2 [W H] Hle.
  unfold transfer_inline_to_block_raw; simpl.
  destruct (Nat.eq_dec W 0) as [HW0 | HW_neq0].
  - subst W. repeat rewrite Nat.div_0_r. lia.
  -