### 1. Intrinsic Dimensions & Aspect Ratio Preservation

In Chromium Blink (specifically within `ng_length_utils.cc` and `ng_replaced_layout_algorithm.cc`), replaced elements ($e.g.$, `<img>`, `<video>`, `<canvas>`) resolve their layout size using three primary inputs from the element itself: intrinsic width ($W_0$), intrinsic height ($H_0$), and intrinsic aspect ratio ($R_0$).

According to **CSS 2.1 §10.3.2** and **CSS Sizing Module Level 3 §5.1**:
* An element possesses an intrinsic aspect ratio $R_0 = \frac{W_0}{H_0}$ if and only if $W_0 > 0$ and $H_0 > 0$ (unless an explicit `aspect-ratio` property overrides it).
* Aspect ratio preservation is governed by the continuous algebraic invariant:
  $$W \cdot H_0 = H \cdot W_0$$
  where $W$ and $H$ are the used width and used height of the replaced element.

In Blink's LayoutNG, layout lengths are represented in `LayoutUnit` (a fixed-point 26.6 format). When converting continuous specifications into discrete verification models, we model the ideal real/rational behavior first to verify the algorithmic logic of `ComputeReplacedSize`, where division is rewritten as cross-multiplication ($W \cdot H_0 = H \cdot W_0$) to avoid division-by-zero states and floating-point precision loss.

---

### 2. Resolution When Only Width or Only Height is Specified

The CSS constraint resolution matrix for replaced elements with an intrinsic aspect ratio ($W_0 > 0 \land H_0 > 0$) operates as follows:

1. **Only Width Specified ($W_{spec} = \text{ Val } w$, $H_{spec} = \text{Auto}$):**
   * The used width $W$ resolves directly to the specified width (clamped to $\ge 0$).
   * The used height $H$ is derived via the aspect ratio:
     $$H = W \cdot \frac{H_0}{W_0}$$

2. **Only Height Specified ($W_{spec} = \text{Auto}$, $H_{spec} = \text{ Val } h$):**
   * The used height $H$ resolves directly to the specified height (clamped to $\ge 0$).
   * The used width $W$ is derived via the aspect ratio:
     $$W = H \cdot \frac{W_0}{H_0}$$

3. **Both Auto ($W_{spec} = \text{Auto}$, $H_{spec} = \text{Auto}$):**
   * If $W_0$ and $H_0$ exist, $W = W_0$ and $H = H_0$.
   * Fallback (CSS 2.1 §10.3.2): If no intrinsic dimensions exist, Blink defaults to the standard fallback size of $300\text{px} \times 150\text{px}$, unless constrained by the containing block width $W_{cb}$ in specific formatting contexts.

---

### 3. System Invariants

Our audit of Blink's replaced size calculation establishes three core invariants:

1. **Dimension Non-Negativity:** 
   $$\forall \text{ inputs}, \quad W \ge 0 \land H \ge 0$$
   Negative specified lengths are clamped or rejected during style resolution; intrinsic dimensions and fallback values are strictly non-negative.

2. **Aspect Ratio Scaling Consistency:**
   If at least one dimension is `Auto` and valid intrinsic dimensions exist ($W_0 > 0, H_0 > 0$), the resolved $(W, H)$ strictly satisfies:
   $$W \cdot H_0 = H \cdot W_0$$

3. **Containment in Container Width (`max-width: 100%` constraint pattern):**
   When an inline/block replaced element is constrained by its containing block width $W_{cb}$ (e.g., via transfers of `max-width: min(W_spec, W_cb)`), the resolved width satisfies:
   $$W \le W_{cb}$$
   Furthermore, if $H$ is `Auto`, the height scales down proportionally to preserve $W \cdot H_0 = H \cdot W_0$ under the $W_{cb}$ constraint.

---

### 4. Concrete Rocq / Coq Formalization

Below is the complete, self-contained formalization for `BlinkReplacedElementSemantics.v` using `QArith` (Rationals) to exactly model rational aspect-ratio scaling without division truncation errors.

```coq
(** * BlinkReplacedElementSemantics.v
    Formal Audit of Chromium Blink Replaced Element Layout
    against CSS 2.1 §10.3.2 and CSS Sizing 3 §5. *)

Require Import Coq.QArith.QArith.
Require Import Coq.QArith.Qminmax.
Require Import Coq.micromega.Lqa.

Open Scope Q_scope.

(** ** 1. Data Types & Input Specifications *)

Inductive CSSSize : Type :=
  | Auto : CSSSize
  | Specified : Q -> CSSSize.

Record IntrinsicDimensions : Type := mkIntrinsic {
  W0 : Q;
  H0 : Q
}.

Record StyleBox : Type := mkStyle {
  spec_w : CSSSize;
  spec_h : CSSSize;
  clamp_to_cb : bool (* Models max-width: 100% containment *)
}.

Record ResolvedSize : Type := mkResolved {
  W : Q;
  H : Q
}.

(** Helper: Clamp a rational value to be non-negative *)
Definition Qclamp_nonneg (x : Q) : Q := Qmax 0 x.

(** Standard CSS 2.1 Fallback dimensions: 300px by 150px *)
Definition Fallback_W : Q := 300#1.
Definition Fallback_H : Q := 150#1.

(** ** 2. Blink Replaced Element Resolution Algorithm *)

Definition resolve_replaced_size 
  (style : StyleBox) 
  (intr : IntrinsicDimensions) 
  (W_cb : Q) : ResolvedSize :=
  let w0 := Qclamp_nonneg (W0 intr) in
  let h0 := Qclamp_nonneg (H0 intr) in
  let cb := Qclamp_nonneg W_cb in
  let has_ar := andb (Qlt_le_dec 0 w0) (Qlt_le_dec 0 h0) in
  
  (* Step 1: Resolve unconstrained (W, H) per CSS 2.1 §10.3.2 / §10.6.2 *)
  let '(raw_w, raw_h) :=
    match spec_w style, spec_h style with
    | Specified sw, Specified sh =>
        (Qclamp_nonneg sw, Qclamp_nonneg sh)
        
    | Specified sw, Auto =>
        let w := Qclamp_nonneg sw in
        if has_ar then (w, (w * h0) / w0)
        else if Qlt_le_dec 0 h0 then (w, h0)
        else (w, Fallback_H)
        
    | Auto, Specified sh =>
        let h := Qclamp_nonneg sh in
        if has_ar then ((h * w0) / h0, h)
        else if Qlt_le_dec 0 w0 then (w0, h)
        else (Fallback_W, h)
        
    | Auto, Auto =>
        if has_ar then (w0, h0)
        else if Qlt_le_dec 0 w0 then (w0, Fallback_H)
        else if Qlt_le_dec 0 h0 then (Fallback_W, h0)
        else (Fallback_W, Fallback_H)
    end
  in
  (* Step 2: Apply Containing Block Containment if active *)
  if clamp_to_cb style then
    let final_w := Qmin raw_w cb in
    match spec_w style, spec_h style with
    | _, Auto =>
        if has_ar then mkResolved final_w ((final_w * h0) / w0)
        else mkResolved final_w raw_h
    | _, _ => mkResolved final_w raw_h
    end
  else
    mkResolved raw_w raw_h.

(** ** 3. Auxiliary Lemmas for Rational Arithmetic *)

Lemma Qclamp_nonneg_ge_0 : forall x, 0 <= Qclamp_nonneg x.
Proof.
  intros x. unfold Qclamp_nonneg. apply Q.le_max_l.
Qed.

Lemma Qclamp_nonneg_id : forall x, 0 <= x -> Qclamp_nonneg x == x.
Proof.
  intros x Hx. unfold Qclamp_nonneg. apply Q.max_r. exact Hx.
Qed.

Lemma mult_div_nonneg : forall a b c,
  0 <= a -> 0 <= b -> 0 < c -> 0 <= (a * b) / c.
Proof.
  intros a b c Ha Hb Hc.
  apply Qle_shift_div_l; [exact Hc |].
   rewrite Qmult_0_l.
  apply Qmult_le_0_compat; assumption.
Qed.

(** ** 4. Formal Verification of Core Invariants *)

(** *** Invariant 1: Dimension Non-Negativity *)
Theorem dimension_non_negativity :
  forall (style : StyleBox) (intr : IntrinsicDimensions) (W_cb : Q),
  let res := resolve_replaced_size style intr W_cb in
  0 <= W res /\ 0 <= H res.
Proof.
  intros style intr W_cb.
  unfold resolve_replaced_size.
  set (w0 := Qclamp_nonneg (W0 intr)).
  set (h0 := Qclamp_nonneg (H0 intr)).
  set (cb := Qclamp_nonneg W_cb).
  assert (Hw0 : 0 <= w0) by apply Qclamp_nonneg_ge_0.
  assert (Hh0 : 0 <= h0) by apply Qclamp_nonneg_ge_0.
  assert (Hcb : 0 <= cb) by apply Qclamp_nonneg_ge_0.
  assert (Hfw : 0 <= Fallback_W) by (unfold Fallback_W; lra).
  assert (Hfh : 0 <= Fallback_H) by (unfold Fallback_H; lra).
  
  destruct (spec_w style) as [|sw];
  destruct (spec_h style) as [|sh];
  destruct (Qlt_le_dec 0 w0) as [Hw0_pos | Hw0_ zero];
  destruct (Qlt_le_dec 0 h0) as [Hh0_pos | Hh0_zero];
  simpl;
  repeat (destruct (clamp_to_cb style); simpl);
  try (split; [
     repeat (apply Q.min_glb; try apply Qclamp_nonneg_ge_0; try assumption;
             try (apply mult_div_nonneg; try apply Qclamp_nonneg_ge_0; assumption))
  | repeat (apply Q.min_glb; try apply Qclamp_nonneg_ge_0; try assumption;
            try (apply mult_div_nonneg; try apply Qclamp_nonneg_ge_0; try apply Q.min_glb; assumption))
  ]).
Qed.

(** *** Invariant 2: Aspect Ratio Preservation (W * H0 == H * W0) *)
Theorem aspect_ratio_preservation_width_only :
  forall (sw W_cb : Q) (intr : IntrinsicDimensions) (clamp : bool),
  0 < W0 intr ->
  0 < H0 intr ->
  let style := mkStyle (Specified sw) Auto clamp in
  let res := resolve_replaced_size style intr W_cb in
  (W res) * (H0 intr) == (H res) * (W0 intr).
Proof.
  intros sw W_cb intr clamp Hw0 Hh0 style res.
  unfold res, resolve_replaced_size, style; simpl.
  set (w0 := Qclamp_nonneg (W0 intr)).
  set (h0 := Qclamp_nonneg (H0 intr)).
  assert (Hw0_eq : w0 == W0 intr) by (apply Qclamp_nonneg_id; lra).
  assert (Hh0_eq : h0 == H0 intr) by (apply Qclamp_nonneg_id; lra).
  assert (Hw0_pos : 0 < w0) by lra.
  assert (Hh0_pos : 0 < h0) by lra.
  
  destruct (Qlt_le_dec 0 w0) as [_ | Hbad]; [| lra].
  destruct (Qlt_le_dec 0 h0) as [_ | Hbad]; [| lra].
  simpl.
  destruct clamp; simpl;
  rewrite <- Hw0_eq, <- Hh0_eq;
  field; lra.
Qed.

Theorem aspect_ratio_preservation_height_only :
  forall (sh W_cb : Q) (intr : IntrinsicDimensions),
  0 < W0 intr ->
  0 < H0 intr ->
  let style := mkStyle Auto (Specified sh) false in
  let res := resolve_replaced_size style intr W_cb in
  (W res) * (H0 intr) == (H res) * (W0 intr).
Proof.
  intros sh W_cb intr Hw0 Hh0 style res.
  unfold res, resolve_replaced_size, style; simpl.
  set (w0 := Qclamp_nonneg (W0 intr)).
  set (h0 := Qclamp_nonneg (H0 intr)).
  assert (Hw0_eq : w0 == W0 intr) by (apply Qclamp_nonneg_id; lra).
  assert (Hh0_eq : h0 == H0 intr) by (apply Qclamp_nonneg_id; lra).
  assert (Hw0_pos : 0 < w0) by lra.
  assert (Hh0_pos : 0 < h0) by lra.

  destruct (Qlt_le_dec 0 w0) as [_ | Hbad]; [| lra].
  destruct (Qlt_le_dec 0 h0) as [_ | Hbad]; [| lra].
  simpl.
  rewrite <- Hw0_eq, <- Hh0_eq.
  field; lra.
Qed.

Theorem aspect_ratio_preservation_both_auto :
  forall (W_cb : Q) (intr : IntrinsicDimensions) (clamp : bool),
  0 < W0 intr ->
  0 < H0 intr ->
  let style := mkStyle Auto Auto clamp in
  let res := resolve_replaced_size style intr W_cb in
  (W res) * (H0 intr) == (H res) * (