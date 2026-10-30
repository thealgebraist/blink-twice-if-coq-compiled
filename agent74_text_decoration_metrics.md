### 1. Core Data Structures in Blink Text Decoration

In Chromium’s Blink layout and paint engine (`third_party/blink/renderer/core/paint/` and `core/style/`), text decoration geometry is mediated by three primary structures that bridge computed CSS styles, platform font metrics, and physical layout coordinates:

*   **`TextDecorationLine` (`ComputedStyleConstants.h`)**: A bitmask enumeration representing the active `text-decoration-line` properties (§2.1):
    *   `kNone = 0x0`, `kUnderline = 0x1`, `kOverline = 0x2`, `kLineThrough = 0x4`, `kBlink = 0x8`, `kSpellingError = 0x10`, `kGrammarError = 0x20`.
*   **`ResolvedUnderlinePosition` (`TextDecorationInfo.h`)**: The resolved geometric policy derived from `text-underline-position` (§2.3) and writing mode / font baseline properties:
    *   `kRoman`: Standard alphabetic baseline placement using font-specified metrics.
    *   `kUnder`: Placed below the em-box / descenders (`text-underline-position: under` or CJK vertical modes).
    *   `kOver`: Placed over the text (used in vertical typographic modes with `text-underline-position: right/left`).
*   **`TextDecorationInfo` (`text_decoration_info.h/.cc`)**: The stateful paint-time calculator instantiated per decorated inline box or text fragment. It aggregates:
    *   `const ComputedStyle& target_style_` and `const Font* font_` (yielding `SimpleFontData` and `FontMetrics`).
    *   `LayoutUnit baseline_` (derived from `font_metrics.Ascent()`).
    *   `TextDecorationThickness` (`from-font`, `auto`, `<length>`, or `<percentage>`).
    *   Cached calculation outputs: `float resolved_thickness_` and line-specific offsets (`UnderlineOffset()`, `OverlineOffset()`, `LineThroughOffset()`).

---

### 2. Underline Thickness Resolution

Per CSS Text Decoration Level 3 §2.2 (and CSS Text Decoration Level 4 `text-decoration-thickness`), Blink computes the stroke thickness in `TextDecorationInfo::ComputeUnderlineThickness`:

1.  **Metric Extraction**: Let $t_{\text{font}} = \text{font\_metrics.UnderlineThickness()}$ and $S = \text{font\_size}$.
2.  **Mode Resolution**:
    *   If `auto`: Blink defaults to the font metric if available, or approximates it as $\max(1.0, S / 14.0)$ (or platform-equivalent heuristic) before rounding.
    *   If `from-font`: Uses $t_{\text{font}}$ if present; falls back to `auto`.
    *   If `<length>` or `<percentage>`: Uses the resolved CSS pixel value $t_{\text{css}}$.
3.  **Floor and Rounding**: To prevent sub-pixel disappearance on low-DPI displays and ensure crisp rasterization when snapping to physical device pixels, the raw thickness $t_{\text{raw}}$ is floored at $1\text{px}$ and rounded:
    $$t_{\text{rounded}} = \max\left(1, \text{round}(t_{\text{raw}})\right)$$
4.  **Upper-Bound Clamping**: To guard against malformed OpenType `post` tables (where `underlineThickness` may exceed the glyph em-box) or extreme layout overflow, Blink clamps the resolved thickness against an upper bound $T_{\max}$ (typically bounded by a multiple of the font's ascent + descent, $H_{\text{em}}$):
    $$T_{\text{resolved}} = \min\left(T_{\max}, \max\left(1, \text{round}(t_{\text{raw}})\right)\right) \quad \text{where } T_{\max} \ge 1$$

---

### 3. Underline Vertical Offset

In Blink's coordinate space (where $y=0$ is the top of the inline box and $+y$ points downward), the alphabetic baseline lies at $B = \text{round}(\text{font\_metrics.Ascent()})$.

`TextDecorationInfo::ComputeUnderlineOffset` resolves the vertical position based on `ResolvedUnderlinePosition` and `text-underline-offset` ($\Delta_{\text{css}}$, defaulting to $0$ for `auto`):

1.  **`kRoman` (Alphabetic / Auto)**:
    *   Let $p_{\text{font}} = \text{font\_metrics.UnderlinePosition()}$ (normalized in Blink so positive values represent distances *below* the baseline).
    *    To prevent the underline stroke from colliding with the alphabetic baseline, Blink enforces a minimum gap $g_{\min} = \max(1, \lfloor T_{\text{resolved}} / 2 \rfloor)$ or $1\text{px}$:
        $$Y_{\text{underline}}^{\text{roman}} = B + \max\left(1, \text{round}(p_{\text{font}}) + \Delta_{\text{css}}\right)$$
2.  **`kUnder` (Descender-clearing)**:
    *   Places the underline below the font's maximum descent $D = \text{round}(\text{font\_metrics.Descent()})$ (where $D \ge 0$) or the ink bounds of the decorated box:
        $$Y_{\text{underline}}^{\text{under}} = B + D + \max\left(0, \Delta_{\text{css}}\right)$$
3.  **Overline Offset (`kOverline`)**:
    *   Positioned at or above the top of the em-box (ascent $B$ above the baseline, so near $y = 0$), adjusted upward by thickness to avoid encroaching on ascenders:
        $$Y_{\text{overline}} = B - \text{ max}(B, \text{ascent} + \Delta_{\text{overline}}) \le B$$

---

### 4. Mathematical Invariants

Auditing Blink’s metric resolution against CSS Text Decoration Level 3 §2 & §3 yields three core invariants:

1.  **Non-Degenerate Visibility (Thickness Lower Bound)**:
    $$\forall M, C.\; \text{ResolveThickness}(M, C) \ge 1$$
    Every active decoration line renders with at least $1$ device pixel of thickness, regardless of zero or negative font table metrics.
2.  **Vertical Monotonic Ordering**:
    Under standard non-negative author offsets ($\Delta_{\text{css}} \ge 0$) and well-formed font metrics ($B \ge 0, D \ge 0$):
    $$Y_{\text{overline}} \le B \le Y_{\text{underline}}$$
    Specifically, in screen coordinates ($+y$ downward), the overline never falls below the alphabetic baseline, and the underline never rises above the alphabetic baseline.
3.  **Pure Functional Determinism**:
    For a fixed `FontMetrics` environment $M$ and `DecorationConfig` $C$, metric resolution is referentially transparent and independent of sibling paint states:
    $$\forall M, C, r_1, r_2.\; \text{EvalMetrics}(M, C) = r_1 \land \text{EvalMetrics}(M, C) = r_2 \implies r_1 = r_2$$

---

### 5. Rocq / Coq Formalization (`BlinkTextDecorationMetricsSemantics.v`)

The following self-contained Rocq (Coq) module formalizes the Blink data structures, resolution algorithms, and proves the three core invariants over integer device-pixel coordinates ($\mathbb{Z}$).

```coq
(** * BlinkTextDecorationMetricsSemantics.v
    Formal Audit of Chromium Blink Text Decoration Metrics vs CSS Text Decoration L3 §2 & §3. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** CSS Text Decoration Level 3 §2.1: text-decoration-line *)
Inductive TextDecorationLine : Type :=
  | LineNone
  | Underline
  | Overline
  | LineThrough
  | SpellingError
  | GrammarError.

(** Blink ResolvedUnderlinePosition (TextDecorationInfo.h) *)
Inductive ResolvedUnderlinePosition : Type :=
  | PosRoman (* Standard alphabetic baseline metric placement *)
  | PosUnder (* Below descenders / em-box *)
  | PosOver. (* Vertical typographic over-placement *)

(** CSS Text Decoration Level 4 / Blink Thickness Specification *)
Inductive ThicknessPolicy : Type :=
  | ThicknessAuto
  | ThicknessFromFont
  | ThicknessExplicit (px : Z).

(** Platform FontMetrics (SimpleFontData / FontMetrics.h)
    All values represent rounded layout/device units in Z. *)
Record FontMetrics : Type := mkFontMetrics {
  fm_ascent              : Z; (* Distance from top of em-box to baseline (>= 0) *)
  fm_descent             : Z; (* Distance from baseline to bottom of em-box (>= 0) *)
  fm_underline_thickness : Z; (* OpenType 'post' table underlineThickness (rounded) *)
  fm_underline_position  : Z; (* Distance below baseline in Blink coords *)
  fm_max_thickness_bound : Z  (* Upper clamp bound, e.g., em-height >= 1 *)
}.

(** Well-formedness predicate for sanitized platform FontMetrics *)
Definition wf_font_metrics (m : FontMetrics) : Prop :=
  fm_ascent m >= 0 /\
  fm_descent m >= 0 /\
  fm_max_thickness_bound m >= 1.

(** Input style configuration for TextDecorationInfo *)
Record TextDecorationConfig : Type := mkTextDecorationConfig {
  tdc_lines              : list TextDecorationLine;
  tdc_underline_pos      : ResolvedUnderlinePosition;
  tdc_thickness_policy   : ThicknessPolicy;
  tdc_underline_offset   : Z; (* Resolved text-underline-offset (>= 0 for standard auto/positive) *)
  tdc_overline_offset    : Z  (* Resolved upward adjustment for overline (>= 0) *)
}.

Definition wf_decoration_config (c : TextDecorationConfig) : Prop :=
  tdc_underline_offset c >= 0 /\
  tdc_overline_offset c >= 0.

(** Computed state of Blink's TextDecorationInfo *)
Record TextDecorationInfo : Type := mkTextDecorationInfo {
  tdi_baseline            : Z;
  tdi_resolved_thickness  : Z;
  tdi_underline_offset    : Z;
  tdi_overline_offset     : Z;
  tdi_linethrough_offset  : Z
}.

(** ** 2. Metric Resolution Semantics *)

(** Clamp value x into [low, high] *)
Definition z_clamp (x low high : Z) : Z :=
  Z.min high (Z.max low x).

(** Blink TextDecorationInfo::ComputeUnderlineThickness:
    Resolves raw thickness, enforces minimum of 1px, and clamps by max bound. *)
Definition resolve_thickness (m : FontMetrics) (policy : ThicknessPolicy) : Z :=
  let raw := match policy with
             | ThicknessAuto       => fm_underline_thickness m
             | ThicknessFromFont   => fm_underline_thickness m
             | ThicknessExplicit v => v
             end in
  z_clamp raw 1 (fm_max_thickness_bound m).

(** Blink TextDecorationInfo::ComputeUnderlineOffset:
    Coordinate system: y = 0 at top of box, +y downwards. Baseline B = fm_ascent m. *)
Definition resolve_underline_offset (m : FontMetrics) (c : TextDecorationConfig) : Z :=
  let B := fm_ascent m in
  match tdc_underline_pos c with
  | PosRoman =>
      (* Enforces at least 1px below baseline when using Roman metrics *)
      let gap := Z.max 1 (fm_underline_position m + tdc_underline_offset c) in
      B + gap
  | PosUnder =>
      (* Placed at or below the font descent *)
      B + fm_descent m + Z.max 0 (tdc_underline_offset c)
  | PosOver =>
      (* Even in PosOver fallback for horizontal audit, clamp to baseline minimum *)
      B + Z.max 0 (tdc_underline_offset c)
  end.

(** Blink Overline Offset:
    Placed at top of ascent (B - fm_ascent = 0) shifted upwards (negative Y) by offset. *)
Definition resolve_overline_offset (m : FontMetrics) (c : TextDecorationConfig) : Z :=
  let B := fm_ascent m in
  B - (fm_ascent m + Z.max 0 (tdc_overline_offset c)).

(** Blink Line-Through Offset:
    Placed at middle of corpus (approximated as B - ascent / 2). *)
Definition resolve_linethrough_offset (m : FontMetrics) : Z :=
  let B := fm_ascent m in
  B - (fm_ascent m / 2).

(** Complete evaluation of TextDecorationInfo *)
Definition compute_text_decoration_info (m : FontMetrics) (c : TextDecorationConfig) : TextDecorationInfo :=
  mkTextDecorationInfo
    (fm_ascent m)
    (resolve_thickness m (tdc_thickness_policy c))
    (resolve_underline_offset m c)
    (resolve_overline_offset m c)
    (resolve_linethrough_offset m).

(** Relational specification of metric evaluation *)
Inductive EvalDecorationMetrics : FontMetrics -> TextDecorationConfig -> TextDecorationInfo -> Prop :=
  | EvalMetrics_Intro : forall m c,
      EvalDecorationMetrics m c (compute_text_decoration_info m c).

(** ** 3. Formal Audit Theorems & Invariants *)

(** Theorem 1: Thickness Lower and Upper Bound Invariant.
    Resolved thickness is strictly >= 1px and <= max_thickness_bound. *)
Theorem thickness_bounds_invariant :
  forall (m : FontMetrics) (c : TextDecorationConfig),
    wf_font_metrics m ->
    1 <= tdi_resolved_thickness (compute_text_decoration_info m c) <= fm_max_thickness_bound m.
Proof.
  intros m c [Hascent [Hdescent Hbound]].
  unfold compute_text_decoration_info, resolve_thickness, z_clamp.
  simpl.
  destruct (tdc_thickness_policy c); lia.
Qed.

(** Corollary 1.1: Thickness is strictly at least 1px regardless of negative/zero font metrics. *)
Corollary thickness_ge_one :
  forall (m : FontMetrics) (c : TextDecorationConfig),
    wf_font_metrics m ->
    tdi_resolved_thickness (compute_text_decoration_info m c) >= 1.
Proof.
  intros m c Hwf.
  pose proof (thickness_bounds_invariant m c Hwf) as [Hlow _].
  lia.
Qed.

(** Theorem 2: Vertical Monotonic Ordering Invariant.
    overline_offset <= baseline <= underline_offset. *)
Theorem vertical_ordering_invariant :
  forall (m : FontMetrics) (c : TextDecorationConfig),
    wf_font_metrics m ->
    wf_decoration_config c ->
    let info := compute_