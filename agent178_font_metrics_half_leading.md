### Audit Report: Agent 178
**Target:** Chromium Blink Font Half-Leading (`FontHeight` / `FontMetrics` in `third_party/blink/renderer/platform/fonts/` and `ng_inline_box_state.cc`)  
**Specification:** CSS Inline Layout Module Level 3 §3.2 (Leading and Half-Leading)

---

### 1. Half-Leading Calculation

In CSS Inline 3 §3.2, the difference between the computed `line-height` and the content area height ($A + D$, where $A$ is ascent and $D$ is descent) is the **leading**. The specification requires splitting this leading equally above and below the content area (**half-leading**):

$$\Delta L = \text{line\_height} - (A + D)$$
$$L = \frac{\Delta L}{2} = \frac{\text{line\_height} - (A + D)}{2}$$

In Chromium Blink’s layout engine (specifically LayoutNG, utilizing fixed-point `LayoutUnit` or integer pixel snapping during legacy/font metric phases), exact division by 2 over discrete representations $(\mathbb{Z})$ introduces truncation. Blink computes the integer/fixed-point half-leading via arithmetic shift or integer division:

$$L_{\text{top}} = \lfloor \frac{\Delta L}{2} \rfloor \quad \text{or} \quad \text{ truncate}(\frac{\Delta L}{2})$$

---

### 2. Effective Above/Below Baseline Offsets

To prevent layout drift and losing the odd subpixel/pixel during integer division, Blink does not assign $L$ identically to both sides when $\Delta L$ is odd. Instead, it assigns the residual leading to the descent side (bottom offset):

*   **Total Leading:** $\Delta L = \text{line\_height} - (A + D)$
*   **Top Half-Leading ($L_{\text{top}}$):** $\Delta L \div 2$
*   **Bottom Half-Leading ($L_{\text{bottom}}$):** $\Delta L - L_{\text{top}}$

This yields the effective baseline-relative bounds (`FontHeight` in Blink):

*   **Effective Ascent (`top_offset`):**
    $$\text{top\_offset} = A + L_{\text{top}}$$
*   **Effective Descent (`bottom_offset`):**
    $$\text{bottom\_offset} = D + (\text{line\_height} - (A + D) - L_{\text{top}})$$

---

### 3. Invariants

1.  **Conservation of Line Height (`top_offset + bottom_offset = line_height`):**  
    Regardless of rounding or truncation rules used to compute $L$, defining the bottom half-leading as the remainder $(\Delta L - L)$ algebraically guarantees that the sum of the effective ascent and effective descent equals the exact `line_height`.
2.  **Unique Baseline Positioning:**  
    Given fixed metrics $(A, D, \text{line\_height})$ and a deterministic division operator, the baseline exists at a unique, deterministic coordinate offset `top_offset` below the line box's top edge (and `bottom_offset` above its bottom edge). If $\text{line\_height} \ge 0$, the top and bottom boundaries do not invert ($-\text{top\_offset} \le \text{bottom\_offset}$).

---

### 4. Rocq / Coq Formalization (`BlinkFontMetricsHalfLeadingSemantics.v`)

The following complete, self-contained Rocq (Coq) script models Blink's exact integer/fixed-point (`Z`) arithmetic for half-leading and formally verifies the CSS Inline 3 §3.2 invariants.

```coq
(** * BlinkFontMetricsHalfLeadingSemantics.v
    Formal Audit of Chromium Blink Font Half-Leading vs CSS Inline 3 §3.2
    Agent 178 *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Section BlinkHalfLeading.

  (** In Chromium Blink (LayoutNG), metrics are represented as fixed-point 
      integers (LayoutUnit, 1/64th of a pixel) or rounded integers. 
      We model these values in Z. *)

  Record FontMetrics := mkFontMetrics {
    ascent : Z;
    descent : Z
  }.

  Record LineBoxMetrics := mkLineBoxMetrics {
    top_offset : Z;    (* Effective ascent above baseline *)
    bottom_offset : Z  (* Effective descent below baseline *)
  }.

  (** Total leading: ΔL = line_height - (ascent + descent) *)
  Definition total_leading (m : FontMetrics) (line_height : Z) : Z :=
    line_height - (ascent m + descent m).

  (** Half-leading calculation: L = (line_height - (ascent + descent)) / 2.
      Blink uses truncated division (Z.quot) or floor division (Z.div) 
      depending on the subsystem. We parameterize the division operator 
      or use standard Z.div, noting that the conservation invariant holds 
      for ANY deterministic midpoint function. *)
  Definition half_leading (m : FontMetrics) (line_height : Z) : Z :=
    (total_leading m line_height) / 2.

  (** Effective above/below baseline computation matching Blink's 
      FontHeight::AddLeading implementation. *)
  Definition compute_line_box_metrics (m : FontMetrics) (line_height : Z) : LineBoxMetrics :=
    let L := half_leading m line_height in
    let delta_L := total_leading m line_height in
    {|
      top_offset := ascent m + L;
      bottom_offset := descent m + (delta_L - L)
    |}.

  (** * Invariant 1: Conservation of Line Height
      top_offset + bottom_offset = line_height *)
  Theorem line_height_conservation :
    forall (m : FontMetrics) (line_height : Z),
      let lbm := compute_line_box_metrics m line_height in
      top_offset lbm + bottom_offset lbm = line_height.
  Proof.
    intros m line_height lbm.
    unfold lbm, compute_line_box_metrics, total_leading.
    simpl.
    (* Algebraically holds regardless of the value of (half_leading m line_height) *)
    lia.
  Qed.

  (** * Invariant 2: Half-Leading Symmetry Bound
      The difference between the bottom leading and top leading is at most 1 
      quantum (1 pixel or 1 LayoutUnit), ensuring compliance with CSS Inline 3 §3.2. *)
  Theorem half_leading_symmetry_bound :
    forall (m : FontMetrics) (line_height : Z),
      let L_top := half_leading m line_height in
      let L_bot := (total_leading m line_height) - L_top in
      0 <= L_bot - L_top <= 1.
  Proof.
    intros m line_height L_top L_bot.
    unfold L_bot, L_top, half_leading.
    pose proof (Z.div_mod (total_leading m line_height) 2) as Hmod.
    pose proof (Z.mod_pos_bound (total_leading m line_height) 2) as Hbound.
    lia.
  Qed.

  (** * Invariant 3: Unique Baseline Positioning within Line Box
      In a coordinate system where y=0 is the top of the line box and y=line_height 
      is the bottom, the baseline y_baseline = top_offset is uniquely determined 
      and satisfies: line_height - bottom_offset = top_offset. *)
  Theorem baseline_uniquely_positioned :
    forall (m : FontMetrics) (line_height : Z) (y_baseline : Z),
      let lbm := compute_line_box_metrics m line_height in
      (y_baseline = top_offset lbm /\ line_height - y_baseline = bottom_offset lbm) <->
      y_baseline = ascent m + half_leading m line_height.
  Proof.
    intros m line_height y_baseline lbm.
    unfold lbm, compute_line_box_metrics, total_leading.
    simpl.
    split; intros H; lia.
  Qed.

  (** * Invariant 4: Non-Inversion of Line Box Bounds
      For any non-negative line_height, in baseline-relative coordinates where 
       the baseline is at 0, the top edge (-top_offset) is strictly above or 
      coincident with the bottom edge (bottom_offset). *)
  Theorem line_box_bounds_ordered :
    forall (m : FontMetrics) (line_height : Z),
      0 <= line_height ->
      let lbm := compute_line_box_metrics m line_height in
      - (top_offset lbm) <= bottom_offset lbm.
  Proof.
    intros m line_height Hlh lbm.
    pose proof (line_height_conservation m line_height) as Hcons.
    cbv zeta in Hcons.
    fold lbm in Hcons.
    lia.
  Qed.

End BlinkHalfLeading.
```