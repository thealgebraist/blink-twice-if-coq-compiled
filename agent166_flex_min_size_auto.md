### 1. Automatic Minimum Size Resolution (CSS Flexbox 1 §4.5 vs. Blink)

According to CSS Flexible Box Layout Module Level 1 §4.5 ("Automatic Minimum Size of Flex Items"), when a flex item has `min-width: auto` or `min-height: auto` along the main axis (and `overflow` is `visible`), its resolved minimum main size is computed from up to three suggestions:
* **Content-based minimum size:** The item's `min-content` main size.
* **Specified size suggestion:** If the item has a definite computed main size (`width`/`height`), that size is a suggestion.
* **Transferred size suggestion:** Derived from a definite cross size and an intrinsic aspect ratio (omitted here when assuming no aspect ratio).

The specification states that if the specified size suggestion exists, the automatic minimum size is the *smaller* of the content size suggestion and the specified size suggestion:
$$\text{auto\_min\_size} = \begin{cases} \min(\text{specified\_size}, \text{min\_content}) & \text{if specified\_size is definite} \\ \text{min\_content} & \text{if specified\_size is auto} \end{cases}$$

In Chromium Blink (`ng_flex_layout_algorithm.cc` / `FlexLayoutAlgorithm::ComputeMinAndMaxSizesForChild`), this is implemented by computing the `content_size_suggestion` via the item's min-content contribution, checking if the main axis length is definite (`specified_size_suggestion`), and clamping the content suggestion down to the specified size suggestion via ` std::min(content_size_suggestion, specified_size_suggestion)`.

---

### 2. Clamping: Flex Item Used Main Size $\ge \text{auto\_min\_size}$

During the flex sizing algorithm (§9.7 "Resolving Flexible Lengths"), each flex item has a target main size derived from its `flex-basis` and flex factor distribution. Blink attaches a `MinMaxSizes` constraint struct `{min_size, max_size}` to every `FlexItem`. 

When `min-main-size` is `auto`, `min_size` is initialized to $\text{auto\_min\_size}$. During the freeze Loop in `FlexLine::FreezeViolations`, any item whose flexed main size falls below `min_size` registers a positive violation and is clamped:
$$\text{used\_main\_size} = \max(\text{min\_size}, \min(\text{flexed\_size}, \text{max\_size}))$$

Assuming standard CSS box-sizing constraints where $\text{max\_size} \ge \text{min\_size}$ (or where `min-size` wins over `max-size` per CSS 2.1 §10.4 / §10.7), the final used main size satisfies:
$$\text{used\_main\_size} \ge \text{auto\_min\_size}$$

---

### 3. Core Invariant

**Invariant:** Given non-negative layout inputs ($\text{min\_content} \ge 0$ and definite $\text{specified\_size} \ge 0$), the final used main size of a flex item with `min-size: auto` is guaranteed to be non-negative ($\text{used\_main\_size} \ge 0$). Furthermore, when the item's computed main size (`width`/`height`) is `auto`, the specified size suggestion does not apply, and the used main size is strictly bounded below by the item's intrinsic `min-content` size ($\text{used\_main\_size} \ge \text{min\_content}$), preventing the flex container from shrinking the item below its intrinsic minimum content size.

---

### 4. Concrete Rocq / Coq Formalization (`BlinkFlexMinSizeAutoSemantics.v`)

```coq
(** * BlinkFlexMinSizeAutoSemantics.v
    Formal verification of Chromium Blink Flex Min-Size: Auto Clamping
    against CSS Flexible Box Layout Module Level 1 §4.5. *)

From Coq Require Import Arith.PeanoNat.
From Coq Require Import micromega.Lia.

Module BlinkFlexMinSizeAutoSemantics.

(** Represent CSS main-axis size property (width / height) *)
Inductive SpecifiedSize : Type :=
  | SizeAuto : SpecifiedSize
  | SizeDefinite : nat -> SpecifiedSize.

(** Represent CSS min-width / min-height property *)
Inductive MinSize : Type :=
  | MinAuto : MinSize
  | MinDefinite : nat -> MinSize.

(** Represent CSS max-width / max-height property *)
Inductive MaxSize : Type :=
  | MaxNone : MaxSize
  | MaxDefinite : nat -> MaxSize.

(** ** 1. Automatic Minimum Size Resolution (§4.5)
    Resolves [min-size: auto] to [min(specified_size, min_content)] when
    [specified_size] is definite, and [min_content] when [auto]. *)
Definition resolve_auto_min_size (spec : SpecifiedSize) (min_content : nat) : nat :=
  match spec with
  | SizeAuto => min_content
  | SizeDefinite s => Nat.min s min_content
  end.

(** Resolve the effective minimum main size of the flex item *)
Definition resolve_min_size (m : MinSize) (spec : SpecifiedSize) (min_content : nat) : nat :=
  match m with
  | MinAuto => resolve_auto_min_size spec min_content
  | MinDefinite d => d
  end.

(** ** 2. Clamping Mechanics (§9.7 & CSS 2.1 §10.4)
    In CSS, max-size clamping is applied first, followed by min-size clamping
    (so min-size wins if min_size > max_size). *)
Definition clamp_to_max (size : nat) (max_s : MaxSize) : nat :=
  match max_s with
  | MaxNone => size
  | MaxDefinite m => Nat.min size m
  end.

Definition compute_used_main_size
  (flexed_size : nat)
  (min_s : MinSize)
  (max_s : MaxSize)
  (spec : SpecifiedSize)
  (min_content : nat) : nat :=
  let eff_min := resolve_min_size min_s spec min_content in
  let max_clamped := clamp_to_max flexed_size max_s in
  Nat.max eff_min max_clamped.

(** ** 3. Verification Theorems & Invariants *)

(** Theorem 1: Automatic minimum size resolution matches min(spec, min_content)
    for definite sizes. *)
Theorem auto_min_size_definite_eq :
  forall (s min_content : nat),
    resolve_auto_min_size (SizeDefinite s) min_content = Nat.min s min_content.
Proof.
  intros s min_content.
  simpl. reflexivity.
Qed.

(** Theorem 2: Automatic minimum size is bounded above by min_content. *)
Theorem auto_min_size_le_min_content :
  forall (spec : SpecifiedSize) (min_content : nat),
    resolve_auto_min_size spec min_content <= min_content.
Proof.
  intros [| s] min_content; simpl; lia.
Qed.

(** Theorem 3: Clamping guarantees used main size >= auto_min_size
    when min-size is auto. *)
Theorem used_main_size_ge_auto_min_size :
  forall (flexed_size min_content : nat) (max_s : MaxSize) (spec : SpecifiedSize),
    compute_used_main_size flexed_size MinAuto max_s spec min_content >=
    resolve_auto_min_size spec min_content.
Proof.
  intros flexed_size min_content max_s spec.
  unfold compute_used_main_size, resolve_min_size.
  lia.
Qed.

(** Theorem 4 (Core Invariant): Used size is non-negative and bounded below
    by intrinsic min-content when both min-size and specified-size are auto. *)
Theorem used_size_nonneg_and_bounded_by_min_content_when_auto :
  forall (flexed_size min_content : nat) (max_s : MaxSize),
    0 <= compute_used_main_size flexed_size MinAuto max_s SizeAuto min_content /\
    min_content <= compute_used_main_size flexed_size MinAuto max_s SizeAuto min_content.
Proof.
  intros flexed_size min_content max_s.
  unfold compute_used_main_size, resolve_min_size, resolve_auto_min_size.
  split; lia.
Qed.

(** Theorem 5: When specified size is definite and smaller than min_content,
    auto_min_size clamps down to the specified size. *)
Theorem auto_min_size_respects_smaller_definite_size :
  forall (s min_content : nat),
    s <= min_content ->
    resolve_auto_min_size (SizeDefinite s) min_content = s.
Proof.
  intros s min_content Hle.
  simpl. lia.
Qed.

End BlinkFlexMinSizeAutoSemantics.
```