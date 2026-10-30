### 1. Core Data Structures in Chromium Blink

In Chromium's Blink rendering engine, font metrics bridge low-level typographic tables (`OS/2`, `hhea`, `hmtx` parsed via Skia/HarfBuzz) and the CSS Inline Layout engine (LayoutNG). 

#### `FontMetrics` (`third_party/blink/renderer/platform/fonts/font_metrics.h`)
The foundational container for raw and adjusted typographic metrics scaled to the font's pixel size.
*   **Primary Fields**: `ascent_` ($A$), `descent_` ($D$), `line_gap_` ($LG$), `line_spacing_` ($LS$), `x_height_` ($xH$), `cap_height_` ($CH$), `units_per_em_` ($UPEM$).
*   **Fixed-Point representations**: Maintains both floating-point (`float`) and subpixel layout representations (`LayoutUnit`, which uses 1/64th pixel precision, and integer `int` rounded metrics).
*   **Ascent/Descent Quirks**: Implements `Ascent(FontBaseline)` and `Descent(FontBaseline)`. For `kIdeographicBaseline` or `kAlphabeticBaseline`, it adjusts distribution based on platform-specific table rules (e.g., preferring `OS/2` `sTypoAscender` if `USE_TYPO_METRICS` is set, otherwise falling back to `usWinAscent` or `hhea` `Ascender`).

#### `SimpleFontData` (`third_party/blink/renderer/platform/fonts/simple_font_data.h`)
Represents a single, realized physical font face at a specific size and orientation.
*   Owns an instance of `FontMetrics` (`font_metrics_`).
*   **`PlatformInit()`**: Queries the underlying `SkFont` to populate `FontMetrics`. It extracts `SkFontMetrics`, resolves font table presence, and triggers metric synthesis when metrics are missing or zeroed.

#### `FontHeight` (`third_party/blink/renderer/platform/fonts/font_height.h`)
The LayoutNG value type representing the vertical extent of an inline box relative to its dominant baseline.
*   **Fields**: `LayoutUnit ascent`, `LayoutUnit descent`.
*   **Semantics**: Unlike `FontMetrics` (which stores intrinsic font values), `FontHeight` represents the *box extent* during inline layout.
*   **Operations**:
    *   `LineHeight() = ascent + descent`.
    *   `Unite(const FontHeight& other)`: Computes $\max(\text{ascent}_1, \text{ascent}_2)$ and $\max(\text{descent}_1, \text{descent}_2)$ to grow the line box or inline box to encompass child glyphs/boxes.
    *   `AddLeading(LayoutUnit line_height)`: Distributes half-leading into `ascent` and `descent` in-place.

---

### 2. Synthesized Metrics: Blink vs. W3C CSS Specifications

When fonts lack specific tables (e.g., `OS/2` Version $< 2$ missing `sxHeight` and `sCapHeight`) or contain malformed values ($\le 0$), both W3C specifications (CSS Fonts Level 4 / CSS Inline Layout Module Level 3) and Blink prescribe fallback synthesis.

| Metric | W3C CSS Specification (Fonts 4 / Inline 3) | Chromium Blink Implementation (`SimpleFontData`) | Audit / Divergence |
| :--- | :--- | :--- | :--- |
| **x-height** (`ex`) | 1. Use `sxHeight` from `OS/2`.<br>2. Measure bounding box of glyph `'x'` (U+0078).<br>3. Fallback to $0.5 \times \text{em}$. | 1. Uses Skia `fXHeight` (from `OS/2`).<br>2. Measures Skia glyph bounds for `'x'`.<br>3. Fallback: $0.5 \times \text{ascent}$ (or $0.5 \times \text{size}$ if ascent $\le 0$). | **Divergence**: If `'x'` glyph is missing, Blink falls back to $0.5 \times A$ rather than $0.5 \times \text{em}$ (`font_size`). |
| **cap-height** (`cap`) | 1. Use `sCapHeight` from `OS/2`.<br>2. Measure bounding box of glyph `'O'` (U+004F).<br>3. Fallback to `ascent`. | 1. Uses Skia `fCapHeight` (from `OS/2`).<br>2. Measures glyph `'H'` or `'O'` (via Skia).<br>3. Fallback: Returns `FloatAscent()` ($A$). | **Aligned**: Both resolve to the font's ascent ($A$) as the ultimate fallback. |
| **line-gap** (Normal Line Height) | If `line-height: normal`, use $A + D + LG$ from font tables (`hhea` or `OS/2`). | `line_spacing_ = lroundf(ascent) + lroundf(descent) + lroundf(line_gap)`. If `line_gap < 0`, clamped to $0$ on specific platforms. | **Subpixel Rounding**: Blink rounds $A$, $D$, and $LG$ to integers *before* summing for `line_spacing_` in legacy paths, though `FontHeight` preserves `LayoutUnit` (1/64 px). |
| **Baseline Offsets** | **Alphabetic**: $0$.<br>**Central**: $\frac{A - D}{2}$.<br>**Ideographic-Under**: $-D$.<br>**Hanging**: $0.8 \times A$ (or `bsln` / `BASE` table). | Computed in `FontMetrics::Ascent(baseline)`:<br>**Alphabetic**: $A_{\text{alphabetic}} = A$, $D_{\text{alphabetic}} = D$.<br>**Central**: $A_{\text{central}} = \frac{A + D}{2}$, $D_{\text{central}} = (A+D) - A_{\text{central}}$. | **Implicit Baseline**: Instead of returning an explicit offset $Y$, Blink shifts the effective `ascent` and `descent` returned by `GetFontHeight(baseline)` so the baseline sits at $0$. |

---

### 3. Half-Leading Distribution Mechanics

In CSS Inline 3 § 4.2 (Leading and Half-Leading), the difference between the computed `line-height` ($LH$) and the text metric extent ($A + D$) is the **leading** ($L$). It is split equally above and below the text bounds.

#### Mathematical Formulation (Exact Real Arithmetic)
$$L = LH - (A + D)$$
$$\frac{L}{2} = \frac{LH - (A + D)}{2}$$
$$A' = A + \frac{L}{2}, \quad D' = D + \frac{L}{2}$$

#### Blink Fixed-Point Implementation (`FontHeight::AddLeading`)
Because Blink uses 64ths of a pixel (`LayoutUnit`) or integers, dividing an odd leading value by 2 causes truncation. To maintain the invariant $A' + D' = LH$, Blink does not compute $L/2$ twice. Instead, it computes `half_leading` once and assigns the remainder to `descent`:

```cpp
// third_party/blink/renderer/platform/fonts/font_height.cc
LayoutUnit half_leading = (line_height - (ascent + descent)) / 2; // Truncates towards 0
ascent += half_leading;
descent = line_height - ascent; // Absorbs any odd-unit remainder
```

---

### 4. Mathematical Invariants

1.  **Conservation of Line Height (Exact Partitioning)**:
    $$\forall A, D, LH \in \mathbb{Z}, \quad A' + D' = LH$$
    Even under integer or fixed-point division truncation where $\lfloor L/2 \rfloor + \lfloor L/2 \rfloor \neq L$, the remainder absorption (`descent = line_height - ascent`) guarantees exact conservation.
2.  **Intrinsic Non-Negativity**:
    For well-formed normalized metrics:
    $$A \ge 0 \quad \land \quad D \ge 0 \quad \land \quad LG \ge 0$$
    *(Note: While raw font tables store descent as a negative number in `OS/2` `sTypoDescender`, Blink normalizes `descent_` to be a positive distance below the baseline upon ingestion).*
3.  **Line Height Non-Negativity**:
    Per CSS Inline 3, negative `line-height` values are illegal at parse time:
    $$LH \ge 0$$
    *(Note: If $0 \le LH < A + D$, then $L < 0$, which can produce $A' < 0$ or $D' < 0$. However, their sum $A' + D'$ remains strictly $\ge 0$).*
4.  **Determinism**:
    Metric synthesis and leading distribution are pure functions of the input font table record, platform flags, and target `line_height`.

---

### 5. Formalization in Rocq / Coq (`BlinkFontMetricsSemantics.v`)

The following standalone Coq script formalizes Blink's `LayoutUnit` (modeled over $\mathbb{Z}$), raw vs. synthesized metrics, baseline shifting, half-leading distribution, and proves the core invariants.

```coq
(** * BlinkFontMetricsSemantics.v
    Formal verification of Chromium Blink Font Metrics against W3C CSS Fonts 4 & Inline 3.
    Agent 41 Audit Artifact. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** Blink's LayoutUnit is a 32-bit fixed-point value (1/64th pixel). 
    We model it over Z to capture exact fixed-point quantization and truncation. *)
Definition LayoutUnit := Z.

Inductive FontBaseline : Type :=
  | AlphabeticBaseline
  | IdeographicBaseline
  | CentralBaseline
  | HangingBaseline.

(** Represents raw data extracted from OpenType/TrueType tables (OS/2, hhea, glyf).
    Optional fields represent tables or glyphs that may be missing or zeroed. *)
Record RawFontTables : Type := mkRawFontTables {
  raw_ascent       : LayoutUnit;
  raw_descent      : LayoutUnit; (* Normalized magnitude; may be < 0 if malformed *)
  raw_line_gap     : LayoutUnit;
  raw_x_height     : option LayoutUnit;
  glyph_x_bounds   : option LayoutUnit;
  raw_cap_height   : option LayoutUnit;
  glyph_O_bounds   : option LayoutUnit;
  font_size        : LayoutUnit
}.

(** Blink's [FontMetrics] after synthesis and normalization in [SimpleFontData::PlatformInit]. *)
Record FontMetrics : Type := mkFontMetrics {
  fm_ascent       : LayoutUnit;
  fm_descent      : LayoutUnit;
  fm_line_gap     : LayoutUnit;
  fm_line_spacing : LayoutUnit;
  fm_x_height     : LayoutUnit;
  fm_cap_height   : LayoutUnit
}.

(** Blink's [FontHeight] (third_party/blink/renderer/platform/fonts/font_height.h) *)
Record FontHeight : Type := mkFontHeight {
  fh_ascent  : LayoutUnit;
  fh_descent : LayoutUnit
}.

Definition fh_line_height (fh : FontHeight) : LayoutUnit :=
  fh_ascent fh + fh_descent fh.

(** ** 2. Synthesized Metrics Semantics *)

(** Helper: Clamps negative raw metric magnitudes to 0. *)
Definition clamp_non_neg (v : LayoutUnit) : LayoutUnit :=
  Z.max 0 v.

(** Blink x-height synthesis:
    1. Explicit OS/2 sxHeight (if > 0)
    2. Measured 'x' glyph bounding box (if > 0)
    3. Fallback: 0.5 * ascent (if ascent > 0) else 0.5 * font_size *)
Definition synthesize_x_height (raw : RawFontTables) (norm_ascent : LayoutUnit) : LayoutUnit :=
  match raw_x_height raw with
  | Some xh => if xh >? 0 then xh else
               match glyph_x_bounds raw with
               | Some gx => if gx >? 0 then gx else (norm_ascent / 2)
               | None => (norm_ascent / 2)
               end
  | None => match glyph_x_bounds raw with
            | Some gx => if gx >? 0 then gx else (norm_ascent / 2)
            | None => if norm_ascent >? 0 
                      then norm_ascent / 2 
                      else (clamp_non_neg (font_size raw)) / 2
            end
  end.

(** W3C CSS Fonts 4 x-height synthesis (diverges on final fallback: uses 0.5 * em/font_size) *)
Definition w3c_synthesize_x_height (raw : RawFontTables) : LayoutUnit :=
  match raw_x_height raw with
  | Some xh => if xh >? 0 then xh else (clamp_non_neg (font_size raw)) / 2
  | None => match glyph_x_bounds raw with
            | Some gx => if gx >? 0 then gx else (clamp_non_neg (font_size raw)) / 2
            | None => (clamp_non_neg (font_size raw)) / 2
            end
  end.

(** Cap-height synthesis (Aligned between Blink and W3C: falls back to ascent) *)
Definition synthesize_cap_height (raw : RawFontTables) (norm_ascent : LayoutUnit) : LayoutUnit :=
  match raw_cap_height raw with
  | Some ch => if ch >? 0 then ch else norm_ascent
  | None => match glyph_O_bounds raw with
            | Some go => if go >? 0 then go else norm_ascent
            | None => norm_ascent
            end
  end.

(** Complete initialization of [FontMetrics] from [RawFontTables] *)
Definition platform_init_metrics (raw : RawFontTables) : FontMetrics :=
  let a  := clamp_non_neg (raw_ascent raw) in
  let d  := clamp_non_neg (raw_descent raw) in
  let lg := clamp_non_neg (raw_line_gap raw) in
  let ls := a + d + lg in
  let xh := synthesize_x_height raw a in
  let ch := synthesize_cap_height raw a in
  mkFontMetrics a d lg ls xh ch.

(** Baseline-adjusted FontHeight extraction ([SimpleFontData::GetFontHeight]) *)
Definition get_font_height (fm : FontMetrics) (b : FontBaseline) : FontHeight :=
  let a := fm_ascent fm in
  let d := fm_descent fm in
  match b with
  | AlphabeticBaseline => mkFontHeight a d
  | IdeographicBaseline => mkFontHeight a d
  | CentralBaseline =>
      let total := a + d in
      let central_a