Here is the formal architectural audit and Rocq (Coq) specification for Chromium Blink’s Replaced Element Sizing engine compared against the CSS Box Sizing Module Level 3 (§6: Intrinsic Sizes) and CSS 2.1 (§10.3.2, §10.4, §10.6.2, §10.7).

---

### 1. Core Data Structures in Blink Replaced Sizing

In Chromium Blink’s LayoutNG architecture (and its legacy `LayoutReplaced` fallback), replaced elements (`<img>`, `<video>`, `<canvas>`, `<svg>`, `<iframe>`) delegate intrinsic dimension queries to an internal representation before box generation.

#### `IntrinsicSizingInfo` (`third_party/blink/renderer/core/layout/intrinsic_sizing_info.h`)
This struct bridges the gap between the replaced content (e.g., an `ImageResource` or `SVGSVGElement`) and the CSS layout constraint space:
*   **`size` (`gfx::SizeF` / `PhysicalSize`)**: Represents the concrete **natural width** and **natural height** of the replaced content.
*   **`aspect_ratio` (`gfx::SizeF` / `LogicalAspectRatio`)**: Represents the **natural aspect ratio** ($w_{ratio} : h_{ratio}$). In Blink, an empty aspect ratio (`IsEmpty() == true`, i.e., $w \le 0 \lor h \le 0$) indicates no intrinsic aspect ratio exists.
*   **`has_width` / `has_height` (`bool`)**: Explicit flags necessary primarily for vector graphics (`<svg>`), which may define a percentage width/height alongside a `viewBox` (giving them an `aspect_ratio` without definite natural physical dimensions).

#### `LayoutReplaced` & `NGReplacedLayoutAlgorithm`
*   **`ComputeIntrinsicSizingInfo()`**: Extracted by querying the underlying resource. Note that CSS `aspect-ratio` properties or HTML width/height attributes map to style properties (`ComputedStyle`), whereas `IntrinsicSizingInfo` strictly reflects the underlying media.
*   **`LayoutUnit`**: Blink’s fixed-point arithmetic type (1/64th of a CSS pixel). While `IntrinsicSizingInfo` uses floating-point (`gfx::SizeF`) to preserve exact ratios during intermediate calculations, the resolved dimensions are clamped and quantized to `LayoutUnit` at the constraint boundary.

---

### 2. The 3-Way Resolution Algorithm

When resolving the used `width` ($W_{used}$) and `height` ($H_{used}$) of a replaced element, Blink evaluates three primary input vectors:
1.  **Specified Sizes**: $W_{spec}, H_{spec} \in \{\text{Auto}, \text{Definite}(v)\}$ (after resolving percentages against the containing block).
2.  **Natural Sizes**: $W_{nat}, H_{nat} \in \mathbb{R}_{\ge 0} \cup \{\text{None}\}$.
3.  **Natural Aspect Ratio**: $R \in \mathbb{R}_{> 0} \cup \{\text{None}\}$ (where $R = W_{ratio} / H_{ratio}$).

#### The Resolution Matrix (Unconstrained by Min/Max)

**Case 1: Both Specified Width and Height are Definite** ($W_{spec} = \text{Def}(w), H_{spec} = \text{Def}(h)$)
*   $W_{used} = w$
*   $H_{used} = h$
*   *Note*: Aspect ratio and natural sizes are completely overridden.

**Case 2: Exactly One Dimension is `Auto`**
*   **Subcase 2a ($W_{spec} = \text{Def}(w), H_{spec} = \text{Auto}$)**:
    1. If $R = \text{Some}(r)$: $H_{used} = w / r$.
    2. Else if $H_{nat} = \text{Some}(h_{nat})$: $H_{used} = h_{nat}$.
    3. Else: $H_{used} = 150\text{px}$ (Fallback height).
    *   In all sub-branches, $W_{used} = w$.
*   **Subcase 2b ($W_{spec} = \text{Auto}, H_{spec} = \text{Def}(h)$)**:
    1. If $R = \text{Some}(r)$: $W_{used} = h \times r$.
    2. Else if $W_{nat} = \text{Some}(w_{nat})$: $W_{used} = w_{nat}$.
    3. Else: $W_{used} = 300\text{px}$ (or container-dependent inline fallback, standard CSS fallback is $300\text{px}$).
    *   In all sub-branches, $H_{used} = h$.

**Case 3: Both Specified Width and Height are `Auto`** ($W_{spec} = \text{Auto}, H_{spec} = \text{Auto}$)
1. If $W_{nat} = \text{Some}(w_{nat})$ and $H_{nat} = \text{Some}(h_{nat})$:
   $W_{used} = w_{nat}, H_{used} = h_{nat}$.
2. If $W_{nat} = \text{Some}(w_{nat})$ and $H_{nat} = \text{None}$:
   $W_{used} = w_{nat}$. If $R = \text{Some}(r)$ then $H_{used} = w_{nat} / r$, else $H_{used} = 150\text{px}$.
3. If $W_{nat} = \text{None}$ and $H_{nat} = \text{Some}(h_{nat})$:
   $H_{used} = h_{nat}$. If $R = \text{Some}(r)$ then $W_{used} = h_{nat} \times r$, else $W_{used} = 300\text{px}$.
4. If $W_{nat} = \text{None}, H_{nat} = \text{None}$, and $R = \text{Some}(r)$:
   Blink resolves the inline size via stretch-fit against the containing block (subject to min/max constraints), or falls back to the $300\text{px} \times 150\text{px}$ constraint box while preserving $r$ (per CSS 2.1 §10.3.2).
5. If $W_{nat} = \text{None}, H_{nat} = \text{None}, R = \text{None}$:
   $W_{used} = 300\text{px}, H_{used} = 150\text{px}$.

---

### 3. Min/Max Size Constraint Enforcement

When `W_spec = Auto`, `H_spec = Auto`, and an aspect ratio $R$ is present, min/max constraints (`min-width`, `max-width`, `min-height`, `max-height`) cannot be applied independently without violating $R$.

Blink implements the **CSS 2.1 §10.4 Constraint Violation Table** (located in `ConstrainIntrinsicSizeToMinMax` within Blink). Given an initial resolved $(w, h)$ where $w / h = r$, and normalized boundaries $[w_{min}, w_{max}]$ and $[h_{min}, h_{max}]$ (where $w_{min} \le w_{max}$ and $h_{min} \le h_{max}$ because `min` wins over `max` in CSS):

| Condition | Resolved Width ($W_{used}$) | Resolved Height ($H_{used}$) |
| :--- | :--- | :--- |
| $w > w_{max} \land h < h_{min}$ | $w_{max}$ | $h_{min}$ |
| $w < w_{min} \land h > h_{max}$ | $w_{min}$ | $h_{max}$ |
| $w > w_{max} \land h > h_{max}$ | $\text{if } (w_{max}/w \le h_{max}/h) \text{ then } w_{max} \text{ else } \max(w_{min}, h_{max} \cdot r)$ | $\text{if } (w_{max}/w \le h_{max}/h) \text{ then } \max(h_{min}, w_{max} / r) \text{ else } h_{max}$ |
| $w < w_{min} \land h < h_{min}$ | $\text{if } (w_{min}/w \le h_{min}/h) \text{ then } \min(w_{max}, h_{min} \cdot r) \text{ else } w_{min}$ | $\text{if } (w_{min}/w \le h_{min}/h) \text{ then } h_{min} \text{ else } \min(h_{max}, w_{min} / r)$ |
| $w > w_{max}$ (only) | $w_{max}$ | $\max(h_{min}, w_{max} / r)$ |
| $w < w_{min}$ (only) | $w_{min}$ | $\min(h_{max}, w_{min} / r)$ |
| $h > h_{max}$ (only) | $\max(w_{min}, h_{max} \cdot r)$ | $h_{max}$ |
| $h < h_{min}$ (only) | $\min(w_{max}, h_{min} \cdot r)$ | $h_{min}$ |
| Otherwise | $w$ | $h$ |

*Note on One-Auto-One-Definite*: If $W_{spec} = \text{Def}(w)$ and $H_{spec} = \text{Auto}$, Blink *first* clamps $w$ to $[w_{min}, w_{max}]$, *then* computes $h = w_{clamped} / r$, and *finally* clamps $h$ to $[h_{min}, h_{max}]$. In this scenario, hitting $h_{min}$ or $h_{max}$ does **not** back-propagate to alter $W_{used}$; the aspect ratio is simply broken in favor of the explicit `width` and `min/max-height` constraints.

---

### 4. Mathematical Invariants

1.  **Non-Negativity ($\forall e, W_{used}(e) \ge 0 \land H_{used}(e) \ge 0$)**: Provided all inputs (natural sizes, specified sizes, min/max bounds) are non-negative and aspect ratios are strictly positive ($>0$), the output dimensions are guaranteed non-negative.
2.  **Idempotence of Min/Max Clamping**: Applying the min/max constraint resolver to an already-constrained $(W_{used}, H_{used})$ yields the exact same dimensions.
3.  **Dominance of `min` over `max`**: In CSS, if $w_{min} > w_{max}$, the effective maximum is raised to $w_{min}$ ($w_{max\_eff} = \max(w_{min}, w_{max})$). Consequently, $W_{used}$ always satisfies $w_{min} \le W_{used} \le \max(w_{min}, w_{max})$.
4.  **Aspect Ratio Preservation in the Unconstrained Interior**: When $W_{spec} = \text{Auto}, H_{spec} = \text{Auto}$, $R = \text{Some}(r)$, and the unconstrained resolved dimensions $(w_0, h_0)$ fall strictly within $[w_{min}, w_{max}] \times [h_{min}, h_{max}]$, then $W_{used} = h_0 \cdot r$.
5.  **Determinism**: The sizing algorithm is a pure total function from `(SpecifiedStyle, IntrinsicSizingInfo)` to `(Q * Q)`.

---

### 5. Concrete Rocq (Coq) Formalization (`BlinkReplacedElementSemantics.v`)

Below is a complete, self-contained Rocq formalization using rational numbers (`QArith`) to model exact aspect-ratio scaling and prove the fundamental invariants.

```coq
(** * BlinkReplacedElementSemantics.v
    Formalization of Chromium Blink's Replaced Element Sizing Algorithm
    against CSS Box Sizing Level 3 §6 and CSS 2.1 §10.3.2 / §10.4. *)

From Coq Require Import QArith Qminmax Lia Lqa.
Open Scope Q_scope.

(** ** 1. Core Data Structures *)

(** Optional dimension: None represents 'auto' (for style) or 'none' (for intrinsic/max). *)
Inductive OptDim : Type :=
  | DimAutoOrNone : OptDim
  | DimVal (q : Q) : OptDim.

(** Blink's IntrinsicSizingInfo representation *)
Record IntrinsicSizingInfo : Type := mkIntrinsic {
  natural_width  : OptDim;
  natural_height : OptDim;
  aspect_ratio   : OptDim; (* Strictly > 0 when present *)
}.

(** CSS ComputedStyle subset for replaced sizing *)
Record ReplacedStyle : Type := mkStyle {
  spec_width  : OptDim;
  spec_height : OptDim;
  min_width   : Q;      (* Defaults to 0 *)
  max_width   : OptDim; (* Defaults to DimAutoOrNone (infinity) *)
  min_height  : Q;      (* Defaults to 0 *)
  max_height  : OptDim; (* Defaults to DimAutoOrNone (infinity) *)
}.

(** Resolved physical dimensions *)
Record ResolvedSize : Type := mkResolved {
  used_width  : Q;
  used_height : Q;
}.

(** Default CSS fallback dimensions (300px by 150px) *)
Definition fallback_width  : Q := 300#1.
Definition fallback_height : Q := 150#1.

(** ** 2. Helper Functions & Clamping *)

(** Clamp a value v between min_v and an optional max_v.
    Enforces CSS rule: min wins over max. *)
Definition clamp_dim (v : Q) (min_v : Q) (max_opt : OptDim) : Q :=
  match max_opt with
  | DimAutoOrNone => Qmax min_v v
  | DimVal max_v  =>
      let eff_max := Qmax min_v max_v in
      Qmax min_v (Qmin v eff_max)
  end.

(** Normalize max bound so that min <= max holds, or use a large sentinel if unbounded *)
Definition resolve_eff_max (v : Q) (min_v : Q) (max_opt : OptDim) : Q :=
  match max_opt with
  | DimAutoOrNone => Qmax min_v v (* Effectively unbounded relative to v and min_v *)
  | DimVal max_v  => Qmax min_v max_v
  end.

(** ** 3. CSS 2.1 §10.4 Min/Max Aspect-Ratio Constraint Table *)

(** Applies min/max constraints to an (auto, auto) replaced box with an aspect ratio r > 0. *)
Definition constrain_auto_auto_with_ratio
  (w h r : Q) (w_min : Q) (w_max_opt : OptDim) (h_min : Q) (h_max_opt : OptDim)
  : ResolvedSize :=
  let w_max := resolve_eff_max (Qmax w (h_min * r)) w_min w_max_opt in
  let h