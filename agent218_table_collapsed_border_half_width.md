### 1. Audit Summary: Chromium Blink vs. CSS 2.1 §17.6.2

In the CSS 2.1 §17.6.2 (The 'border-collapse' model), collapsed borders are centered on the grid lines between table cells. When a collapsed border has an integer pixel width $w$, the rendering engine must split $w$ into two integer half-widths, $w_1$ and $w_2$, allocated to the two adjacent cells (before/after in block direction, or start/end in inline direction).

When $w$ is odd, exact division by $2$ yields a fractional pixel ($0.5\text{px}$). To prevent subpixel anti-aliasing seams or $1\text{px}$ layout gaps, Chromium Blink (specifically within `NGTableBorders` and `LayoutTableCell::CollapsedBorderHalfWidth`) resolves this via asymmetric integer truncation and complementation:
* **First Half ($w_1$):** `w1 = w / 2` (integer floor division: $\lfloor w / 2 \rfloor$).
* **Second Half ($w_2$):** `w2 = w - (w / 2)` (integer ceiling division: $\lceil w / 2 \rceil$, equivalently computed in C++ as `(w + 1) / 2`).

---

### 2. Core Mathematical Invariants

For any non-negative integer border width $w \in \mathbb{N}$:
1. **Exact Pixel Conservation (No Gaps/Overlaps):** 
   $$w_1 + w_2 = \lfloor w / 2 \rfloor + (w - \lfloor w / 2 \rfloor) = w$$
2. **Minimal Asymmetry Bound (CSS 2.1 Centering Rule):** 
   $$0 \le w_2 - w_1 \le 1 \implies |w_1 - w_2| \le 1$$
3. **Ceiling Equivalence:** 
   $$w - \lfloor w / 2 \rfloor = \lfloor (w + 1) / 2 \rfloor$$

---

### 3. Formal Verification in Rocq / Coq (`BlinkTableCollapsedBorderHalfWidthSemantics.v`)

The following file compiles cleanly in Coq/Rocq (8.16+) with **0 admits** and **0 axioms**.

```coq
(** * BlinkTableCollapsedBorderHalfWidthSemantics.v
    Agent 218 Audit: Chromium Blink Collapsed Border Half-Width Allocation
    vs. CSS 2.1 Section 17.6.2. *)

From Coq Require Import Arith PeanoNat Lia.

Module BlinkCollapsedBorderHalfWidth.

  (** ** 1. Concrete Definitions *)

  (** First half-width allocation (before / inline-start): floor(w / 2) *)
  Definition half_width_1 (w : nat) : nat :=
    w / 2.

  (** Second half-width allocation (after / inline-end): w - floor(w / 2) *)
  Definition half_width_2 (w : nat) : nat :=
    w - (w / 2).

  (** Alternative C++ idiom used in Blink: ceil(w / 2) := (w + 1) / 2 *)
  Definition half_width_ceil (w : nat) : nat :=
    (w + 1) / 2.

  (** Absolute difference between two natural numbers *)
  Definition abs_diff (a b : nat) : nat :=
    (a - b) + (b - a).

  (** ** 2. Helper Arithmetic Lemmas *)

  (** Euclidean division by 2 decomposition in standard Peano arithmetic *)
  Lemma div2_decomp : forall w : nat,
    w = 2 * (w / 2) + (w mod 2) /\ (w mod 2 < 2).
  Proof.
    intro w.
    split.
    - apply (Nat.div_mod w 2). lia.
    - apply (Nat.mod_upper_bound w 2). lia.
  Qed.

  (** ** 3. Core Invariant Theorems *)

  (** Invariant 1: Exact Pixel Conservation (w1 + w2 = w).
      Guarantees no subpixel gaps or overlaps across the grid line. *)
  Theorem pixel_conservation : forall w : nat,
    half_width_1 w + half_width_2 w = w.
  Proof.
    intro w.
    unfold half_width_1, half_width_2.
    destruct (div2_decomp w) as [Hdiv Hmod].
    lia.
  Qed.

  (** Invariant 2a: Ordering (w1 <= w2).
      The second half absorbs the extra pixel on odd widths. *)
  Theorem half_width_ordering : forall w : nat,
    half_width_1 w <= half_width_2 w.
  Proof.
    intro w.
    unfold half_width_1, half_width_2.
    destruct (div2_decomp w) as [Hdiv Hmod].
    lia.
  Qed.

  (** Invariant 2b: Minimal Asymmetry Bound (|w1 - w2| <= 1).
      Satisfies CSS 2.1 §17.6.2 centering within 1 device pixel. *)
  Theorem half_width_asymmetry_bound : forall w : nat,
    abs_diff (half_width_1 w) (half_width_2 w) <= 1.
  Proof.
    intro w.
    unfold abs_diff, half_width_1, half_width_2.
    destruct (div2_decomp w) as [Hdiv Hmod].
    lia.
  Qed.

  (** Invariant 3: Equivalence of Complement and Ceiling Formulations.
      Proves `w - w / 2` is strictly identical to `(w + 1) / 2`. *)
  Theorem half_width_2_eq_ceil : forall w : nat,
    half_width_2 w = half_width_ceil w.
  Proof.
    intro w.
    unfold half_width_2, half_width_ceil.
    destruct (div2_decomp w) as [Hdiv Hmod].
    destruct (div2_decomp (w + 1)) as [Hdiv1 Hmod1].
    lia.
  Qed.

  (** Invariant 4: Exact Parity Characterization.
      The difference between w2 and w1 is exactly (w mod 2). *)
  Theorem half_width_diff_exact : forall w : nat,
    half_width_2 w - half_width_1 w = w mod 2.
  Proof.
    intro w.
    unfold half_width_1, half_width_2.
    destruct (div2_decomp w) as [Hdiv Hmod].
    lia.
  Qed.

End BlinkCollapsedBorderHalfWidth.
```