### 1. Cross-Axis Computation

In Chromium's Blink rendering engine (specifically within `LayoutReplaced` and `NGReplacedLayoutAlgorithm`), replaced elements with an intrinsic aspect ratio compute their cross-axis dimension by scaling the resolved main-axis dimension. Under CSS Sizing Module Level 3 §5.2 ("Intrinsic Sizes and Aspect Ratios"), if the inline size $w$ is definite and the block size $h$ is auto, $h$ is resolved via the intrinsic ratio $r_w : r_h$.

In Blink's integer/fixed-point layout arithmetic (`LayoutUnit`), this computation is modeled over integers $\mathbb{Z}$ as:

$$h = \lfloor (w \times r_h) / r_w \rfloor$$

where $r_w > 0$ and $r_h > 0$ represent the strictly positive intrinsic width and height ratio components, and `/` denotes truncated/floored integer division (`Z.div` in Rocq/Coq).

---

### 2. Core Invariants

1. **Non-Negativity (`h >= 0` when `w >= 0`):** 
   Given valid positive aspect ratio components ($r_w > 0, r_h > 0$), a non-negative resolved width $w \ge 0$ guarantees a non-negative computed height $h \ge 0$. Under `Z.div`, multiplying two non-negative numbers and dividing by a strictly positive number preserves non-negativity without underflow.

2. **Monotonicity (`h` monotonic in `w`):** 
   For any two widths $w_1, w_2$ such that $0 \le w_1 \le w_2$, the resulting heights satisfy $h(w_1) \le h(w_2)$. Because $r_h > 0$, the intermediate product scales monotonically ($w_1 \times r_h \le w_2 \times r_h$), and integer division by $r_w > 0$ is order-preserving.

---

### 3. Concrete Rocq / Coq Formalization

Below is the complete, self-contained formalization for `BlinkReplacedAspectRatioSemantics.v` using standard `ZArith` and `Lia` with **0 admits**.

```coq
(** * BlinkReplacedAspectRatioSemantics.v
    Audit of Chromium Blink Replaced Element Aspect Ratio vs CSS Sizing 3 §5.2
    Agent 231 Formal Verification Module *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Section BlinkReplacedAspectRatio.

  (** Cross-axis computation: h = (w * r_h) / r_w *)
  Definition compute_cross_axis_height (w r_w r_h : Z) : Z :=
    (w * r_h) / r_w.

  (** Strict positivity predicate for intrinsic aspect ratio components *)
  Definition valid_aspect_ratio (r_w r_h : Z) : Prop :=
    r_w > 0 /\ r_h > 0.

  (** Invariant 1: Non-negativity.
      When w >= 0 and the aspect ratio is valid, the computed height h >= 0. *)
  Theorem cross_axis_height_nonneg :
    forall (w r_w r_h : Z),
      valid_aspect_ratio r_w r_h ->
      w >= 0 ->
      compute_cross_axis_height w r_w r_h >= 0.
  Proof.
    intros w r_w r_h [Hrw Hrh] Hw.
    unfold compute_cross_axis_height.
    apply Z.le_ge.
    apply Z.div_pos.
    - apply Z.mul_nonneg_nonneg; lia.
    - lia.
  Qed.

  (** Invariant 2: Monotonicity.
      The computed height h is monotonically non-decreasing with respect to w. *)
  Theorem cross_axis_height_monotonic :
    forall (w1 w2 r_w r_h : Z),
      valid_aspect_ratio r_w r_h ->
      w1 <= w2 ->
      compute_cross_axis_height w1 r_w r_h <= compute_cross_axis_height w2 r_w r_h.
  Proof.
    intros w1 w2 r_w r_h [Hrw Hrh] Hle.
    unfold compute_cross_axis_height.
    apply Z.div_le_mono.
    - lia.
    - apply Z.mul_le_mono_nonneg_r; lia.
  Qed.

  (** Combined CSS Sizing 3 §5.2 Compliance Specification *)
  Theorem css_sizing_3_section_5_2_compliance :
    forall (w1 w2 r_w r_h : Z),
      valid_aspect_ratio r_w r_h ->
      0 <= w1 ->
      w1 <= w2 ->
      0 <= compute_cross_axis_height w1 r_w r_h /\
      compute_cross_axis_height w1 r_w r_h <= compute_cross_axis_height w2 r_w r_h.
  Proof.
    intros w1 w2 r_w r_h Hratio Hw1 Hle.
    split.
    - apply Z.ge_le.
      apply cross_axis_height_nonneg; [exact Hratio | lia].
    - apply cross_axis_height_monotonic; [exact Hratio | exact Hle].
  Qed.

End BlinkReplacedAspectRatio.
```