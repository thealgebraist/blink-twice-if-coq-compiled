# Audit Report: Agent 123 — Chromium Blink Letter/Word Spacing vs. CSS Text Module Level 3 §8

**Target Subsystem:** `third_party/blink/renderer/platform/fonts/shaping/harfbuzz_shaper.cc`, `shape_result.cc`, `shape_result_bloberizer.cc`  
**Specification:** CSS Text Module Level 3, §8.1 (`word-spacing`) & §8.2 (`letter-spacing`)

---

## 1. Tracking Expansion Formula & Boundary Semantics

Per CSS Text 3 §8.2, `letter-spacing` specifies the additional spacing between typographic character units (grapheme clusters). Per §8.1, `word-spacing` specifies additional spacing applied to word-separator characters (U+0020 SPACE, U+00A0 NO-BREAK SPACE, U+1361 ETHIOPIC WORDSPACE, etc.).

### 1.1 The Abstract vs. Concrete Blink Formula
Let a text run consist of $N$ typographic character units ($N \ge 1$) with uniform base advance $W_g$, containing $W_c$ word-separator characters ($0 \le W_c \le N$). Let $S_L$ be `letter-spacing` and $S_W$ be `word-spacing`.

* **Specification Model (CSS Text 3 §8.2):** Tracking is applied *between* adjacent characters and must not be applied at the start or end of a line. This yields the inter-character expansion formula:
  $$\text{TotalWidth}_{\text{spec}} = N \cdot W_g + (N - 1) \cdot S_L + W_c \cdot S_W$$

* **Blink Concrete Implementation (`ShapeResult::ApplySpacingToCopy`):**
  Blink's `RunInfo::ApplySpacing` iterates over all glyph clusters and adds `letter_spacing` unconditionally to the *trailing edge* of every non-cursive, non-zero-width cluster:
  ```cpp
  // shape_result.cc
  float space = font_description.LetterSpacing();
  if (Character::TreatAsSpace(character))
      space += font_description.WordSpacing();
  glyph_data.advance += space;
  ```
  This yields the raw internal Blink formula:
  $$\text{TotalWidth}_{\text{blink\_raw}} = N \cdot W_g + N \cdot S_L + W_c \cdot S_W$$

**Audit Finding 1.1 (Trailing Over-application):** Blink does *not* subtract the final $S_L$ at the end of a line box. Consequently, $\text{TotalWidth}_{\text{blink\_raw}} - \text{TotalWidth}_{\text{spec}} = S_L$. In right-aligned or centered text, or inside shrink-to-fit inline-blocks, Blink leaves a phantom trailing `letter-spacing` advance (tracked upstream in Chromium Issue 40360452). The formalization below models both the CSS boundary-aware formula and Blink's trailing-edge accumulator.

---

## 2. Handling of Negative Spacing, Clamping, and Offsets

CSS Text 3 §8.1 & §8.2 explicitly permit negative values for both `word-spacing` and `letter-spacing`.

### 2.1 Glyph Advance vs. Paint Offset in Blink
When $S_L < 0$ or $S_W < 0$ such that $W_g + S_L + S_W < 0$, the net advance of a single glyph cluster becomes negative.
1. **HarfBuzz Shaping Phase:** HarfBuzz operates in `hb_position_t` (signed `int32_t` in 26.6 fixed-point). Negative advances are preserved during initial shaping.
2. **Blink `ShapeResult` Spacing Phase:** In `ShapeResult`, `HarfBuzzRunGlyphData::advance` is stored as `InlineLayoutUnit` (or `float` depending on the layout path). When `ApplySpacing` executes, `glyph_data.advance` is mutated in-place:
   $$A'_i = A_i + S_L + \mathbb{I}(\text{is\_space}(i)) \cdot S_W$$
   **Blink does not clamp $A'_i$ to $0$.** The advance is permitted to become negative.
3. **Run Width Clamping:** While individual glyph advances can be negative, `ShapeResult::width_` accumulates $\sum A'_i$. If $\sum A'_i < 0$, `InlineItemResult` and `LineBreaker` clamp the layout box inline-size to $0$ at the fragment level (`LayoutUnit::ClampNegativeToZero()`), preventing negative box widths in the layout tree, while the visual ink overflow bounds still reflect the reversed glyph coordinates.
4. **Blobberization (Paint Phase):** In `ShapeResultBloberizer`, cursor advancement is computed via:
   $$\text{offset}_{i+1} = \text{offset}_i + A'_i$$
   Because $A'_i < 0$ is unclamped at the glyph level, the pen position moves backward (to the left in LTR), causing visual overlapping or inversion of glyph order, strictly matching CSS Text 3 requirements.

---

## 3. Monotonicity and Layout Invariants

For a fixed run of $N$ characters ($N \ge 0$) and $W_c$ word separators ($W_c \ge 0$):

1. **Unclamped Monotonicity in $S_L$ and $S_W$:**
   In the exact arithmetic domain ($\mathbb{Z}$ or $\mathbb{Q}$), the total advance function $F(N, W_g, S_L, W_c, S_W)$ has partial derivatives:
   $$\frac{\partial F_{\text{spec}}}{\partial S_L} = \max(0, N - 1) \ge 0, \quad \frac{\partial F_{\text{blink}}}{\partial S_L} = N \ge 0, \quad \frac{\partial F}{\partial S_W} = W_c \ge 0$$
   Since $N - 1 \ge 0$ (for $N \ge 1$) and $W_c \ge 0$, the total advance is non-decreasing (monotonically increasing for $N \ge 2$ and $W_c \ge 1$) with respect to both `letter-spacing` and `word-spacing`.

2. **Clamped Monotonicity Preservation:**
   Let $\text{clamp}_0(x) = \max(0, x)$. Since $x \mapsto \max(0, x)$ is an order-preserving endomorphism on $(\mathbb{Z}, \le)$, applying fragment-level zero-clamping preserves monotonicity with respect to both $S_L$ and $S_W$, whether applied per-glyph or across the total run width.

---

## 4. Formal Verification: `BlinkCSSSpacingSemantics.v`

The following Rocq (Coq) script provides a self-contained, axiom-free formalization of the CSS Text 3 §8 specification model, the Blink `ShapeResult` accumulator model, negative offset progression, and proofs of the monotonicity invariants.

```coq
(** * BlinkCSSSpacingSemantics.v
    Formal Audit of Chromium Blink Letter/Word Spacing vs. CSS Text 3 §8.
    Author: Agent 123 *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

Section CSSSpacingSemantics.

  (** ** 1. Core Definitions and Tracking Formulas *)

  (** Clamp a signed integer value to zero (models LayoutUnit::ClampNegativeToZero) *)
  Definition clamp_zero (x : Z) : Z := Z.max 0 x.

  (** CSS Text 3 §8.2 Specification Formula:
      total_width = N * glyph_w + (N - 1) * letter_spacing + word_count * word_spacing
      Valid for N >= 1. *)
  Definition total_width_spec (N glyph_w letter_spacing word_count word_spacing : Z) : Z :=
    N * glyph_w + (N - 1) * letter_spacing + word_count * word_spacing.

  (** Blink ShapeResult Raw Formula (includes trailing letter-spacing on last cluster):
      total_width = N * glyph_w + N * letter_spacing + word_count * word_spacing *)
  Definition total_width_blink_raw (N glyph_w letter_spacing word_count word_spacing : Z) : Z :=
    N * glyph_w + N * letter_spacing + word_count * word_spacing.

  (** Fragment-level clamped width (models Blink LineBreaker / InlineItemResult) *)
  Definition total_width_spec_clamped (N glyph_w letter_spacing word_count word_spacing : Z) : Z :=
    clamp_zero (total_width_spec N glyph_w letter_spacing word_count word_spacing).

  (** Theorem: Blink's raw width exceeds CSS Spec width by exactly 1 * letter_spacing *)
  Theorem blink_spec_trailing_discrepancy :
    forall N glyph_w ls wc ws : Z,
      total_width_blink_raw N glyph_w ls wc ws - total_width_spec N glyph_w ls wc ws = ls.
  Proof.
    intros N glyph_w ls wc ws.
    unfold total_width_blink_raw, total_width_spec.
    lia.
  Qed.

  (** ** 2. Glyph-Level Stream Model & Negative Offset Handling *)

  (** A character unit in a shaping run is either a standard glyph or a word separator. *)
  Inductive CharKind : Type :=
  | CharStandard : CharKind
  | CharWordSep  : CharKind.

  (** Compute advance for a single glyph cluster in Blink (unclamped). *)
  Definition blink_cluster_advance (glyph_w ls ws : Z) (c : CharKind) : Z :=
    match c with
    | CharStandard => glyph_w + ls
    | CharWordSep  => glyph_w + ls + ws
    end.

  (** Count word separators in a character run. *)
  Fixpoint count_word_seps (run : list CharKind) : Z :=
    match run with
    | [] => 0
    | CharStandard :: rest => count_word_seps rest
    | CharWordSep :: rest  => 1 + count_word_seps rest
    end.

  (** Accumulate total advance across a run of characters (Bloberizer pen progression). *)
  Fixpoint run_advance_blink (glyph_w ls ws : Z) (run : list CharKind) : Z :=
    match run with
    | [] => 0
    | c :: rest => blink_cluster_advance glyph_w ls ws c + run_advance_blink glyph_w ls ws rest
    end.

  (** Lemma: Word separator count is always non-negative. *)
  Lemma count_word_seps_nonneg :
    forall run : list CharKind, 0 <= count_word_seps run.
  Proof.
    induction run as [| [|] rest IH]; simpl; lia.
  Qed.

  (** Theorem: The inductive glyph-by-glyph pen progression in ShapeResultBloberizer
      is algebraically equivalent to the closed-form Blink tracking formula. *)
  Theorem run_advance_matches_blink_formula :
    forall (run : list CharKind) (glyph_w ls ws : Z),
      run_advance_blink glyph_w ls ws run =
      total_width_blink_raw (Z.of_nat (length run)) glyph_w ls (count_word_seps run) ws.
  Proof.
    induction run as [| c rest IH]; intros glyph_w ls ws.
    - simpl. unfold total_width_blink_raw. lia.
    - simpl length. rewrite Nat2Z.inj_succ.
      simpl run_advance_blink. rewrite IH.
      unfold total_width_blink_raw, blink_cluster_advance.
      destruct c; simpl count_word_seps; lia.
  Qed.

  (** ** 3. Monotonicity Invariants *)

  (** Theorem 3.1: Spec total width is monotonic in letter_spacing for fixed N >= 1. *)
  Theorem spec_width_monotonic_letter_spacing :
    forall N glyph_w ls1 ls2 wc ws : Z,
      1 <= N ->
      ls1 <= ls2 ->
      total_width_spec N glyph_w ls1 wc ws <= total_width_spec N glyph_w ls2 wc ws.
  Proof.
    intros N glyph_w ls1 ls2 wc ws HN Hls.
    unfold total_width_spec.
    assert (H1: 0 <= N - 1) by lia.
    assert (H2: (N - 1) * ls1 <= (N - 1) * ls2) by (apply Z.mul_le_mono_nonneg_l; lia).
    lia.
  Qed.

  (** Theorem 3.2: Spec total width is strictly monotonic in letter_spacing for N >= 2. *)
  Theorem spec_width_strict_monotonic_letter_spacing :
    forall N glyph_w ls1 ls2 wc ws : Z,
      2 <= N ->
      ls1 < ls2 ->
      total_width_spec N glyph_w ls1 wc ws < total_width_spec N glyph_w ls2 wc ws.
  Proof.
    intros N glyph_w ls1 ls2 wc ws HN Hls.
    unfold total_width_spec.
    assert (H1: 0 < N - 1) by lia.
    assert (H2: (N - 1) * ls1 < (N - 1) * ls2) by (apply Z.mul_lt_mono_pos_l; lia).
    lia.
  Qed.

  (** Theorem 3.3: Spec total width is monotonic in word_spacing for wc >= 0. *)
  Theorem spec_width_monotonic_word_spacing :
    forall N glyph_w ls wc ws1 ws2 : Z,
      0 <= wc ->
      ws1 <= ws2 ->
      total_width_spec N glyph_w ls wc ws1 <= total_width_spec N glyph_w ls wc ws2.
  Proof.
    intros N glyph_w ls wc ws1 ws2 Hwc Hws.
    unfold total_width_spec.
    assert (H: wc * ws1 <= wc * ws2) by (apply Z.mul_le_mono_nonneg_l; lia).
    lia.
  Qed.

  (** Theorem 3.4: Joint Monotonicity in (letter_spacing, word_spacing) for Spec Formula. *)
  Theorem spec_width_joint_monotonic :
    forall N glyph_w ls1 ls2 wc ws1 ws2 : Z,
      1 <= N ->
      0 <= wc ->
      ls1 <= ls2 ->
      ws1 <= ws2 ->
      total_width_spec N glyph_w ls1 wc ws1 <= total_width_spec N glyph_w ls2 wc ws2.
  Proof.
    intros N glyph_w ls1 ls2 wc ws1 ws2 HN Hwc Hls Hws.
    