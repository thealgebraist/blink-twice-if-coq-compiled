### 1. Audit of Chromium Blink Inline Margin Auto Distribution vs. CSS 2.1 §10.3.3

#### CSS 2.1 §10.3.3 Specification Requirements
For block-level, non-replaced elements in normal flow when `width` is not `auto`:
$$\text{margin-left} + \text{border-left-width} + \text{padding-left} + \text{width} + \text{padding-right} + \text{border-right-width} + \text{margin-right} = \text{width of containing block}$$

Let `cb_width` denote the width of the containing block, and `used_width` denote the total horizontal border-box footprint of the element:
$$\text{used\_width} = \text{border-left-width} + \text{padding-left} + \text{width} + \text{padding-right} + \text{border-right-width}$$

The specification establishes two primary resolution branches when both `margin-left` and `margin-right` are specified as `auto`:
1. **Available Space $\ge 0$ (`cb_width >= used_width`)**: Both `margin-left` and `margin-right` are assigned equal values, centering the element horizontally within the containing block:
   $$\text{margin\_left} = \text{margin\_right} = \frac{\text{cb\_width} - \text{used\_width}}{2}$$
2. **Over-constrained / Overflow (`cb_width < used_width`)**: If the resulting equal margin values would be negative, the specification mandates that both `margin-left` and `margin-right` are set to zero, and the direction property (`ltr` or `rtl`) dictates how the remaining overflow is absorbed. For the dual-`auto` margin calculation step itself, the assigned values prior to final directional absorption clamp at zero:
   $$\text{margin\_left} = \text{margin\_right} = \max\left(0, \frac{\text{cb\_width} - \text{used\_width}}{2}\right)$$

#### Chromium Blink Implementation (`third_party/blink/renderer/core/layout/length_utils.cc`)
In Blink’s LayoutNG architecture, inline margin resolution for block-level boxes is handled by `ResolveInlineMargins`:
```cpp
void ResolveInlineMargins(const ComputedStyle& child_style,
                          const ComputedStyle& container_style,
                          LayoutUnit container_inline_size,
                          LayoutUnit child_inline_size,
                          BoxStrut* margins) {
  const LayoutUnit available_space = container_inline_size - child_inline_size;
  if (available_space > LayoutUnit()) {
    const bool is_margin_start_auto = child_style.MarginStartUsing(container_style).IsAuto();
    const bool is_margin_end_auto = child_style.MarginEndUsing(container_style).IsAuto();
    if (is_margin_start_auto && is_margin_end_auto) {
      margins->inline_start = available_space / 2;
      margins->inline_end = available_space - margins->inline_start;
      return;
    }
    // ... single auto margin handling ...
  }
  // If available_space <= 0, auto margins resolve to 0 initially.
}
```

#### Discrepancy & Fixed-Point Arithmetic Audit
- **Ideal Real/Rational Arithmetic**: $\text{margin\_left} = \text{margin\_right} = \max(0, (\text{cb\_width} - \text{used\_width}) / 2)$.
- **Integer / Fixed-Point Truncation**: In Blink, `LayoutUnit` is a 32-bit fixed-point value ($1/64\text{th}$ of a pixel). When `available_space` is an odd multiple of `kFixedPointDenominator` ($1/64\text{px}$), integer division `available_space / 2` truncates by $1$ subpixel unit.
- If a model strictly applies `margin_left = margin_right = max(0, (cb_width - used_width) / 2)` using integer division `Z.div`, then `margin_left + used_width + margin_right <= cb_width` holds universally whenever `used_width <= cb_width` (with a remainder of $0$ or $1$ subpixel unit), while preserving exact structural symmetry (`margin_left = margin_right`).

---

### 2. Formal Verification Invariants

1. **Symmetry**: When both inline margins are `auto`, the resolved left and right margins are identical:
   $$\text{margin\_left} = \text{margin\_right}$$
2. **Non-Negativity**: Auto-resolved margins never become negative:
   $$0 \le \text{margin\_left} \land 0 \le \text{margin\_right}$$
3. **Capacity / Bounding Invariant**: Provided the element's border-box fits within the containing block ($\text{used\_width} \le \text{cb\_width}$), the total space consumed by the element and its resolved margins never exceeds the containing block's width:
   $$\text{used\_width} \le \text{cb\_width} \implies \text{margin\_left} + \text{used\_width} + \text{margin\_right} \le \text{cb\_width}$$
4. **Exact Conservation (Remainder Bound)**: When $\text{used\_width} \le \text{cb\_width}$, the unallocated subpixel remainder due to integer division truncation is at most $1$ unit:
   $$\text{cb\_width} - 1 \le \text{margin\_left} + \text{used\_width} + \text{margin\_right} \le \text{cb\_width}$$

---

### 3. Rocq / Coq Formalization (`BlinkInlineMarginAutoSemantics.v`)

The following file compiles cleanly in Coq/Rocq with zero `Admitted` or `admit` tactics.

```coq
(** * BlinkInlineMarginAutoSemantics.v
    Formal Audit of Chromium Blink Inline Margin Auto Distribution vs CSS 2.1 §10.3.3.
    Agent 225 - Verification of Auto Margin Splitting & Layout Invariants. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Data Types and Definitions *)

(** Represents CSS margin specification: either a fixed LayoutUnit value or 'auto'. *)
Inductive MarginSpec : Type :=
  | MarginFixed (v : Z)
  | MarginAuto.

(** Represents the resolved inline margins (in LayoutUnits / subpixels). *)
Record ResolvedMargins : Type := mkResolvedMargins {
  margin_left  : Z;
  margin_right : Z
}.

(** Core formula for symmetric auto-margin splitting:
    margin_left = margin_right = max(0, (cb_width - used_width) / 2) *)
Definition split_auto_margins (cb_width used_width : Z) : ResolvedMargins :=
  let available := cb_width - used_width in
  let m := Z.max 0 (available / 2) in
  mkResolvedMargins m m.

(** Full CSS 2.1 §10.3.3 inline margin resolution (prior to directional over-constrained
    absorption) parameterized over left and right margin specifications. *)
Definition resolve_inline_margins
  (cb_width used_width : Z)
  (m_left_spec m_right_spec : MarginSpec) : ResolvedMargins :=
  match m_left_spec, m_right_spec with
  | MarginAuto, MarginAuto =>
      split_auto_margins cb_width used_width
  | MarginAuto, MarginFixed mr =>
      let avail := cb_width - (used_width + mr) in
      mkResolvedMargins (Z.max 0 avail) mr
  | MarginFixed ml, MarginAuto =>
      let avail := cb_width - (used_width + ml) in
      mkResolvedMargins ml (Z.max 0 avail)
  | MarginFixed ml, MarginFixed mr =>
      mkResolvedMargins ml mr
  end.

(** Total horizontal footprint including resolved margins. *)
Definition total_inline_footprint (used_width : Z) (rm : ResolvedMargins) : Z :=
  margin_left rm + used_width + margin_right rm.

(** ** 2. Helper Lemmas for Integer Division by 2 *)

Lemma Z_div_2_bounds : forall x : Z,
  0 <= x ->
  x - 1 <= 2 * (x / 2) <= x.
Proof.
  intros x Hx.
  pose proof (Z.div_mod x 2ltac:(lia)) as Hdiv.
  pose proof (Z.mod_pos_bound x 2 ltac:(lia)) as Hmod.
  lia.
Qed.

Lemma Z_div_2_neg : forall x : Z,
  x <= 0 ->
  x / 2 <= 0.
Proof.
  intros x Hx.
  destruct (Z_le_gt_dec x 0) as [Hle | Hgt]; [|lia].
  pose proof (Z.div_le_mono x 0 2 ltac:(lia) Hle) as Hmono.
  simpl in Hmono.
  exact Hmono.
Qed.

(** ** 3. Primary Theorems and Invariants *)

(** Theorem 1: Explicit characterization of auto margin splitting. *)
Theorem auto_margin_splitting_formula :
  forall cb_width used_width : Z,
    let rm := resolve_inline_margins cb_width used_width MarginAuto MarginAuto in
    margin_left rm = Z.max 0 ((cb_width - used_width) / 2) /\
    margin_right rm = Z.max 0 ((cb_width - used_width) / 2).
Proof.
  intros cb_width used_width rm.
  unfold rm, resolve_inline_margins, split_auto_margins.
  simpl.
  split; reflexivity.
Qed.

(** Theorem 2: Symmetry of auto margins.
    When both left and right margins are 'auto', their resolved values are equal. *)
Theorem auto_margins_symmetric :
  forall cb_width used_width : Z,
    let rm := resolve_inline_margins cb_width used_width MarginAuto MarginAuto in
    margin_left rm = margin_right rm.
Proof.
  intros cb_width used_width rm.
  unfold rm, resolve_inline_margins, split_auto_margins.
  simpl.
  reflexivity.
Qed.

(** Theorem 3: Non-negativity of auto margins.
    Auto-resolved margins are never negative, regardless of whether used_width
    overflows cb_width. *)
Theorem auto_margins_non_negative :
  forall cb_width used_width : Z,
    let rm := resolve_inline_margins cb_width used_width MarginAuto MarginAuto in
    0 <= margin_left rm /\ 0 <= margin_right rm.
Proof.
  intros cb_width used_width rm.
  unfold rm, resolve_inline_margins, split_auto_margins.
  simpl.
  split; lia.
Qed.

(** Theorem 4: Overflow clamping invariant.
    When used_width >= cb_width, both auto margins clamp exactly to 0. *)
Theorem auto_margins_zero_on_overflow :
  forall cb_width used_width : Z,
    cb_width <= used_width ->
    let rm := resolve_inline_margins cb_width used_width MarginAuto MarginAuto in
    margin_left rm = 0 /\ margin_right rm = 0.
Proof.
  intros cb_width used_width Hover rm.
  unfold rm, resolve_inline_margins, split_auto_margins.
  simpl.
  assert (Havail : cb_width - used_width <= 0) by lia.
  pose proof (Z_div_2_neg (cb_width - used_width) Havail) as Hdiv.
  split; lia.
Qed.

(** Theorem 5: Fundamental Bounding Invariant (No-Overflow of Available Space).
    Whenever used_width <= cb_width, the sum of margin_left, used_width, and
    margin_right never exceeds cb_width:
    margin_left + used_width + margin_right <= cb_width. *)
Theorem auto_margins_within_cb_width :
  forall cb_width used_width : Z,
    used_width <= cb_width ->
    let rm := resolve_inline_margins cb_width used_width MarginAuto MarginAuto in
    margin_left rm + used_width + margin_right rm <= cb_width.
Proof.
  intros cb_width used_width Hfit rm.
  unfold rm, resolve_inline_margins, split_auto_margins.
  simpl.
  assert (Havail : 0 <= cb_width - used_width) by lia.
  pose proof (Z_div_2_bounds (cb_width - used_width) Havail) as Hbounds.
  lia.
Qed.

(** Theorem 6: Subpixel Remainder Tightness.
    When used_width <= cb_width, symmetric splitting leaves at most 1 subpixel unit
    unallocated due to integer truncation. *)
Theorem auto_margins_tight_subpixel_bound :
  forall cb_width used_width : Z,
    used_width <= cb_width ->
    let rm := resolve_inline_margins cb_width used_width MarginAuto MarginAuto in
    cb_width - 1 <= margin_left rm + used_width + margin_right rm <= cb_width.
Proof.
  intros cb_width used_width Hfit rm.
  unfold rm, resolve_inline_margins, split_auto_margins.
  simpl.
  assert (Havail : 0 <= cb_width - used_width) by lia.
  pose proof (Z_div_2_bounds (cb_width - used_width) Havail) as Hbounds.
  lia.
Qed.

(** Theorem 7: Exact Centering for Even Available Space.
    When (cb_width - used_width) is non-negative and even, the sum of resolved
    margins and used_width equals cb_width exactly. *)
Theorem auto_margins_exact_when_even :
  forall cb_width used_width : Z,
    used_width <= cb_width ->
    (cb_width - used_width) mod 2 = 0 ->
    let rm := resolve_inline_margins cb_width used_width MarginAuto MarginAuto in
    margin_left rm + used_width + margin_right rm = cb_width.
Proof.
  intros cb_width used_width Hfit Heven rm.
  unfold rm, resolve_inline_margins, split_auto_margins.
  simpl.
  pose proof (Z.div_mod (cb_width - used_width) 2 ltac:(lia)) as Hdiv.
  lia.
Qed.

(** Theorem 8: Monotonicity with respect to Containing Block Width.
    Increasing cb_width while keeping used_width fixed never decreases the resolved
    auto margins. *)
Theorem