# Formal Verification Report: Blink Line Box Half-Leading Distribution and Strut Accumulation

**Agent ID**: 682 (W3C/WHATWG Layout Rules & Blink LayoutNG Verification)  
**Target Component**: `third_party/blink/renderer/core/layout/inline/line_box_fragment_builder.cc`  
**Specification**: CSS 2.1 §10.8.1 Leading and half-leading; CSS Inline Layout Module Level 3  
**Formal Artifact**: `BlinkLineBoxHalfLeadingDistributionSemantics.v`  

---

## 1. Normative W3C Specification Requirements

According to **CSS 2.1 §10.8 Line height calculations: the `'line-height'` and `'vertical-align'` properties** and **§10.8.1 Leading and half-leading**, the height of a line box is determined by the vertical alignment and computed heights of the inline-level boxes it contains, initialized by an imaginary zero-width inline box known as the **strut**.

### 1.1 Half-Leading Calculation
For an inline non-replaced element (and the root inline box / strut), the user agent calculates the font's intrinsic metric height:
$$H_{\text{font}} = A_{\text{font}} + D_{\text{font}}$$
where $A_{\text{font}}$ is the typographical ascender height above the baseline and $D_{\text{font}}$ is the typographical descender depth below the baseline.

Given a computed `'line-height'` value $L$, the **leading** $\Delta L$ is the difference between the computed line height and the intrinsic font height:
$$\Delta L = L - H_{\text{font}} = L - (A_{\text{font}} + D_{\text{font}})$$

The specification dictates that this leading is split equally above and below the content area as **half-leading**:
$$\text{half\_leading} = \frac{\Delta L}{2} = \frac{L - (A_{\text{font}} + D_{\text{font}})}{2}$$

Adding the half-leading to the intrinsic font metrics yields the effective layout ascent ($A_{\text{eff}}$) and descent ($D_{\text{eff}}$) of the inline box:
$$A_{\text{eff}} = A_{\text{font}} + \text{half\_leading}$$
$$D_{\text{eff}} = D_{\text{font}} + \text{half\_leading}$$

Note that $\Delta L$ may be negative if $L < H_{\text{font}}$, resulting in negative half-leading and an inline box whose logical height is smaller than its content area.

### 1.2 The Strut and Line Box Metric Accumulation
Per CSS 2.1 §10.8.1:
> *"On a block container element whose content is composed of inline-level elements, 'line-height' specifies the minimal height of line boxes within the element. The minimum height consists of a minimum height above the baseline and a minimum depth below it, exactly as if each line box starts with a zero-width inline box with the element's font and line height properties. We call that imaginary box a 'strut'."*

When accumulating a sequence of aligned inline-level children $C_1, C_2, \dots, C_n$ (each positioned with baseline-relative ascent $A_i$ and descent $D_i$ after applying `vertical-align` shifts), the total line box metrics $(A_{\text{line}}, D_{\text{line}})$ are determined by the supremum over the strut $(A_{\text{strut}}, D_{\text{strut}})$ and all inline children:
$$A_{\text{line}} = \max\left(A_{\text{strut}}, \max_{1 \le i \le n} A_i\right)$$
$$D_{\text{line}} = \max\left(D_{\text{strut}}, \max_{1 \le i \le n} D_i\right)$$
$$H_{\text{line}} = A_{\text{line}} + D_{\text{line}}$$

---

## 2. Chromium Blink Implementation Details & Invariants

In Chromium Blink's LayoutNG architecture, line box metrics are represented by `FontHeight` (`third_party/blink/renderer/platform/fonts/shaping/font_height.h`) and accumulated during inline layout inside `LineBoxFragmentBuilder` (`third_party/blink/renderer/core/layout/inline/line_box_fragment_builder.cc`) and its helper routines in `InlineLayoutAlgorithm` / `InlineBoxState`.

### 2.1 Fixed-Point Representation (`LayoutUnit`)
Blink represents subpixel layout coordinates using `LayoutUnit`, a 32-bit signed fixed-point integer with 6 fractional bits ($\frac{1}{64}$th of a CSS pixel). All arithmetic operations on `FontHeight::ascent` and `FontHeight::descent` operate over $\mathbb{Z}$ (scaled by 64).

When splitting an odd integer leading $\Delta L \in \mathbb{Z}$ in `FontHeight` / `ComputedStyle::ComputedLineHeight`, integer division truncates toward zero (or rounds via `LayoutUnit` division):
```cpp
LayoutUnit leading = line_height - (ascent + descent);
LayoutUnit half_leading = leading / 2;
ascent += half_leading;
descent = line_height - ascent; // Preserves exact line_height sum in integer arithmetic, or both += half_leading
```
In pure rational / even-unit arithmetic (and specification semantics), both ascent and descent receive exact `half_leading`, whereas in discrete fixed-point `LayoutUnit` arithmetic, Blink ensures either symmetric truncation `ascent += leading / 2; descent += leading - leading / 2;` or symmetric half-leading distribution. In our formalization below, we model both the **Exact Spec Domain** (where leading is evenly divisible or scaled by 2) and the **Discrete `LayoutUnit` Integer Domain** (modeling truncation and remainder preservation).

### 2.2 `LineBoxFragmentBuilder` and `FontHeight::Unite`
In `line_box_fragment_builder.cc`:
```cpp
void LineBoxFragmentBuilder::SetMetrics(const FontHeight& metrics) {
  metrics_ = metrics;
}
```
During line box construction (`InlineLayoutStateStack::OnOpenTag` and `ComputeLineBoxMetrics`), the builder's `metrics_` starts with the block container's **strut metrics** (computed from the root inline box's font and `line-height` via half-leading distribution). As each inline child fragment is added, its baseline-shifted `FontHeight` is united with the running line box metrics via `FontHeight::Unite`:
```cpp
void FontHeight::Unite(const FontHeight& other) {
  if (other.IsEmpty())
    return;
  if (IsEmpty()) {
    *this = other;
    return;
  }
  ascent = std::max(ascent, other.ascent);
  descent = std::max(descent, other.descent);
}
```
Finally, `LineBoxFragmentBuilder::CreateLineBoxFragment()` sets the physical/logical block-size of the line box fragment to `metrics_.LineHeight()` (which computes `ascent + descent`, clamped to $\ge 0$ when converted to physical fragment size if necessary).

### 2.3 Core Implementation Invariants
1. **Half-Leading Additive Identity**: When leading is distributed, $A_{\text{eff}} = A_{\text{font}} + \lfloor \Delta L / 2 \rfloor$ and $D_{\text{eff}} = D_{\text{font}} + (\Delta L - \lfloor \Delta L / 2 \rfloor)$ (and for even $\Delta L$, both equal $+ \Delta L / 2$), guaranteeing $A_{\text{eff}} + D_{\text{eff}} = L$.
2. **Strut Dominance Lower Bound**: For any sequence of non-empty inline items accumulated into a line box initialized with a non-empty strut, the final line box ascent is $\ge A_{\text{strut}}$, final descent is $\ge D_{\text{strut}}$, and total line box height is $\ge L_{\text{strut}}$.
3. **Commutativity, Associativity, and Idempotence of Metric Accumulation**: `FontHeight::Unite` forms a join-semilattice over non-empty `FontHeight` records, ensuring that child order does not affect vertical line box extent.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained, and admitted-free Rocq/Coq formalization (`BlinkLineBoxHalfLeadingDistributionSemantics.v`). It models both the exact CSS 2.1 specification equation ($A = A_f + \text{hl}, D = D_f + \text{hl}$) and Blink's discrete `LayoutUnit` rounding/accumulation semantics in `line_box_fragment_builder.cc`.

```coq
(** * BlinkLineBoxHalfLeadingDistributionSemantics.v
    Formal verification of W3C CSS 2.1 §10.8.1 Half-Leading Distribution
    and Strut Metric Accumulation in Chromium Blink's LineBoxFragmentBuilder. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Data Types and Font Metrics Representation *)

(** In Blink, LayoutUnit is a signed 32-bit fixed-point value (1/64px).
    We model LayoutUnit as an arbitrary-precision integer Z. *)
Definition LayoutUnit := Z.

(** [FontHeight] represents Blink's [blink::FontHeight] structure
    (third_party/blink/renderer/platform/fonts/shaping/font_height.h).
    An empty FontHeight in Blink is represented either by a sentinel or
    tracked via an explicit emptiness flag during box tree accumulation. *)
Record FontHeight : Type := mkFontHeight {
  ascent : LayoutUnit;
  descent : LayoutUnit;
  is_empty : bool
}.

(** Intrinsic font metrics together with a computed line-height property. *)
Record InlineBoxStyle : Type := mkInlineBoxStyle {
  font_ascent : LayoutUnit;
  font_descent : LayoutUnit;
  computed_line_height : LayoutUnit
}.

(** Total height of a [FontHeight] metric pair (Blink's [FontHeight::LineHeight()]). *)
Definition font_height_total (fh : FontHeight) : LayoutUnit :=
  if is_empty fh then 0 else ascent fh + descent fh.

(** ** 2. Half-Leading Distribution Semantics (CSS 2.1 §10.8.1) *)

(** Intrinsic font height: A_font + D_font *)
Definition intrinsic_font_height (s : InlineBoxStyle) : LayoutUnit :=
  font_ascent s + font_descent s.

(** Total leading: L - (A_font + D_font) *)
Definition total_leading (s : InlineBoxStyle) : LayoutUnit :=
  computed_line_height s - intrinsic_font_height s.

(** Pure CSS 2.1 §10.8.1 exact half-leading formula:
    half_leading = (line_height - font_height) / 2
    ascent = font_ascent + half_leading
    descent = font_descent + half_leading *)
Definition half_leading (s : InlineBoxStyle) : LayoutUnit :=
  (computed_line_height s - intrinsic_font_height s) / 2.

Definition apply_exact_half_leading (s : InlineBoxStyle) : FontHeight :=
  let hl := half_leading s in
  mkFontHeight (font_ascent s + hl) (font_descent s + hl) false.

(** Blink's discrete LayoutUnit half-leading distribution where odd subpixel
    leading remainders are preserved so that ascent + descent == line_height. *)
Definition apply_discrete_half_leading (s : InlineBoxStyle) : FontHeight :=
  let leading := total_leading s in
  let hl_ascent := leading / 2 in
  let hl_descent := leading - hl_ascent in
  mkFontHeight (font_ascent s + hl_ascent) (font_descent s + hl_descent) false.

(** ** 3. Strut & LineBoxFragmentBuilder Accumulation Semantics *)

(** Blink's [FontHeight::Unite(const FontHeight& other)] used throughout
    inline layout and finalized in [LineBoxFragmentBuilder::SetMetrics]. *)
Definition font_height_unite (a b : FontHeight) : FontHeight :=
  if is_empty b then a
  else if is_empty a then b
  else mkFontHeight (Z.max (ascent a) (ascent b))
                    (Z.max (descent a) (descent b))
                    false.

(** Apply a baseline shift (from CSS [vertical-align]) to a child's metrics.
    In Blink's [FontHeight::Move(LayoutUnit)], shifting a box upward by [offset]
    increases its ascent by [offset] and decreases its descent by [offset]
    (or vice-versa depending on coordinate sign). *)
Definition font_height_move (fh : FontHeight) (baseline_shift : LayoutUnit) : FontHeight :=
  if is_empty fh then fh
  else mkFontHeight (ascent fh + baseline_shift)
                    (descent fh - baseline_shift)
                    false.

(** Accumulate a list of inline child metrics over an initial strut metric
    to produce the final metrics stored in [LineBoxFragmentBuilder::metrics_]. *)
Definition accumulate_line_box_metrics
  (strut : FontHeight) (children : list FontHeight) : FontHeight :=
   fold_left font_height_unite children strut.

(** State of [LineBoxFragmentBuilder] relevant to vertical block-size calculation. *)
Record LineBoxFragmentBuilder : Type := mkLineBoxFragmentBuilder {
  builder_metrics : FontHeight;
  builder_line_box_block_size : LayoutUnit
}.

(** Build the final line box fragment state from a strut style and inline children. *)
Definition build_line_box_fragment
  (strut_style : InlineBoxStyle)
  (children : list FontHeight) : LineBoxFragmentBuilder :=
  let strut := apply_exact_half_leading strut_style in
  let final_metrics := accumulate_line_box_metrics strut children in
  mkLineBoxFragmentBuilder final_metrics (font_height_total final_metrics).
```

---

## 4. Concrete Theorems and Complete Mechanized Proofs

We now state and prove the core functional correctness theorems establishing the mathematical properties required by CSS 2.1 §10.8.1 and Blink's `line_box_fragment_builder.cc`.

```coq
(** ** 4. Formal Verification Theorems and Proofs *)

(** Theorem 1: CSS 2.1 §10.8.1 Exact Half-Leading Decomposition
    Proves the fundamental specification property:
    ascent = font_ascent + half_leading /\ descent = font_descent + half_leading. *)
Theorem css21_half_leading_decomposition :
  forall (s : InlineBoxStyle),
    let fh := apply_exact_half_leading s in
    let hl := (computed_line_height s - (font_ascent s + font_descent s)) / 2 in
    ascent fh = font_ascent s + hl /\
    descent fh = font_descent s + hl /\
    is_empty fh = false.
Proof.
  intros s fh