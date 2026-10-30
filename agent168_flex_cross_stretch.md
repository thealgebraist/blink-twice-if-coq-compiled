### Audit Report: Agent 168 — Chromium Blink Flex Cross Axis Stretch vs. CSS Flexbox 1 §8.3

---

### 1. Stretch Sizing Mechanics (CSS Flexbox 1 §8.3 vs. Blink Implementation)

In CSS Flexible Box Layout Module Level 1 §8.3 (*Cross-Axis Alignment: the `align-self` and `align-items` properties*) and §9.4 (*Cross Size Determination*, Step 11), a flex item undergoes cross-axis stretching if and only if all of the following preconditions hold:
1. The computed `align-self` property of the item resolves to `stretch`.
2. The computed cross size property (`width` in `row` flex directions, `height` in `column` flex directions) is `auto`.
3. Neither of the item's cross-axis margins are `auto`.

In Chromium Blink (`third_party/blink/renderer/core/layout/flex/flex_layout_algorithm.cc`), during the final cross-axis layout phase (`GiveItemsFinalPositionAndSize`), the layout engine computes the target stretched border-box size by taking the flex line's cross size (`line_cross_size`), subtracting the item's cross-axis outer margins, and clamping the result between the item's resolved minimum and maximum cross sizes:

$$\text{used\_cross\_size} = \text{clamp}(\text{min\_cross}, \text{max\_cross}, \text{line\_cross\_size} - \text{margins}_{\text{cross}})$$

Assuming normalized zero margins (or absorbing margins into the effective line cross space allocated to the item), the sizing equation reduces to:

$$\text{used\_cross\_size} = \max(\text{min\_cross}, \min(\text{max\_cross}, \text{line\_cross\_size}))$$

Note that per CSS Sizing 3, if `min_cross` $>$ `max_cross`, the minimum constraint wins ($\max(\text{min\_cross}, \dots)$).

---

### 2. Core Invariant

**Invariant (Unconstrained Stretch Identity):**
For any flex item satisfying the stretch preconditions where the line cross size falls within the valid range of the item's cross-axis min/max constraints ($\text{min\_cross} \le \text{line\_cross\_size} \le \text{max\_cross}$), the item's used cross size is strictly equal to the flex line's cross size:

$$\text{align\_self} = \text{Stretch} \land \text{cross\_size} = \text{Auto} \land \text{no\_auto\_margins} \land (\text{min\_cross} \le \text{line\_cross\_size} \le \text{max\_cross}) \implies \text{used\_cross\_size} = \text{line\_cross\_size}$$

---

### 3. Rocq / Coq Formalization (`BlinkFlexCrossStretchSemantics.v`)

The following self-contained Rocq (Coq) script formalizes the Blink cross-axis stretch semantics over non-negative layout units (`nat`, representing `LayoutUnit` ticks) and proves the core stretch invariants.

```coq
(** * BlinkFlexCrossStretchSemantics.v
    Formal Audit by Agent 168: Chromium Blink Flex Cross-Axis Stretch vs CSS Flexbox 1 §8.3 *)

From Coq Require Import Arith PeanoNat Lia Bool.

Module BlinkFlexCrossStretchSemantics.

(** ** 1. Basic CSS & Blink Layout Types *)

Inductive AlignSelf : Type :=
  | AlignAuto
  | AlignFlexStart
  | AlignFlexEnd
  | AlignCenter
  | AlignBaseline
  | AlignStretch.

Inductive SizeSpec : Type :=
  | SizeAuto
  | SizeDefinite (px : nat).

(** Equality deciders for inductive types *)
Scheme Equality for AlignSelf.
Scheme Equality for SizeSpec.

(** CSS Clamp Semantics: max(min_val, min(max_val, val))
    In CSS, min_val takes precedence over max_val if min_val > max_val. *)
Definition css_clamp (min_val max_val val : nat) : nat :=
  Nat.max min_val (Nat.min max_val val).

(** Flex item state relevant to §8.3 & §9.4 Step 11 cross-axis sizing *)
Record FlexItemCrossState : Type := mkFlexItemCrossState {
  align_self       : AlignSelf;
  cross_size       : SizeSpec;
  has_auto_margin  : bool;
  min_cross        : nat;
  max_cross        : nat;
  hypothetical_cross : nat (* Fallback cross size if not stretched *)
}.

(** ** 2. Blink Stretch Predicate and Sizing Function *)

(** §8.3 / §9.4 Step 11: Conditions under which an item stretches *)
Definition should_stretch (item : FlexItemCrossState) : bool :=
  AlignSelf_beq (align_self item) AlignStretch &&
  SizeSpec_beq (cross_size item) SizeAuto &&
  negb (has_auto_margin item).

(** Blink's cross size resolution for a flex item on a line of size [line_cross_size] *)
Definition compute_used_cross_size (item : FlexItemCrossState) (line_cross_size : nat) : nat :=
  if should_stretch item then
    css_clamp (min_cross item) (max_cross item) line_cross_size
  else
    css_clamp (min_cross item) (max_cross item) (hypothetical_cross item).

(** ** 3. Formal Theorems and Invariants *)

(** Lemma: css_clamp identity when value is within [min_val, max_val] *)
Lemma css_clamp_in_bounds : forall (min_val max_val val : nat),
  min_val <= val ->
  val <= max_val ->
  css_clamp min_val max_val val = val.
Proof.
  intros min_val max_val val Hmin Hmax.
  unfold css_clamp.
  lia.
Qed.

(** Lemma: css_clamp enforces min_val lower bound *)
Lemma css_clamp_ge_min : forall (min_val max_val val : nat),
  min_val <= css_clamp min_val max_val val.
Proof.
  intros min_val max_val val.
  unfold css_clamp.
  lia.
Qed.

(** Lemma: css_clamp enforces max_val upper bound when constraints are well-formed *)
Lemma css_clamp_le_max : forall (min_val max_val val : nat),
  min_val <= max_val ->
  css_clamp min_val max_val val <= max_val.
Proof.
  intros min_val max_val val Hwf.
  unfold css_clamp.
  lia.
Qed.

(** Theorem 1 (Requirement 1): Stretch Sizing Formula
    When align-self is stretch, cross size is auto, and there are no auto margins,
    used_cross_size equals clamp(min_cross, max_cross, line_cross_size). *)
Theorem stretch_sizing_formula : forall (item : FlexItemCrossState) (line_cross_size : nat),
  align_self item = AlignStretch ->
  cross_size item = SizeAuto ->
  has_auto_margin item = false ->
  compute_used_cross_size item line_cross_size =
    css_clamp (min_cross item) (max_cross item) line_cross_size.
Proof.
  intros item line_cross_size Halign Hsize Hmargin.
  unfold compute_used_cross_size, should_stretch.
  rewrite Halign, Hsize, Hmargin.
  simpl.
  reflexivity.
Qed.

(** Theorem 2 (Requirement 2 - Core Invariant):
    used_cross_size matches line_cross_size if stretching applies and
    line_cross_size is within [min_cross, max_cross]. *)
Theorem stretch_matches_line_cross_size_in_bounds :
  forall (item : FlexItemCrossState) (line_cross_size : nat),
  align_self item = AlignStretch ->
  cross_size item = SizeAuto ->
  has_auto_margin item = false ->
  min_cross item <= line_cross_size ->
  line_cross_size <= max_cross item ->
  compute_used_cross_size item line_cross_size = line_cross_size.
Proof.
  intros item line_cross_size Halign Hsize Hmargin Hmin Hmax.
  rewrite (stretch_sizing_formula item line_cross_size Halign Hsize Hmargin).
  apply css_clamp_in_bounds; assumption.
Qed.

(** Theorem 3: Min-Cross Precedence Over Max-Cross (CSS Sizing 3 §4.1 Invariant)
    If min_cross > max_cross on a stretched item, used_cross_size resolves to min_cross. *)
Theorem stretch_min_beats_max :
  forall (item : FlexItemCrossState) (line_cross_size : nat),
  align_self item = AlignStretch ->
  cross_size item = SizeAuto ->
  has_auto_margin item = false ->
  max_cross item < min_cross item ->
  compute_used_cross_size item line_cross_size = min_cross item.
Proof.
  intros item line_cross_size Halign Hsize Hmargin Hgt.
  rewrite (stretch_sizing_formula item line_cross_size Halign Hsize Hmargin).
  unfold css_clamp.
  lia.
Qed.

(** Theorem 4: Non-Auto Cross Size Prevents Stretch
    If cross_size is definite, line_cross_size does not affect used_cross_size. *)
Theorem definite_cross_size_ignores_line_size :
  forall (item : FlexItemCrossState) (px line1 line2 : nat),
  cross_size item = SizeDefinite px ->
  compute_used_cross_size item line1 = compute_used_cross_size item line2.
Proof.
  intros item px line1 line2 Hdef.
  unfold compute_used_cross_size, should_stretch.
  rewrite Hdef.
  simpl.
  rewrite andb_false_r.
  simpl.
  reflexivity.
Qed.

End BlinkFlexCrossStretchSemantics.
```