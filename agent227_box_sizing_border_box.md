### 1. Audit Report: Chromium Blink `border-box` vs. CSS Box Sizing Module Level 3 §3

**Target Specification:** CSS Box Sizing Module Level 3, Section 3 (Box-sizing)  
**Target Implementation:** Chromium Blink `third_party/blink/renderer/core/layout/` (specifically `box_sizing` adjustment logic in `LayoutBox` / NG Layout algorithms).

#### 1.1 Subtraction Semantics
According to CSS Box Sizing 3 §3, when `box-sizing: border-box` is specified, the specified `width` or `height` determines the border box size of the element. The content box size is derived by subtracting the padding and border sizes from the specified border box size, floored at zero:

$$\text{content\_size} = \max(0, \text{border\_box\_size} - (\text{padding} + \text{border}))$$

In Chromium Blink (using `LayoutUnit` fixed-point arithmetic or integer pixel snapping), the sum of inline/block padding and border (`border_and_padding`) is subtracted from the resolved `border_box_size`. To prevent negative content geometry—which would violate layout invariants during fragment generation—Blink clamps the resulting content size to `LayoutUnit(0)`.

#### 1.2 Verified Invariants
1. **Non-negativity of Content Size:** Regardless of how large the padding and border values are relative to the specified `border-box` dimension, the computed content size is strictly non-negative ($\text{content\_size} \ge 0$).
2. **Exact Reconstruction (No Underflow Regime):** When $\text{border\_box\_size} \ge \text{padding} + \text{border}$, the sum of the computed content size, padding, and border exactly equals the specified border box size ($\text{content\_size} + \text{padding} + \text{border} = \text{border\_box\_size}$).
3. **Monotonicity / Floor Dominance (Overflow Regime):** In all cases (assuming non-negative padding and border), the actual physical border box resulting from the floored content box plus padding and border is at least as large as the specified border box size: $\text{content\_size} + \text{padding} + \text{border} \ge \text{border\_box\_size}$.

---

### 2. Formal Verification: `BlinkBoxSizingBorderBoxSemantics.v`

The following Rocq/Coq module formalizes the `border-box` subtraction semantics over integer layout units (`Z`), corresponding to Blink's signed `LayoutUnit` representation, and proves all required invariants with zero admits.

```coq
(** * BlinkBoxSizingBorderBoxSemantics.v
    Formal audit of Chromium Blink border-box sizing semantics against
    CSS Box Sizing Module Level 3 §3.
    Agent 227 Verification Artifact.
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.

Open Scope Z_scope.

Section BorderBoxSemantics.

  (** ** 1. Definitions *)

  (** Sum of start and end padding and border along a single axis (inline or block). *)
  Definition padding_and_border (padding border : Z) : Z :=
    padding + border.

  (** CSS Box Sizing 3 §3 & Blink LayoutUnit clamping semantics:
      content_size = max(0, border_box_size - (padding + border)) *)
  Definition compute_content_size (border_box_size padding border : Z) : Z :=
    Z.max 0 (border_box_size - padding_and_border padding border).

  (** The effective resulting border-box size after flooring content_size at 0. *)
  Definition effective_border_box_size (border_box_size padding border : Z) : Z :=
    compute_content_size border_box_size padding border + padding_and_border padding border.


  (** ** 2. Core Invariants *)

  (** Invariant 1: The computed content size is always non-negative. *)
  Theorem content_size_nonneg :
    forall (border_box_size padding border : Z),
      0 <= compute_content_size border_box_size padding border.
  Proof.
    intros border_box_size padding border.
    unfold compute_content_size.
    lia.
  Qed.

  (** Invariant 2a: Exact reconstruction when border_box_size >= padding + border. *)
  Theorem border_box_exact_when_sufficient :
    forall (border_box_size padding border : Z),
      padding_and_border padding border <= border_box_size ->
      compute_content_size border_box_size padding border + padding + border = border_box_size.
  Proof.
    intros border_box_size padding border H_suff.
    unfold compute_content_size, padding_and_border in *.
    lia.
  Qed.

  (** Invariant 2b: Lower-bound preservation (general inequality) when border_box_size >= pb. *)
  Theorem border_box_ge_when_sufficient :
    forall (border_box_size padding border : Z),
      padding_and_border padding border <= border_box_size ->
      border_box_size <= compute_content_size border_box_size padding border + padding + border.
  Proof.
    intros border_box_size padding border H_suff.
    unfold compute_content_size, padding_and_border in *.
    lia.
  Qed.

  (** Invariant 2c: Universal lower-bound preservation across all regimes
      (even when border_box_size < padding + border). *)
  Theorem effective_border_box_ge_specified :
    forall (border_box_size padding border : Z),
      border_box_size <= compute_content_size border_box_size padding border + padding + border.
  Proof.
    intros border_box_size padding border.
    unfold compute_content_size, padding_and_border.
    lia.
  Qed.

  (** Invariant 3: Clamping boundary behavior when padding + border exceeds border_box_size. *)
  Theorem content_size_zero_when_overflow :
    forall (border_box_size padding border : Z),
      border_box_size <= padding_and_border padding border ->
      compute_content_size border_box_size padding border = 0.
  Proof.
    intros border_box_size padding border H_over.
    unfold compute_content_size, padding_and_border in *.
    lia.
  Qed.

  (** Invariant 4: Monotonicity of content_size with respect to border_box_size. *)
  Theorem content_size_monotonic_in_border_box :
    forall (bb1 bb2 padding border : Z),
      bb1 <= bb2 ->
      compute_content_size bb1 padding border <= compute_content_size bb2 padding border.
  Proof.
    intros bb1 bb2 padding border H_le.
    unfold compute_content_size, padding_and_border.
    lia.
  Qed.

  (** Invariant 5: Antitonicity of content_size with respect to padding and border. *)
  Theorem content_size_antitonic_in_pb :
    forall (border_box_size p1 p2 b1 b2 : Z),
      p1 <= p2 ->
      b1 <= b2 ->
      compute_content_size border_box_size p2 b2 <= compute_content_size border_box_size p1 b1.
  Proof.
    intros border_box_size p1 p2 b1 b2 Hp Hb.
    unfold compute_content_size, padding_and_border.
    lia.
  Qed.

End BorderBoxSemantics.
```