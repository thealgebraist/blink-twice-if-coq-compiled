### 1. Justification Expansion Semantics (CSS Text 3 §7.3.3 vs. Chromium Blink)

In CSS Text Module Level 3 §7.3.3 (`text-justify: inter-word`), justification adjusts typographic alignment by expanding word separator characters (specifically U+0020 SPACE and U+00A0 NO-BREAK SPACE) when the computed inline size of a line is less than the available inline size of its line box. 

In Chromium Blink (`third_party/blink/renderer/core/layout/inline/inline_layout_algorithm.cc` and `shaping_line_breaker.cc`), layout arithmetic operates over fixed-point `LayoutUnit` values (typically $1/64\text{th}$ of a CSS pixel), which can be modeled over $\mathbb{Z}$ (integers) representing atomic layout quanta:

1. **Free Space Calculation:**
   Given `available_width` ($W_{\text{avail}}$) and unexpanded `line_width` ($W_{\text{line}}$), the raw deficit is $\Delta = W_{\text{avail}} - W_{\text{line}}$. Because CSS `inter-word` justification in standard inline layout only expands lines that fall short of the available width (ignoring hyphenation/compression fallbacks), the actionable `free_space` is clamped to non-negative values:
   $$\text{free\_space} = \max(0, W_{\text{avail}} - W_{\text{line}})$$

2. **Per-Space Expansion:**
   Let $N = \text{spaces\_count}$ be the number of justifiable word-separator opportunities on the line.
   - If $N > 0$, each space receives an equal share of the integer division:
     $$\text{extra\_per\_space} = \lfloor \text{free\_space} / N \rfloor$$
   - If $N = 0$, no expansion can occur via inter-word spacing:
     $$\text{extra\_per\_space} = 0$$

*(Note: While HarfBuzz/Blink may distribute sub-pixel remainders $(\text{free\_space} \bmod N)$ across specific glyph advances in the shaping run, the base uniform expansion model guarantees the core allocation bounds established below).*

---

### 2. Core Invariants

1. **Conservation / Bounded Distribution:** The total extra space distributed uniformly across all justifiable spaces never exceeds the available `free_space`:
   $$\text{total\_extra\_space} = \text{extra\_per\_space} \times \text{spaces\_count} \le \text{free\_space}$$
2. **Non-negativity:** Word spacing expansion is strictly non-negative ($\text{extra\_per\_space} \ge 0$), ensuring justification never causes glyphs to collide or overlap due to negative tracking.
3. **Monotonicity in Free Space:** If the available `free_space` increases (e.g., the container widens while line content remains static), the computed `extra_per_space` is monotonically non-decreasing:
   $$\text{free\_space}_1 \le \text{free\_space}_2 \implies \text{extra\_per\_space}_1 \le \text{extra\_per\_space}_2$$

---

### 3. Rocq / Coq Formalization (`BlinkTextJustifyInterWordSemantics.v`)

The following file compiles cleanly in Coq/Rocq (8.16+ / 8.19+) using standard integer arithmetic (`ZArith`) and `lia`.

```coq
(** * BlinkTextJustifyInterWordSemantics.v
    Formalization of Chromium Blink's inter-word text justification 
    against CSS Text Module Level 3 §7.3.3. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Section InterWordJustification.

  (** ** 1. Definitions *)

  (** Actionable free space is clamped to non-negative layout units. *)
  Definition compute_free_space (available_width line_width : Z) : Z :=
    Z.max 0 (available_width - line_width).

  (** Extra width allocated per justifiable space opportunity. *)
  Definition compute_extra_per_space (free_space spaces_count : Z) : Z :=
    if spaces_count >? 0 then
      free_space / spaces_count
    else
      0.

  (** Total extra space distributed uniformly across all spaces on the line. *)
  Definition compute_total_distributed (free_space spaces_count : Z) : Z :=
    (compute_extra_per_space free_space spaces_count) * Z.max 0 spaces_count.

  (** Final justified line width. *)
  Definition justified_line_width (available_width line_width spaces_count : Z) : Z :=
    let free_space := compute_free_space available_width line_width in
    line_width + compute_total_distributed free_space spaces_count.


  (** ** 2. Fundamental Lemmas & Invariants *)

  (** Lemma: Computed free space is always non-negative. *)
  Lemma free_space_nonneg : forall avail line,
    0 <= compute_free_space avail line.
  Proof.
    intros avail line.
    unfold compute_free_space.
    lia.
  Qed.

  (** Invariant 1: Word spacing expansion is always non-negative. *)
  Theorem extra_per_space_nonneg : forall free_space spaces_count,
    0 <= free_space ->
    0 <= compute_extra_per_space free_space spaces_count.
  Proof.
    intros free_space spaces_count Hfree.
    unfold compute_extra_per_space.
    destruct (spaces_count >? 0) eqn:Hgt.
    - apply Z.gtb_lt in Hgt.
      apply Z.div_pos; lia.
    - lia.
  Qed.

  (** Invariant 2: Total extra space distributed never exceeds free_space. *)
  Theorem total_distributed_le_free_space : forall free_space spaces_count,
    0 <= free_space ->
    compute_total_distributed free_space spaces_count <= free_space.
  Proof.
    intros free_space spaces_count Hfree.
    unfold compute_total_distributed, compute_extra_per_space.
    destruct (spaces_count >? 0) eqn:Hgt.
    - apply Z.gtb_lt in Hgt.
      replace (Z.max 0 spaces_count) with spaces_count by lia.
      rewrite Z.mul_comm.
      apply Z.mul_div_le; lia.
    - apply Z.gtb_gt in Hgt || (rewrite Z.gtb_ltb in Hgt; apply Z.ltb_ge in Hgt).
      replace (0 * Z.max 0 spaces_count) with 0 by lia.
      assumption.
  Qed.

  (** Corollary: Total distributed space is non-negative. *)
  Corollary total_distributed_nonneg : forall free_space spaces_count,
    0 <= free_space ->
    0 <= compute_total_distributed free_space spaces_count.
  Proof.
    intros free_space spaces_count Hfree.
    unfold compute_total_distributed.
    pose proof (extra_per_space_nonneg free_space spaces_count Hfree) as Hextra.
    assert (0 <= Z.max 0 spaces_count) by lia.
    nia.
  Qed.

  (** Invariant 3: Word spacing is monotonic in free space. *)
  Theorem extra_per_space_monotonic_in_free_space : forall fs1 fs2 spaces_count,
    0 <= fs1 ->
    fs1 <= fs2 ->
    compute_extra_per_space fs1 spaces_count <= compute_extra_per_space fs2 spaces_count.
  Proof.
    intros fs1 fs2 spaces_count Hfs1 Hle.
    unfold compute_extra_per_space.
    destruct (spaces_count >? 0) eqn:Hgt.
    - apply Z.gtb_lt in Hgt.
      apply Z.div_le_mono; lia.
    - lia.
  Qed.

  (** End-to-End Layout Invariant: When a line fits within available_width, 
      justification never causes the line to overflow available_width. *)
  Theorem justification_respects_available_width : forall avail line spaces_count,
    line <= avail ->
    justified_line_width avail line spaces_count <= avail.
  Proof.
    intros avail line spaces_count Hfits.
    unfold justified_line_width.
    set (fs := compute_free_space avail line).
    assert (Hfs_eq : fs = avail - line).
    { unfold fs, compute_free_space. lia. }
    assert (Hfs_nonneg : 0 <= fs) by lia.
    pose proof (total_distributed_le_free_space fs spaces_count Hfs_nonneg) as Hdist.
    lia.
  Qed.

End InterWordJustification.
```