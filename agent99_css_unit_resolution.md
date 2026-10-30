Here is the formal architectural audit and Rocq/Coq specification for Chromium Blink’s CSS Length Unit Conversion engine against **CSS Values and Units Module Level 4 (§5 Distance Units: the `<length>` type)**.

---

### 1. Core Data Structures in Blink Length Resolution

In Chromium Blink (`third_party/blink/renderer/core/css/` and `platform/geometry/`), CSS lengths transition from parsed AST tokens into layout-ready fixed-point representations through three core structures:

1. **`LayoutUnit` (`platform/geometry/layout_unit.h`)**:
   * **Representation**: A 32-bit signed fixed-point integer with `kLayoutUnitFractionalBits = 6`.
   * **Scale Factor**: $2^6 = 64$ (`kFixedPointDenominator`). One CSS pixel (`1px`) equals $64$ internal units.
   * ** quantization & Clamping**: Represents values in the interval $[-2^{25}, 2^{25} - \frac{1}{64}]$ with a resolution of $\frac{1}{64}\text{px}$ ($0.015625\text{px}$). Operations use saturating arithmetic (`ClampTo<int>`).

2. **`FontDescription` (`platform/fonts/font_description.h`)**:
   * **Role**: Holds the typographic metrics of a `ComputedStyle`.
   * **Key Fields**: `computed_size_` (float, in CSS pixels) and `specified_size_` (float). During length conversion, `ComputedPixelSize()` provides the resolved scalar reference for `em` and `rem` evaluations, which is subsequently quantized into `LayoutUnit` space.

3. **`CSSToLengthConversionData` (`core/css/css_to_length_conversion_data.h`)**:
   * **Role**: The immutable evaluation context (environment) passed into `CSSPrimitiveValue::ConvertToLength()`.
   * **Sub-structures**:
     * `FontSizes`: Caches `em_` (current element's `FontDescription::ComputedPixelSize()`) and `rem_` (root `<html>` element's `ComputedPixelSize()`).
     * `ViewportSize`: Stores viewport dimensions (`vw`, `vh`, etc.).
     * `ContainerSizes`: Stores query container dimensions (`cqw`, `cqh`, etc.).
     * `zoom_`: Floating-point page/element zoom factor ($\ge 0$).

---

### 2. Resolution Rules (CSS Values 4 §5 vs. Blink Fixed-Point)

In the formal verification model, we align raw floating-point inputs with Blink's fixed-point `LayoutUnit` domain (where $1\text{ unit} = \frac{1}{64}\text{px}$, and input scalars $v$ are pre-scaled by $64$).

* **Absolute Pixels (`px` — CSS Values 4 §5.2)**:
  $$\text{Resolve}(\text{px}(v), \mathcal{E}) = v \times 64$$
  *(If $v$ is already given in fixed-point $1/64\text{th}$ increments, $\text{Resolve}(\text{px}(v_{\text{fp}})) = v_{\text{fp}}$).*

* **Font-Relative `em` (CSS Values 4 §5.1.1)**:
  Resolved against the computed `font-size` of the element on which it is used (or parent, if used inside `font-size` itself; handled by environment construction):
  $$\text{Resolve}(\text{em}(v_{\text{fp}}), \mathcal{E}) = \left\lfloor \frac{v_{\text{fp}} \times \mathcal{E}.\text{em\_size}_{\text{fp}}}{64} \right\rfloor$$

* **Root Font-Relative `rem` (CSS Values 4 §5.1.1)**:
  Resolved against the computed `font-size` of the root element (`<html>`). If unconfigured, the specification and Blink default to $16\text{px} = 16 \times 64 = 1024\text{ LayoutUnits}$:
  $$\text{Resolve}(\text{rem}(v_{\text{fp}}), \mathcal{E}) = \left\lfloor \frac{v_{\text{fp}} \times \mathcal{E}.\text{rem\_size}_{\text{fp}}}{64} \right\rfloor$$

* **Percentages (`%` — CSS Values 4 §5.4 / `<length-percentage>`)**:
  Resolved during box layout (`MinimumValueForLength`) against a directional reference box dimension $R_{\text{fp}}$ (e.g., containing block width/height in `LayoutUnit`s). For a percentage $p_{\text{fp}}$ (where $100\% = 100 \times 64 = 6400$):
  $$\text{Resolve}(\text{pct}(p_{\text{fp}}), R_{\text{fp}}) = \left\lfloor \frac{p_{\text{fp}} \times R_{\text{fp}}}{100 \times 64} \right\rfloor = \left\lfloor \frac{p_{\text{fp}} \times R_{\text{fp}}}{6400} \right\rfloor$$

---

### 3. Mathematical Invariants

1. **Non-Negativity Preservation**:
   For any well-formed conversion environment $\mathcal{E}$ (where $\mathcal{E}.\text{em} \ge 0$, $\mathcal{E}.\text{rem} \ge 0$, and $\mathcal{E}.\text{ref} \ge 0$), any CSS length with a non-negative scalar magnitude $v \ge 0$ resolves to a non-negative `LayoutUnit` ($\ge 0$).
2. **Exact Fixed-Point Scaling (`1em` / `1rem` / `100%` Identity)**:
   Evaluating $1\text{em}$ ($v_{\text{fp}} = 64$) yields the exact `LayoutUnit` representation of the environment's `em` font size. Evaluating $1\text{rem}$ under default root settings yields exactly $1024$ `LayoutUnit`s ($16\text{px}$). Evaluating $100\%$ ($p_{\text{fp}} = 6400$) yields the exact reference container size $R_{\text{fp}}$.
3. **Positive Font-Size Monotonicity**:
   For a fixed non-negative length scalar $v_{\text{fp}} \ge 0$, if environment $\mathcal{E}_1$ has a smaller or equal `em` size than $\mathcal{E}_2$ ($0 \le \mathcal{E}_1.\text{em} \le \mathcal{E}_2.\text{em}$), then $\text{Resolve}(\text{em}(v_{\text{fp}}), \mathcal{E}_1) \le \text{Resolve}(\text{em}(v_{\text{fp}}), \mathcal{E}_2)$.

---

### 4. Formalization in Rocq / Coq (`BlinkCSSUnitResolutionSemantics.v`)

Below is the self-contained, fully proven Rocq/Coq specification encoding these structures, resolution semantics, and invariants.

```coq
(** * BlinkCSSUnitResolutionSemantics.v
    Formalization of Chromium Blink CSS Length Unit Conversion
    against W3C CSS Values and Units Module Level 4 (Section 5).
    Author: Agent 99
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
Open Scope Z_scope.

(** ** 1. Core Data Structures *)

(** Blink LayoutUnit uses a 6-bit fractional fixed-point representation. *)
Definition kLayoutUnitDenominator : Z := 64.

(** Default root (<html>) font-size is 16px = 16 * 64 = 1024 LayoutUnits. *)
Definition kDefaultRootFontSize : Z := 16 * kLayoutUnitDenominator.

(** Type alias for values stored in LayoutUnit (1/64th pixel increments). *)
Definition LayoutUnit := Z.

(** Representation of CSS Length and Length-Percentage AST tokens.
    - [CSS_Px v]: [v] is an integer pixel count (or pre-scaled; here we model
      both raw integer pixels and fixed-point 1/64th scalar inputs).
    - [CSS_Em v_fp]: [v_fp] is scaled by 64 (e.g., 1.5em = 96).
    - [CSS_Rem v_fp]: [v_fp] is scaled by 64 (e.g., 1.0rem = 64).
    - [CSS_Pct p_fp]: [p_fp] is scaled by 64 (e.g., 100% = 6400, 50% = 3200). *)
Inductive CSSLengthUnit : Type :=
  | CSS_Px  (val_px : Z)
  | CSS_Em  (val_fp : Z)
  | CSS_Rem (val_fp : Z)
  | CSS_Pct (pct_fp : Z).

(** Model of Blink's [FontDescription] & [CSSToLengthConversionData].
    All sizes in the conversion environment are represented in LayoutUnits. *)
Record CSSToLengthConversionData : Type := mkConversionData {
  env_em_size  : LayoutUnit; (** Current element computed font-size *)
  env_rem_size : LayoutUnit; (** Root element computed font-size    *)
  env_ref_size : LayoutUnit  (** Reference container size for %     *)
}.

(** Well-formedness predicate for conversion environments:
    CSS font-sizes and container reference dimensions cannot be negative. *)
Definition wf_conversion_data (env : CSSToLengthConversionData) : Prop :=
  env.(env_em_size) >= 0 /\
  env.(env_rem_size) >= 0 /\
  env.(env_ref_size) >= 0.

(** Default conversion environment (16px em, 16px rem, 0px container). *)
Definition default_conversion_data (ref_width : LayoutUnit) : CSSToLengthConversionData :=
  mkConversionData kDefaultRootFontSize kDefaultRootFontSize ref_width.

(** ** 2. Resolution Rules (CSS Values 4 Section 5) *)

(** Resolves a [CSSLengthUnit] into a Blink [LayoutUnit]. *)
Definition resolve_length (u : CSSLengthUnit) (env : CSSToLengthConversionData) : LayoutUnit :=
  match u with
  | CSS_Px val_px =>
      val_px * kLayoutUnitDenominator
  | CSS_Em val_fp =>
      (val_fp * env.(env_em_size)) / kLayoutUnitDenominator
  | CSS_Rem val_fp =>
      (val_fp * env.(env_rem_size)) / kLayoutUnitDenominator
  | CSS_Pct pct_fp =>
      (pct_fp * env.(env_ref_size)) / (100 * kLayoutUnitDenominator)
  end.

(** Helper predicate: scalar magnitude of the CSS unit is non-negative. *)
Definition non_negative_unit (u : CSSLengthUnit) : Prop :=
  match u with
  | CSS_Px v  => v >= 0
  | CSS_Em v  => v >= 0
  | CSS_Rem v => v >= 0
  | CSS_Pct p => p >= 0
  end.

(** ** 3. Mathematical Invariants & Theorems *)

(** *** Invariant 1: Exact Fixed-Point Scaling & Identity Laws *)

(** 1px resolves to exactly 64 LayoutUnits. *)
Theorem resolve_one_px_exact :
  forall env, resolve_length (CSS_Px 1) env = 64.
Proof.
  intros env. unfold resolve_length, kLayoutUnitDenominator. lia.
Qed.

(** 1em (val_fp = 64) resolves to the exact LayoutUnit font-size of the element. *)
Theorem resolve_one_em_identity :
  forall env,
    resolve_length (CSS_Em kLayoutUnitDenominator) env = env.(env_em_size).
Proof.
  intros env.
  unfold resolve_length, kLayoutUnitDenominator.
  rewrite Z.mul_comm.
  apply Z_div_mult.
  lia.
Qed.

(** 1rem (val_fp = 64) under the default root font-size resolves to 1024 LayoutUnits (16px). *)
Theorem resolve_default_one_rem :
  forall ref_w,
    resolve_length (CSS_Rem kLayoutUnitDenominator) (default_conversion_data ref_w) = 1024.
Proof.
  intros ref_w.
  unfold resolve_length, default_conversion_data, kDefaultRootFontSize, kLayoutUnitDenominator.
  simpl.
  reflexivity.
Qed.

(** 100% (pct_fp = 6400) resolves to the exact reference container size. *)
Theorem resolve_hundred_percent_identity :
  forall env,
    resolve_length (CSS_Pct (100 * kLayoutUnitDenominator)) env = env.(env_ref_size).
Proof.
  intros env.
  unfold resolve_length, kLayoutUnitDenominator.
  simpl.
  rewrite Z.mul_comm.
  apply Z_div_mult.
  lia.
Qed.

(** *** Invariant 2: Non-Negativity Preservation *)

Theorem resolve_preserves_non_negativity :
  forall (u : CSSLengthUnit) (env : CSSToLengthConversionData),
    wf_conversion_data env ->
    non_negative_unit u ->
    resolve_length u env >= 0.
Proof.
  intros u env [Hem [Hrem Href]] Hnonneg.
  destruct u as [v_px | v_em | v_rem | p_pct];
    unfold resolve_length, kLayoutUnitDenominator;
    simpl in Hnonneg.
  - (* CSS_Px *)
    lia.
  - (* CSS_Em *)
    apply Z.le_ge.
    apply Z.div_pos; [| lia].
    apply Z.mul_nonneg_nonneg; lia.
  - (* CSS_Rem *)
    apply Z.le_ge.
    apply Z.div_pos; [| lia].
    apply Z.mul_nonneg_nonneg; lia.
  - (* CSS_Pct *)
    apply Z.le_ge.
    apply Z.div_pos; [| lia].
    apply Z.mul_nonneg_nonneg; lia.
Qed.

(** *** Invariant 3: Positive Font-Size Monotonicity *)

(** If the computed font-size grows (env1.(env_em_size) <= env2.(env_em_size)),
    any non-negative `em` value resolves to a monotonically non-decreasing LayoutUnit. *)
Theorem em_font_size_monotonicity :
  forall (val_fp : Z) (env1 env2 : CSSToLengthConversionData),
    val_fp >= 0 ->
    0 <= env1.(env_em_size) <= env2.(env_em_size) ->
    resolve_length (CSS_Em val_fp) env1 <= resolve_length (CSS