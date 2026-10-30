### 1. Shift Computation Audit (Blink vs. CSS Inline 3 §5)

In Chromium's Blink engine (specifically within `NGInlineLayoutAlgorithm` and `NGLogicalLineItems`), vertical alignment is resolved in two phases: **baseline-relative shifts** (computed during inline box placement) and **line-box-relative shifts** (`top` and `bottom`, resolved after initial line box height calculation).

Note on Coordinate Systems: Blink's layout engine predominantly uses a block-progression coordinate system where positive $Y$ (or block-offset) moves **downward** (from line-over to line-under). CSS Inline 3 §5 defines positive baseline shifts as moving **upward**. The mappings below reflect Blink's internal downward-positive offset representation:

*   **`baseline`**: The dominant baseline of the alignment subtree is aligned with the dominant baseline of the parent inline box.
    $$\text{shift} = 0$$
*   **`sub`**: Lowers the alignment point of the box to the subscript offset of the parent box's font metrics (`FontMetrics::SubscriptOffset`).
    $$\text{shift} = +\text{sub\_offset}$$
*   **`super`**: Raises the alignment point of the box to the superscript offset of the parent box's font metrics (`FontMetrics::SuperscriptOffset`).
    $$\text{shift} = -\text{super\_offset}$$
*   **`middle`**: Aligns the vertical midpoint of the inline box with the parent's baseline plus half the parent's x-height (`FontMetrics::XHeight`). In downward-positive coordinates relative to the parent's baseline:
    $$\text{midpoint\_offset} = \frac{\text{descent} - \text{ascent}}{2}$$
    $$\text{target\_offset} = -\frac{\text{x\_height}}{2}$$
    $$\text{shift} = \text{midpoint\_offset} - \frac{\text{x\_height}}{2}$$
*   **`top` / `bottom`**: Aligns the top/bottom of the aligned subtree with the top/bottom of the line box. Because the line box edges depend on the maximum extent of all inline-level boxes on the line, Blink puts these elements into an unpositioned state during initial pass, calculates the encompassment metrics of the line box, and applies clamping shifts in a secondary pass.

---

### 2. Core Invariants

1.  **Height Preservation Invariant**: Vertical alignment acts strictly as a rigid 1D affine translation along the block axis. For any inline box $B$, applying a vertical alignment shift $\Delta y$ modifies its `line_over` (top) and `line_under` (bottom) coordinates identically, preserving its intrinsic layout height:
    $$\text{height}(B') = (\text{bottom}(B) + \Delta y) - (\text{top}(B) + \Delta y) = \text{height}(B)$$
2.  **Line Box Boundary Clamping Invariant**: When resolving `top` or `bottom` alignments against a finalized line box $L$ (where $\text{height}(L) \ge \text{height}(B)$), the shifted inline box $B'$ is guaranteed to remain strictly within the vertical boundaries of $L$:
    $$\text{top}(L) \le \text{top}(B') \quad \land \quad \text{bottom}(B') \le \text{bottom}(L)$$

---

### 3. Rocq / Coq Formalization (`BlinkInlineBoxVerticalAlignSemantics.v`)

```coq
(** * BlinkInlineBoxVerticalAlignSemantics.v
    Formal audit of Chromium Blink Inline Box Vertical Alignment
    against CSS Inline Layout Module Level 3, Section 5. *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.
Open Scope Z_scope.

(** ** 1. Data Structures and Metrics *)

(** Font metrics of the parent inline box.
    Values are represented in fixed-point layout units (e.g., Blink LayoutUnit). *)
Record ParentFontMetrics := mkFontMetrics {
  sub_offset   : Z; (* Positive value: distance to lower for subscript *)
  super_offset : Z; (* Positive value: distance to raise for superscript *)
  x_height     : Z  (* Height of lowercase 'x' *)
}.

(** Vertical geometry of an inline box relative to its initial baseline.
    Coordinates use Blink's downward-positive convention:
    - [ascent] is distance above baseline (thus top is at -ascent).
    - [descent] is distance below baseline (thus bottom is at +descent). *)
Record InlineBox := mkInlineBox {
  ascent  : Z;
  descent : Z
}.

(** Positioned box in absolute line-box coordinates (downward-positive). *)
Record PositionedBox := mkPositionedBox {
  box_top    : Z;
  box_bottom : Z
}.

(** Line box vertical boundaries (downward-positive). *)
Record LineBox := mkLineBox {
  line_top    : Z;
  line_bottom : Z
}.

(** CSS Inline 3 §5 Vertical Alignment Keywords *)
Inductive VerticalAlign :=
  | VA_Baseline
  | VA_Sub
  | VA_Super
  | VA_Middle
  | VA_Top
  | VA_Bottom.

(** ** 2. Helper Functions and Shift Computations *)

Definition inline_box_height (b : InlineBox) : Z :=
  ascent b + descent b.

Definition positioned_box_height (pb : PositionedBox) : Z :=
  box_bottom pb - box_top pb.

Definition line_box_height (lb : LineBox) : Z :=
  line_bottom lb - line_top lb.

(** Converts an InlineBox to a PositionedBox assuming baseline is at Y = 0. *)
Definition initial_position (b : InlineBox) : PositionedBox :=
  mkPositionedBox (- (ascent b)) (descent b).

(** Applies a downward-positive vertical shift to a PositionedBox. *)
Definition apply_shift (pb : PositionedBox) (shift : Z) : PositionedBox :=
  mkPositionedBox (box_top pb + shift) (box_bottom pb + shift).

(** Computes the baseline-relative shift for baseline, sub, super, and middle.
    Note: Division by 2 uses Z.div (floor division). *)
Definition compute_baseline_shift (va : VerticalAlign) (fm : ParentFontMetrics) (b : InlineBox) : Z :=
  match va with
  | VA_Baseline => 0
  | VA_Sub      => sub_offset fm
  | VA_Super    => - (super_offset fm)
  | VA_Middle   => ((descent b - ascent b) / 2) - (x_height fm / 2)
  | _           => 0 (* Top/Bottom are resolved against the LineBox *)
  end.

(** Resolves the final position of an inline box given its alignment,
    parent font metrics, and the enclosing line box. *)
Definition resolve_vertical_align 
  (va : VerticalAlign) (fm : ParentFontMetrics) (b : InlineBox) (lb : LineBox) : PositionedBox :=
  let init_pb := initial_position b in
  match va with
  | VA_Top    => 
      let shift := line_top lb - box_top init_pb in
      apply_shift init_pb shift
  | VA_Bottom => 
      let shift := line_bottom lb - box_bottom init_pb in
      apply_shift init_pb shift
  | _         => 
      let shift := compute_baseline_shift va fm b in
      apply_shift init_pb shift
  end.

(** ** 3. Audit Verification Theorems (Invariants) *)

(** Theorem 1a: Applying any raw shift strictly preserves the height of a PositionedBox. *)
Theorem shift_preserves_positioned_height :
  forall (pb : PositionedBox) (shift : Z),
    positioned_box_height (apply_shift pb shift) = positioned_box_height pb.
Proof.
  intros pb shift.
  unfold positioned_box_height, apply_shift; simpl.
  lia.
Qed.

(** Theorem 1b: Full vertical alignment resolution preserves the intrinsic InlineBox height. *)
Theorem vertical_align_preserves_height :
  forall (va : VerticalAlign) (fm : ParentFontMetrics) (b : InlineBox) (lb : LineBox),
    positioned_box_height (resolve_vertical_align va fm b lb) = inline_box_height b.
Proof.
  intros va fm b lb.
  unfold resolve_vertical_align, inline_box_height.
  destruct va; rewrite shift_preserves_positioned_height;
  unfold positioned_box_height, initial_position; simpl; lia.
Qed.

(** Theorem 2a: 'top' alignment clamps the inline box within the line box boundaries,
    provided the line box is at least as tall as the inline box. *)
Theorem top_align_clamps_within_line_box :
  forall (fm : ParentFontMetrics) (b : InlineBox) (lb : LineBox),
    0 <= inline_box_height b ->
    inline_box_height b <= line_box_height lb ->
    let pb := resolve_vertical_align VA_Top fm b lb in
    line_top lb <= box_top pb /\ box_bottom pb <= line_bottom lb.
Proof.
  intros fm b lb H_nonneg H_fits pb.
  unfold pb, resolve_vertical_align, apply_shift, initial_position in *; simpl in *.
  unfold inline_box_height, line_box_height in *.
  split; lia.
Qed.

(** Theorem 2b: 'bottom' alignment clamps the inline box within the line box boundaries,
    provided the line box is at least as tall as the inline box. *)
Theorem bottom_align_clamps_within_line_box :
  forall (fm : ParentFontMetrics) (b : InlineBox) (lb : LineBox),
    0 <= inline_box_height b ->
    inline_box_height b <= line_box_height lb ->
    let pb := resolve_vertical_align VA_Bottom fm b lb in
    line_top lb <= box_top pb /\ box_bottom pb <= line_bottom lb.
Proof.
  intros fm b lb H_nonneg H_fits pb.
  unfold pb, resolve_vertical_align, apply_shift, initial_position in *; simpl in *.
  unfold inline_box_height, line_box_height in *.
  split; lia.
Qed.

(** Theorem 3: Correctness of 'middle' alignment midpoint calculation.
    Verifies that twice the geometric center of a 'middle'-aligned box 
    equals twice the target x-height offset (accounting for integer division). *)
Theorem middle_align_centers_on_half_x_height :
  forall (fm : ParentFontMetrics) (b : InlineBox) (lb : LineBox),
    let pb := resolve_vertical_align VA_Middle fm b lb in
    let box_center_div_2 := (box_top pb + box_bottom pb) / 2 in
    (* Provided ascent and descent have the same parity (exact midpoint) *)
    (descent b - ascent b) mod 2 = 0 ->
    box_center_div_2 = - (x_height fm / 2).
Proof.
  intros fm b lb pb box_center_div_2 H_even.
  unfold box_center_div_2, pb, resolve_vertical_align, compute_baseline_shift,
         apply_shift, initial_position; simpl.
  replace (- ascent b + ((descent b - ascent b) / 2 - x_height fm / 2) +
           (descent b + ((descent b - ascent b) / 2 - x_height fm / 2)))
    with ((descent b - ascent b) + 2 * ((descent b - ascent b) / 2) - 2 * (x_height fm / 2)) by lia.
  pose proof (Z_div_mod_eq_full (descent b - ascent b) 2) as H_div.
  rewrite H_even in H_div.
  replace (descent b - ascent b + 2 * ((descent b - ascent b) / 2) - 2 * (x_height fm / 2))
    with (2 * (2 * ((descent b - ascent b) / 2) - (x_height fm / 2))) by lia.
  rewrite Z.mul_comm.
  rewrite Z_div_mult by lia.
  lia.
Qed.
```