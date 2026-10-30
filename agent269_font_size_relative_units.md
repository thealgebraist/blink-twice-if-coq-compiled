### Audit Report: Agent 269
**Target:** Chromium Blink Font-Size Relative Units (`third_party/blink/renderer/core/css/css_to_length_conversion_data.cc`)  
**Specification:** CSS Values and Units Module Level 4, §6.2 (Font-relative Lengths: the `em`, `rem`, etc. units)

---

### 1. Resolution Semantics

In CSS Values 4 §6.2, font-relative length units are resolved into canonical absolute lengths (pixels, `px`) by multiplying the unit scalar by a reference font size in the current layout/style evaluation context:

1. **`em` Resolution**: Relative to the computed `font-size` of the element on which it is used (or the parent element if used inside the `font-size` property itself, which is handled by scope construction prior to conversion).
   $$\text{resolve\_em}(\text{em\_count}, \text{font\_size}) = \text{em\_count} \times \text{font\_size}$$
   In Blink (`CSSToLengthConversionData::FontSizes::ZoomedEm`), this corresponds to scaling the local computed `FontSize` by the specified scalar and active zoom factor.

2. **`rem` Resolution**: Relative to the computed `font-size` of the root element (typically `<html>`).
   $$\text{resolve\_rem}(\text{rem\_count}, \text{root\_font\_size}) = \text{rem\_count} \times \text{root\_font\_size}$$
   In Blink (`CSSToLengthConversionData::FontSizes::ZoomedRem`), this references the root element's `FontDescription::ComputedSize()`.

---

### 2. Core Invariants

* **Local Font-Size Invariance of `rem`**: Modifying the local `font-size` of a descendant element has zero effect on the resolved pixel value of `rem` lengths within that descendant's style context.
* **Linearity (Additivity & Homogeneity)**: Both `em` and `rem` resolution act as linear maps with respect to unit counts (under real/rational arithmetic before subpixel layout quantization).
* **Zero Identity**: $0\text{em} = 0\text{rem} = 0\text{px}$ regardless of the font context.
* **Root Element Equivalence**: When evaluated at the document root element (where $\text{font\_size} = \text{root\_font\_size}$), `em` and `rem` resolve identically for equal scalar counts.

---

### 3. Formalization (`BlinkFontSizeRelativeUnitsSemantics.v`)

The following complete Rocq/Coq formalization models the Blink conversion context over exact real numbers (`R`), proves all stated invariants, and contains **0 admits**.

```coq
(** * BlinkFontSizeRelativeUnitsSemantics.v
    Agent 269 Audit: Chromium Blink Font-Size Relative Units vs CSS Values 4 §6.2 *)

From Coq Require Import Reals.
From Coq Require Import Lra.
Open Scope R_scope.

(** ** 1. Context and Resolution Definitions *)

(** Represents Blink's CSSToLengthConversionData::FontSizes context *)
Record FontConversionContext : Type := mkFontContext {
  local_font_size : R;
  root_font_size  : R
}.

(** Core mathematical resolution semantics per CSS Values 4 §6.2 *)
Definition resolve_em (em_count : R) (font_size : R) : R :=
  em_count * font_size.

Definition resolve_rem (rem_count : R) (root_font_size : R) : R :=
  rem_count * root_font_size.

(** Context-aware wrappers matching CSSToLengthConversionData dispatch *)
Definition eval_em_in_ctx (em_count : R) (ctx : FontConversionContext) : R :=
  resolve_em em_count (local_font_size ctx).

Definition eval_rem_in_ctx (rem_count : R) (ctx : FontConversionContext) : R :=
  resolve_rem rem_count (root_font_size ctx).

(** State transition modeling a local font-size change during style cascade *)
Definition with_local_font_size (ctx : FontConversionContext) (new_local_size : R) : FontConversionContext :=
  mkFontContext new_local_size (root_font_size ctx).


(** ** 2. Invariant Theorems *)

(** Invariant 1: rem resolution is strictly invariant to local font-size changes. *)
Theorem rem_invariant_to_local_font_size :
  forall (rem_count : R) (ctx : FontConversionContext) (new_local_size : R),
    eval_rem_in_ctx rem_count (with_local_font_size ctx new_local_size) =
    eval_rem_in_ctx rem_count ctx.
Proof.
  intros rem_count ctx new_local_size.
  unfold eval_rem_in_ctx, with_local_font_size, resolve_rem.
  simpl.
  reflexivity.
Qed.

(** Invariant 2: Explicit non-interference of arbitrary local font sizes on rem. *)
Theorem rem_local_font_size_non_interference :
  forall (rem_count root_fs local_fs1 local_fs2 : R),
    eval_rem_in_ctx rem_count (mkFontContext local_fs1 root_fs) =
    eval_rem_in_ctx rem_count (mkFontContext local_fs2 root_fs).
Proof.
  intros rem_count root_fs local_fs1 local_fs2.
  unfold eval_rem_in_ctx, resolve_rem.
  simpl.
  reflexivity.
Qed.

(** Invariant 3: Root Element Equivalence.
    At the root element (where local_font_size = root_font_size), em and rem coincide. *)
Theorem root_element_em_rem_equivalence :
  forall (count : R) (ctx : FontConversionContext),
    local_font_size ctx = root_font_size ctx ->
    eval_em_in_ctx count ctx = eval_rem_in_ctx count ctx.
Proof.
  intros count ctx H_root.
  unfold eval_em_in_ctx, eval_rem_in_ctx, resolve_em, resolve_rem.
  rewrite H_root.
  reflexivity.
Qed.

(** Invariant 4: Zero unit preservation (0em = 0px, 0rem = 0px). *)
Theorem resolve_em_zero :
  forall (font_size : R),
    resolve_em 0 font_size = 0.
Proof.
  intros font_size.
  unfold resolve_em.
  lra.
Qed.

Theorem resolve_rem_zero :
  forall (root_font_size : R),
    resolve_rem 0 root_font_size = 0.
Proof.
  intros root_font_size.
  unfold resolve_rem.
  lra.
Qed.

(** Invariant 5: Unit Identity (1em = font_size, 1rem = root_font_size). *)
Theorem resolve_em_one :
  forall (font_size : R),
    resolve_em 1 font_size = font_size.
Proof.
  intros font_size.
  unfold resolve_em.
  lra.
Qed.

Theorem resolve_rem_one :
  forall (root_font_size : R),
    resolve_rem 1 root_font_size = root_font_size.
Proof.
  intros root_font_size.
  unfold resolve_rem.
  lra.
Qed.

(** Invariant 6: Additivity (Linearity Part 1) for calc() combinations. *)
Theorem resolve_em_additive :
  forall (c1 c2 font_size : R),
    resolve_em (c1 + c2) font_size = resolve_em c1 font_size + resolve_em c2 font_size.
Proof.
  intros c1 c2 font_size.
  unfold resolve_em.
  lra.
Qed.

Theorem resolve_rem_additive :
  forall (c1 c2 root_font_size : R),
    resolve_rem (c1 + c2) root_font_size = resolve_rem c1 root_font_size + resolve_rem c2 root_font_size.
Proof.
  intros c1 c2 root_font_size.
  unfold resolve_rem.
  lra.
Qed.

(** Invariant 7: Scalar Homogeneity (Linearity Part 2) for zoom/scale factors. *)
Theorem resolve_em_scale :
  forall (scale em_count font_size : R),
    resolve_em (scale * em_count) font_size = scale * resolve_em em_count font_size.
Proof.
  intros scale em_count font_size.
  unfold resolve_em.
  lra.
Qed.

Theorem resolve_rem_scale :
  forall (scale rem_count root_font_size : R),
    resolve_rem (scale * rem_count) root_font_size = scale * resolve_rem rem_count root_font_size.
Proof.
  intros scale rem_count root_font_size.
  unfold resolve_rem.
  lra.
Qed.

(** Invariant 8: Non-negativity preservation under valid (non-negative) font sizes. *)
Theorem resolve_em_nonneg :
  forall (em_count font_size : R),
    0 <= em_count ->
    0 <= font_size ->
    0 <= resolve_em em_count font_size.
Proof.
  intros em_count font_size Hc Hfs.
  unfold resolve_em.
  apply Rmult_le_pos; assumption.
Qed.

Theorem resolve_rem_nonneg :
  forall (rem_count root_font_size : R),
    0 <= rem_count ->
    0 <= root_font_size ->
    0 <= resolve_rem rem_count root_font_size.
Proof.
  intros rem_count root_font_size Hc Hrfs.
  unfold resolve_rem.
  apply Rmult_le_pos; assumption.
Qed.

(** Invariant 9: Monotonicity with respect to unit count for positive font sizes. *)
Theorem resolve_em_monotonic :
  forall (c1 c2 font_size : R),
    0 < font_size ->
    c1 <= c2 ->
    resolve_em c1 font_size <= resolve_em c2 font_size.
Proof.
  intros c1 c2 font_size Hfs Hle.
  unfold resolve_em.
  apply Rmult_le_compat_r; lra.
Qed.

Theorem resolve_rem_monotonic :
  forall (c1 c2 root_font_size : R),
    0 < root_font_size ->
    c1 <= c2 ->
    resolve_rem c1 root_font_size <= resolve_rem c2 root_font_size.
Proof.
  intros c1 c2 root_font_size Hrfs Hle.
  unfold resolve_rem.
  apply Rmult_le_compat_r; lra.
Qed.
```