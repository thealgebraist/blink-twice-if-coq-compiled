### 1. Padding Constraints (CSS Box Model 3 §6 vs. Chromium Blink)

* **CSS Box Model Level 3 (§6 "Padding"):** The specification strictly mandates that computed values for `<length-percentage>` padding properties (`padding-top`, `padding-right`, `padding-bottom`, `padding-left`) must be non-negative: $P_{top}, P_{right}, P_{bottom}, P_{left} \ge 0$. Negative values declared in stylesheets are invalid at parse-time and discarded by the CSS parser.
* **Chromium Blink Implementation:** 
  * **Parse Time:** `CSSPropertyParser` enforces the `kValueRangeNonNegative` constraint when parsing padding shorthands and longhands.
  * **Layout Calculation:** During fragment geometry generation (in `blink::ComputePadding` inside `ng_length_utils.cc`), percentage padding resolves against the inline-size of the containing block. Because inline-sizes are clamped at $0$ and percentage values are non-negative, the resulting `BoxStrut` (represented in fixed-point `LayoutUnit`s) guarantees:
    $$\forall d \in \{\text{top}, \text{right}, \text{bottom}, \text{left}\}, \quad \text{Padding}(d) \ge 0$$
  * **Subpixel Clamping:** Any subpixel rounding in `LayoutUnit` preserves non-negativity via `.ClampNegativeToZero()` guards where dynamic viewport/calc expressions could theoretically underflow.

---

### 2. Content Box Derivation

In Blink’s LayoutNG architecture (`NGBoxFragmentBuilder` and `PhysicalBoxFragment`), physical and logical coordinates of the content box are derived by offsetting the padding box origin and contracting its dimensions by the computed `NGPhysicalBoxStrut` / `BoxStrut`.

Given a **Padding Box** $B_{pad} = (X_{pad}, Y_{pad}, W_{pad}, H_{pad})$ and **Padding Strut** $P = (P_{top}, P_{right}, P_{bottom}, P_{left})$:

* **Origin Translation:**
  $$\text{content\_x} = X_{pad} + P_{left}$$
  $$\text{content\_y} = Y_{pad} + P_{top}$$

* **Dimension Contraction / Expansion:**
  In Blink, layout flows inward to compute available space, or outward from intrinsic content sizes:
  $$W_{pad} = W_{content} + P_{left} + P_{right} \iff W_{content} = \max(0, W_{pad} - (P_{left} + P_{right}))$$
  $$H_{pad} = H_{content} + P_{top} + P_{bottom} \iff H_{content} = \max(0, H_{pad} - (P_{top} + P_{bottom}))$$

---

### 3. Geometric Invariants

1. **Containment Invariant (Content Box $\subseteq$ Padding Box):**
   Because $P \ge 0$ and $W_{content}, H_{content} \ge 0$, the bounding intervals of the content box are enclosed within the padding box along both axes:
   $$X_{pad} \le \text{content\_x} \le \text{content\_x} + W_{content} \le X_{pad} + W_{pad}$$
   $$Y_{pad} \le \text{content\_y} \le \text{content\_y} + H_{content} \le Y_{pad} + H_{pad}$$
   *(Note: In the standard literature and Coq formalization, "strictly contained" in the presence of $P \ge 0$ corresponds to non-strict inequality $\subseteq$ at $P=0$, and strict topological interior containment $\subset$ when $P_{top}, P_{right}, P_{bottom}, P_{left} > 0$).*

2. **Area Monotonicity Invariant:**
   For a fixed non-negative content box size $(W_{content}, H_{content})$, the area of the padding box $\text{Area}(B_{pad}) = W_{pad} \times H_{pad}$ is monotonically non-decreasing with respect to component-wise increases in the padding strut:
   $$P_1 \le P_2 \implies \text{Area}(B_{pad}(C, P_1)) \le \text{Area}(B_{pad}(C, P_2))$$

---

### 4. Concrete Rocq / Coq Formalization (`BlinkCSSPaddingGeometrySemantics.v`)

The following file is a complete, self-contained, zero-axiom Rocq/Coq formalization modelling Blink's `LayoutUnit` integer geometry and proving the CSS Box Model Level 3 §6 invariants.

```coq
(** * BlinkCSSPaddingGeometrySemantics.v
    Agent 119 Audit: Chromium Blink Padding Geometry vs CSS Box Model 3 §6.
    Formalizes LayoutUnit box geometry, padding non-negativity, content box
    derivation, containment invariants, and padding area monotonicity. *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Micromega.Lia.
Open Scope Z_scope.

(** ** 1. Data Structures (Modeling Blink's PhysicalRect and PhysicalBoxStrut) *)

(** Represents a 2D physical rectangle in Blink (e.g., PhysicalRect). *)
Record PhysicalRect : Type := mkRect {
  rect_x : Z;
  rect_y : Z;
  rect_width : Z;
  rect_height : Z
}.

(** Well-formedness of a rectangle: dimensions must be non-negative. *)
Definition wf_rect (r : PhysicalRect) : Prop :=
  rect_width r >= 0 /\ rect_height r >= 0.

(** Represents Blink's PhysicalBoxStrut for padding values. *)
Record PaddingStrut : Type := mkPadding {
  pad_top : Z;
  pad_right : Z;
  pad_bottom : Z;
  pad_left : Z
}.

(** CSS Box Model 3 §6 Constraint: Padding values must be non-negative. *)
Definition wf_padding (p : PaddingStrut) : Prop :=
  pad_top p >= 0 /\
  pad_right p >= 0 /\
  pad_bottom p >= 0 /\
  pad_left p >= 0.

(** Strict positivity for strict interior containment checks. *)
Definition strictly_positive_padding (p : PaddingStrut) : Prop :=
  pad_top p > 0 /\
  pad_right p > 0 /\
  pad_bottom p > 0 /\
  pad_left p > 0.

(** ** 2. Box Derivations (Content Box <-> Padding Box) *)

(** Derives the Padding Box from a given Content Box and Padding Strut
    (Outward expansion, used during intrinsic sizing & fragment generation). *)
Definition padding_box_from_content (content : PhysicalRect) (p : PaddingStrut) : PhysicalRect :=
  mkRect
    (rect_x content - pad_left p)
    (rect_y content - pad_top p)
    (rect_width content + pad_left p + pad_right p)
    (rect_height content + pad_top p + pad_bottom p).

(** Derives the Content Box from a given Padding Box and Padding Strut
    (Inward contraction, matching Blink's content_x = pad_x + pad_left, etc.). *)
Definition content_box_from_padding (pad_box : PhysicalRect) (p : PaddingStrut) : PhysicalRect :=
  mkRect
    (rect_x pad_box + pad_left p)
    (rect_y pad_box + pad_top p)
    (rect_width pad_box - (pad_left p + pad_right p))
    (rect_height pad_box - (pad_top p + pad_bottom p)).

(** Correctness of round-trip derivation between Content Box and Padding Box. *)
Theorem content_padding_roundtrip :
  forall (c : PhysicalRect) (p : PaddingStrut),
    content_box_from_padding (padding_box_from_content c p) p = c.
Proof.
  intros [cx cy cw ch] [pt pr pb pl].
  unfold padding_box_from_content, content_box_from_padding; simpl.
  f_equal; lia.
Qed.

Theorem content_origin_derivation :
  forall (pad_box : PhysicalRect) (p : PaddingStrut),
    let content := content_box_from_padding pad_box p in
    rect_x content = rect_x pad_box + pad_left p /\
    rect_y content = rect_y pad_box + pad_top p.
Proof.
  intros pad_box p. simpl. split; reflexivity.
Qed.

(** ** 3. Geometric Definitions (Bounds, Containment, Area) *)

Definition rect_right (r : PhysicalRect) : Z := rect_x r + rect_width r.
Definition rect_bottom (r : PhysicalRect) : Z := rect_y r + rect_height r.
Definition rect_area (r : PhysicalRect) : Z := rect_width r * rect_height r.

(** Non-strict geometric containment (inner is within outer). *)
Definition rect_contained (inner outer : PhysicalRect) : Prop :=
  rect_x outer <= rect_x inner /\
  rect_y outer <= rect_y inner /\
  rect_right inner <= rect_right outer /\
  rect_bottom inner <= rect_bottom outer.

(** Strict topological containment (inner is strictly inside outer's boundaries). *)
Definition rect_strictly_contained (inner outer : PhysicalRect) : Prop :=
  rect_x outer < rect_x inner /\
  rect_y outer < rect_y inner /\
  rect_right inner < rect_right outer /\
  rect_bottom inner < rect_bottom outer.

(** Component-wise ordering on PaddingStrut. *)
Definition padding_le (p1 p2 : PaddingStrut) : Prop :=
  pad_top p1 <= pad_top p2 /\
  pad_right p1 <= pad_right p2 /\
  pad_bottom p1 <= pad_bottom p2 /\
  pad_left p1 <= pad_left p2.

(** ** 4. Proofs of Core Invariants *)

(** Invariant 3a: Well-formedness preservation. *)
Lemma wf_padding_box :
  forall (c : PhysicalRect) (p : PaddingStrut),
    wf_rect c -> wf_padding p -> wf_rect (padding_box_from_content c p).
Proof.
  intros [cx cy cw ch] [pt pr pb pl] [Hcw Hch] [Hpt [Hpr [Hpb Hpl]]].
  unfold wf_rect, padding_box_from_content; simpl in *.
  split; lia.
Qed.

(** Invariant 3b: Content box is always contained within the padding box
    under standard CSS non-negative padding (P >= 0). *)
Theorem content_contained_in_padding_box :
  forall (pad_box : PhysicalRect) (p : PaddingStrut),
    let content := content_box_from_padding pad_box p in
    wf_padding p ->
    wf_rect content ->
    rect_contained content pad_box.
Proof.
  intros [px py pw ph] [pt pr pb pl] content [Hpt [Hpr [Hpb Hpl]]] [Hcw Hch].
  unfold content in *; clear content.
  unfold content_box_from_padding, rect_contained, rect_right, rect_bottom in *; simpl in *.
   repeat split; lia.
Qed.

(** Invariant 3c: Content box is strictly contained within the padding box
    when padding is strictly positive (P > 0). *)
Theorem content_strictly_contained_in_padding_box :
  forall (pad_box : PhysicalRect) (p : PaddingStrut),
    let content := content_box_from_padding pad_box p in
    strictly_positive_padding p ->
    wf_rect content ->
    rect_strictly_contained content pad_box.
Proof.
  intros [px py pw ph] [pt pr pb pl] content [Hpt [Hpr [Hpb Hpl]]] [Hcw Hch].
  unfold content in *; clear content.
  unfold content_box_from_padding, rect_strictly_contained, rect_right, rect_bottom in *; simpl in *.
  repeat split; lia.
Qed.

(** Invariant 3d: Padding box area is monotonic with respect to padding values. *)
Theorem padding_box_area_monotonic :
  forall (c : PhysicalRect) (p1 p2 : PaddingStrut),
    wf_rect c ->
    wf_padding p1 ->
    wf_padding p2 ->
    padding_le p1 p2 ->
    rect_area (padding_box_from_content c p1) <= rect_area (padding_box_from_content c p2).
Proof.
  intros [cx cy cw ch] [pt1 pr1 pb1 pl1] [pt2 pr2 pb2 pl2].
  intros [Hcw Hch] [Hpt1 [Hpr1 [Hpb1 Hpl1]]] [Hpt2 [Hpr2 [Hpb2 Hpl2]]] [Hle_t [Hle_r [Hle_b Hle_l]]].
  unfold padding_box_from_content, rect_area; simpl in *.
  apply Z.mul_le_mono_nonneg; lia.
Qed.

(** Corollary: Content box area never exceeds Padding box area. *)
Corollary content_area_le_padding_area :
  forall (c : PhysicalRect) (p : PaddingStrut),
    wf_rect c ->
    wf_padding p ->
    rect_area c <= rect_area (padding_box_from_content c p).
Proof.
  intros c p Hwfc Hwfp.
  pose (p0 := mkPadding 0 0 0 0).
  assert (Hp0 : wf_padding p0) by (unfold wf_padding, p0; simpl; lia).
  assert (Hle : padding_le p0 p) by (unfold padding_le, p0; destruct Hwfp as [? [? [? ?]]]; simpl; lia).
  assert (Heq : rect_area c = rect_area (padding_box_from_content c p0)).
  { destruct c; unfold padding_box_from_content, rect_area, p0; simpl. f_equal; lia. }
  rewrite Heq.
  apply padding_box_area_monotonic; assumption.
Qed.
```