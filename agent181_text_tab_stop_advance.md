### Audit Report: Agent 181 — Chromium Blink Tab Stop Expansion vs. CSS Text Module Level 3 §4.2

In CSS Text Module Level 3 §4.2 (*Tab Stops and the `tab-size` Property*), tab stops occur at integer multiples of the tab width (`tab_width`) measured from the start edge of the line box. When a U+0009 CHARACTER TABULATION (tab) is encountered at an inline advance offset `current_x`, it expands to reach the next tab stop strictly greater than `current_x`.

In Chromium Blink’s inline layout engine (`blink::TabSize` and `blink::Font::TabWidth` in `third_party/blink/renderer/platform/fonts/font.cc`), fixed-point (`LayoutUnit`) or integer layout coordinates calculate the advance using integer division or modulo arithmetic.

---

### 1. Mathematical & Implementation Breakdown

#### 1.1 Next Tab Position (`next_x`)
Given a non-negative inline offset `current_x` ($\ge 0$) and a strictly positive tab width `tab_width` ($> 0$), integer division $\lfloor \text{current\_x} / \text{tab\_width} \rfloor$ yields the index of the last tab stop at or before `current_x`. Adding $1$ indexes the strictly next tab stop:
$$\text{next\_x} = \left(\left\lfloor \frac{\text{current\_x}}{\text{tab\_width}} \right\rfloor + 1\right) \times \text{tab\_width}$$

#### 1.2 Tab Advance (`tab_advance`)
The inline advance width assigned to the tab glyph run is the distance from the current position to `next_x`:
$$\text{tab\_advance} = \text{next\_x} - \text{current\_x}$$
*(Note: In Blink, this is frequently computed via the algebraically equivalent expression `tab_width - (current_x % tab_width)`).*

#### 1.3 Core Layout Invariants
For all $\text{current\_x} \ge 0$ and $\text{tab\_width} > 0$:
1. **Bounded Positive Advance**: $0 < \text{tab\_advance} \le \text{tab\_width}$. Even if `current_x` sits exactly on an existing tab stop ($\text{current\_x} \bmod \text{tab\_width} = 0$), a tab character must advance by a full `tab_width` to the next stop.
2. **Strict Monotonicity**: $\text{next\_x} > \text{current\_x}$. Tab expansion never produces a zero or negative inline offset change.
3. **Grid Alignment**: $\text{next\_x} \bmod \text{tab\_width} = 0$. The resulting inline position always aligns cleanly to the tab grid.

---

### 2. Formal Verification: `BlinkTextTabStopAdvanceSemantics.v`

Below is the complete, self-contained Rocq (Coq) formalization verifying the equivalence of Blink's modulo optimization and the three CSS Text 3 §4.2 invariants over non-negative integer layout units (`Z`).

```coq
(** * BlinkTextTabStopAdvanceSemantics.v
    Formal Audit by Agent 181: Chromium Blink Tab Stop Expansion
    Specification: CSS Text Module Level 3, Section 4.2 (tab-size) *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Section TabStopSemantics.

  (** [current_x] represents the current inline offset (in LayoutUnits or px).
      [tab_width] represents the computed pixel/LayoutUnit width of a tab stop. *)

  Definition next_x (current_x tab_width : Z) : Z :=
    ((current_x / tab_width) + 1) * tab_width.

  Definition tab_advance (current_x tab_width : Z) : Z :=
    next_x current_x tab_width - current_x.

  (** Blink frequently computes tab advance directly via modulo:
      [tab_width - (current_x mod tab_width)].
      We prove this optimization is identical to the specification. *)
  Lemma tab_advance_mod_equiv : forall current_x tab_width : Z,
    tab_width > 0 ->
    tab_advance current_x tab_width = tab_width - (current_x mod tab_width).
  Proof.
    intros current_x tab_width Htab.
    unfold tab_advance, next_x.
    pose proof (Z_div_mod_eq_full current_x tab_width) as Hdiv.
    lia.
  Qed.

  (** Invariant 1: 0 < tab_advance <= tab_width *)
  Theorem tab_advance_bounds : forall current_x tab_width : Z,
    current_x >= 0 ->
    tab_width > 0 ->
    0 < tab_advance current_x tab_width <= tab_width.
  Proof.
    intros current_x tab_width Hcur Htab.
    rewrite tab_advance_mod_equiv by assumption.
    assert (Hmod : 0 <= current_x mod tab_width < tab_width).
    { apply Z_mod_lt. lia. }
    lia.
  Qed.

  (** Invariant 2: next_x > current_x *)
  Theorem next_x_strictly_increasing : forall current_x tab_width : Z,
    current_x >= 0 ->
    tab_width > 0 ->
    next_x current_x tab_width > current_x.
  Proof.
    intros current_x tab_width Hcur Htab.
    pose proof (tab_advance_bounds current_x tab_width Hcur Htab) as Hbounds.
    unfold tab_advance in Hbounds.
    lia.
  Qed.

  (** Invariant 3: next_x mod tab_width = 0 *)
  Theorem next_x_grid_aligned : forall current_x tab_width : Z,
    current_x >= 0 ->
    tab_width > 0 ->
    (next_x current_x tab_width) mod tab_width = 0.
  Proof.
    intros current_x tab_width Hcur Htab.
    unfold next_x.
    apply Z_mod_mult.
  Qed.

  (** Corollary: When current_x is already on a tab stop,
      tab_advance expands by a full tab_width. *)
  Corollary tab_advance_on_stop : forall current_x tab_width : Z,
    current_x >= 0 ->
    tab_width > 0 ->
    current_x mod tab_width = 0 ->
    tab_advance current_x tab_width = tab_width.
  Proof.
    intros current_x tab_width Hcur Htab Hmod.
    rewrite tab_advance_mod_equiv by assumption.
    lia.
  Qed.

End TabStopSemantics.
```