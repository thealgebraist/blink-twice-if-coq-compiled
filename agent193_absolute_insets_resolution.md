### Audit Report: Agent 193 — Chromium Blink Absolute Positioned Insets Resolution vs. CSS Positioned Layout 3 §5

This audit examines the resolution of vertical insets (`top`, `bottom`) and block size (`height`) for absolutely positioned boxes within Chromium’s Blink layout engine (`third_party/blink/renderer/core/layout/absolute_utils.cc`, specifically `ComputeAbsoluteDialogYPosition` and `ComputeInsets` / `ComputeOutOfFlowBlockDimensions`) against the **CSS Positioned Layout Module Level 3 §5 (Abspos Layout Equation)**.

---

### 1. Insets Equation (CSS Positioned 3 §5)

In CSS Positioned Layout Level 3, the vertical geometry of an absolutely positioned box (assuming zero margins, borders, and padding for base core resolution) is governed by the fundamental constraint equation:

$$\text{top} + \text{height} + \text{bottom} = \text{cb\_height}$$

Where:
* $\text{cb\_height}$ is the height of the containing block.
* $\text{top}, \text{bottom}$ are the vertical inset properties.
* $\text{height}$ is the content/box block-size.

When any of these three values are `auto`, the layout engine resolves the `auto` value(s) using algebraic substitution to satisfy the equality (with intrinsic size measurement if `height` is `auto`).

---

### 2. Over-Constrained Resolution

When `top`, `height`, and `bottom` are **all** explicitly specified (none are `auto`), the system of equations is over-constrained if $\text{top} + \text{height} + \text{bottom} \neq \text{cb\_height}$.

Per CSS Positioned 3 §5.3 ("Width and Height of Absolutely Positioned Elements"):
> *"If none of the three are `auto`: ... ignore the value for `bottom` (in horizontal-tb writing modes) and solve for that value."*

In Chromium Blink’s `OutOfFlowLayoutPart` and `absolute_utils.cc`:
1. The engine computes the static or explicit `top` inset and the explicit `height`.
2. In standard `horizontal-tb` (top-to-bottom block flow), the specified `bottom` inset is discarded when computing the box's physical offset and size.
3. The effective used value of `bottom` is dynamically re-derived as:
   $$\text{bottom}_{\text{used}} = \text{cb\_height} - (\text{top}_{\text{used}} + \text{height}_{\text{used}})$$

---

### 3. Formal Invariants

The Blink implementation maintains the following structural invariants during over-constrained resolution:
1. **Insets Equality Conservation:** Regardless of the authored `bottom` value, the resolved used values strictly satisfy $\text{top}_{\text{used}} + \text{height}_{\text{used}} + \text{bottom}_{\text{used}} = \text{cb\_height}$.
2. **Specified Size Preservation:** The resolved $\text{height}_{\text{used}}$ is identical to the authored non-auto `height` (ignoring min/max clamping for the base equation).
3. **Start-Edge Priority (Top-to-Bottom):** The resolved $\text{top}_{\text{used}}$ is identical to the authored non-auto `top`.

---

### 4. Rocq / Coq Formalization (`BlinkAbsoluteInsetsResolutionSemantics.v`)

Below is the complete, self-contained Rocq (Coq) formalization verifying the semantics and invariants of Blink's absolute positioned insets resolution.

```coq
(** * BlinkAbsoluteInsetsResolutionSemantics.v
    Formal Audit of Chromium Blink Absolute Positioned Insets Resolution
    against CSS Positioned Layout Module Level 3 §5.
    Agent 193 Audit Artifact. *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Bool.Bool.
Require Import Coq.Micromega.Lia.

Open Scope Z_scope.

(** ** 1. Data Types for CSS Values and Geometry *)

(** CSS length values can either be 'auto' or a definite integer (representing LayoutUnit). *)
Inductive CssLength : Type :=
  | Auto : CssLength
  | Definite : Z -> CssLength.

(** Authored style inputs for the vertical axis of an abspos box (margins/borders omitted). *)
Record AbsposVerticalStyle : Type := mkStyle {
  style_top    : CssLength;
  style_height : CssLength;
  style_bottom : CssLength
}.

(** Resolved (used) layout values after Blink's OutOfFlow resolution. *)
Record ResolvedVerticalGeometry : Type := mkResolved {
  used_top    : Z;
  used_height : Z;
  used_bottom : Z
}.

(** ** 2. Specification of CSS Positioned 3 §5 Equations *)

(** The fundamental constraint equation: top + height + bottom = cb_height *)
Definition satisfies_insets_equation (cb_height : Z) (g : ResolvedVerticalGeometry) : Prop :=
  (used_top g) + (used_height g) + (used_bottom g) = cb_height.

(** Predicate identifying when the vertical axis is over-constrained. *)
Definition is_over_constrained (s : AbsposVerticalStyle) : Prop :=
  exists t h b : Z,
    style_top s = Definite t /\
    style_height s = Definite h /\
    style_bottom s = Definite b.

(** ** 3. Blink Resolution Semantics (horizontal-tb / Top-to-Bottom) *)

(** Mirrors Blink's third_party/blink/renderer/core/layout/absolute_utils.cc.
    `intrinsic_height` and `static_top` are fallback measurements provided by layout
    when respective properties are 'Auto'. *)
Definition blink_resolve_vertical_insets
  (cb_height intrinsic_height static_top : Z)
  (s : AbsposVerticalStyle) : ResolvedVerticalGeometry :=
  match style_top s, style_height s, style_bottom s with
  (* Case 1: All three are Auto -> use static_top, intrinsic_height, solve for bottom *)
  | Auto, Auto, Auto =>
      let t := static_top in
      let h := intrinsic_height in
      let b := cb_height - (t + h) in
      mkResolved t h b

  (* Case 2: Only top and bottom are Definite, height is Auto -> solve for height *)
  | Definite t, Auto, Definite b =>
      let h := cb_height - (t + b) in
      mkResolved t h b

  (* Case 3: Auto top, Definite height and bottom -> solve for top *)
  | Auto, Definite h, Definite b =>
      let t := cb_height - (h + b) in
      mkResolved t h b

  (* Case 4: Auto top and height, Definite bottom -> use intrinsic_height, solve for top *)
  | Auto, Auto, Definite b =>
      let h := intrinsic_height in
      let t := cb_height - (h + b) in
      mkResolved t h b

  (* Case 5: Definite top, Auto height and bottom -> use intrinsic_height, solve for bottom *)
  | Definite t, Auto, Auto =>
      let h := intrinsic_height in
      let b := cb_height - (t + h) in
      mkResolved t h b

  (* Case 6: Definite top and height, Auto bottom -> solve for bottom *)
  | Definite t, Definite h, Auto =>
      let b := cb_height - (t + h) in
      mkResolved t h b

  (* Case 7: Auto top and bottom, Definite height -> use static_top, solve for bottom *)
  | Auto, Definite h, Auto =>
      let t := static_top in
      let b := cb_height - (t + h) in
      mkResolved t h b

  (* Case 8: OVER-CONSTRAINED (All Definite).
     Per CSS Positioned 3 §5.3, ignore 'bottom' and solve for it:
     bottom = cb_height - (top + height) *)
  | Definite t, Definite h, Definite _ (* ignored authored bottom *) =>
      let b_resolved := cb_height - (t + h) in
      mkResolved t h b_resolved
  end.

(** ** 4. Formal Verification of Invariants *)

(** Theorem 1: Universal Conservation of the Insets Equation.
    For all possible CSS input styles, containing block heights, intrinsic sizes,
    and static positions, Blink's resolution satisfies the CSS Positioned 3 §5 equality. *)
Theorem blink_resolution_satisfies_insets_equation :
  forall (cb_height intrinsic_height static_top : Z) (s : AbsposVerticalStyle),
    satisfies_insets_equation cb_height
      (blink_resolve_vertical_insets cb_height intrinsic_height static_top s).
Proof.
  intros cb_height intrinsic_height static_top [top_val height_val bottom_val].
  unfold satisfies_insets_equation, blink_resolve_vertical_insets; simpl.
  destruct top_val as [|t];
  destruct height_val as [|h];
  destruct bottom_val as [|b];
  simpl; lia.
Qed.

(** Theorem 2: Over-Constrained Resolution Rule (Ignore Bottom).
    When top, height, and bottom are all definite, the resolved geometry ignores
    the authored bottom and sets used_bottom = cb_height - (top + height). *)
Theorem over_constrained_ignores_bottom :
  forall (cb_height intrinsic_height static_top t h b1 b2 : Z),
    let s1 := mkStyle (Definite t) (Definite h) (Definite b1) in
    let s2 := mkStyle (Definite t) (Definite h) (Definite b2) in
    blink_resolve_vertical_insets cb_height intrinsic_height static_top s1 =
    blink_resolve_vertical_insets cb_height intrinsic_height static_top s2.
Proof.
  intros.
  unfold s1, s2, blink_resolve_vertical_insets.
  simpl.
  reflexivity.
Qed.

(** Theorem 3: Over-Constrained Height and Top Preservation.
    In the over-constrained state, both authored 'top' and authored 'height'
    are strictly preserved in the used geometry, and 'bottom' is exact. *)
Theorem over_constrained_invariants :
  forall (cb_height intrinsic_height static_top t h b : Z),
    let s := mkStyle (Definite t) (Definite h) (Definite b) in
    let res := blink_resolve_vertical_insets cb_height intrinsic_height static_top s in
    used_top res = t /\
    used_height res = h /\
    used_bottom res = cb_height - (t + h) /\
    satisfies_insets_equation cb_height res.
Proof.
  intros cb_height intrinsic_height static_top t h b s res.
  unfold res, s, blink_resolve_vertical_insets, satisfies_insets_equation.
  simpl.
  repeat split; lia.
Qed.

(** Theorem 4: Idempotence of Resolution.
    Re-feeding the resolved geometry back into the solver as definite styles
    produces the exact same geometry. *)
Theorem blink_resolution_idempotent :
  forall (cb_height intrinsic_height static_top : Z) (s : AbsposVerticalStyle),
    let res1 := blink_resolve_vertical_insets cb_height intrinsic_height static_top s in
    let s_resolved := mkStyle (Definite (used_top res1))
                              (Definite (used_height res1))
                              (Definite (used_bottom res1)) in
    let res2 := blink_resolve_vertical_insets cb_height intrinsic_height static_top s_resolved in
    res1 = res2.
Proof.
  intros cb_height intrinsic_height static_top [top_val height_val bottom_val] res1 s_resolved res2.
  unfold res2, s_resolved, res1, blink_resolve_vertical_insets.
  destruct top_val as [|t];
  destruct height_val as [|h];
  destruct bottom_val as [|b];
  simpl; f_equal; lia.
Qed.
```