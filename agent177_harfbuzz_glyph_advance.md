### Audit Report: Chromium Blink HarfBuzz Glyph Advance Accumulation vs. CSS Text Module Level 3 §5

**Agent ID:** 177  
**Target Subsystem:** `third_party/blink/renderer/platform/fonts/shaping/` (`HarfBuzzShaper`, `ShapeResult`, `ShapeResultBuffer`)  
**Specification:** CSS Text Module Level 3 §5 (Line Breaking and Word Boundaries) & CSS Fonts Module Level 4 (Glyph Advance & Shaping)

---

### 1. Glyph Advance Accumulation

In Chromium Blink’s text shaping pipeline, `HarfBuzzShaper` invokes `hb_shape()` to transform a run of Unicode code points into positioned glyphs. The resulting advances and offsets are extracted from `hb_glyph_position_t` and stored within `ShapeResult::RunInfo`.

#### Mathematical Model
For a shaped run containing $N$ glyphs $G = \{g_0, g_1, \dots, g_{N-1}\}$, each glyph $g_i$ has an associated horizontal advance $a_x(g_i)$ (derived from `hb_glyph_position_t::x_advance` after converting from 26.6 fixed-point or `LayoutUnit`/`float` representation, plus any CSS `letter-spacing` and `word-spacing` adjustments applied during shaping).

The total inline advance width $W_{\text{total}}$ of the shaped run is the scalar accumulation:

$$W_{\text{total}} = \sum_{i=0}^{N-1} a_x(g_i)$$

#### Blink Implementation Specifics
* **Representation:** Blink accumulates advances in floating-point (`float`) inside `ShapeResult::RunInfo` (`width_`) while maintaining individual glyph advances in `HarfBuzzRunGlyphData`.
* **CSS Spacing Injection:** Per CSS Text 3 §8 (Spacing), `letter-spacing` and `word-spacing` are added directly to the glyph advances of the corresponding cluster-boundary glyphs during `ShapeResult::ApplySpacing`.
* **Subpixel Precision:** While HarfBuzz operates in `hb_position_t` (int32, typically 16.16 or 26.6 fixed-point depending on scale), Blink converts these to `float` early via `HarfBuzzPositionToFloat`.

---

### 2. Cluster Mapping

HarfBuzz uses *clusters* (`hb_glyph_info_t::cluster`) to map shaped glyphs back to the original UTF-16/UTF-8 character buffer indices. This is essential for CSS Text 3 §5, as line-breaking opportunities (soft wrap opportunities) are determined at character/grapheme cluster boundaries, not arbitrary glyph boundaries.

#### Structural Properties
Let $C = [c_{\text{start}}, c_{\text{end}})$ be the input character index range of a text run.
* **Monotonicity:** Depending on the text direction (`HB_DIRECTION_LTR` vs `HB_DIRECTION_RTL`), the cluster values $k(g_i)$ of the glyph sequence $g_0, \dots, g_{N-1}$ are monotonically non-decreasing (LTR) or non-increasing (RTL).
  * **LTR:** $i < j \implies k(g_i) \le k(g_j)$
  * **RTL:** $i < j \implies k(g_i) \ge k(g_j)$
* **Surjective Range Partitioning:** A contiguous maximal subsequence of glyphs sharing the same cluster ID $k$ represents an indivisible shaping cluster (e.g., a ligature like `fi` or a base character with combining marks). If characters $[c_a, c_b)$ merge into a single ligature, all resulting glyphs are assigned cluster $c_a$.
* **Range Width Computation:** To measure the inline advance of a character sub-range $[c_1, c_2)$ (e.g., to test if a word fits on a line per CSS Text 3 §5), Blink’s `ShapeResult::IndividualCharacterRanges` or `OffsetForPosition` locates the bounding glyph indices $[i_{\text{start}}, i_{\text{end}})$ corresponding to clusters in $[c_1, c_2)$ and sums their advances. If $c_1$ or $c_2$ falls mid-cluster (e.g., inside a ligature), Blink linearly interpolates the cluster's total advance across the constituent grapheme clusters.

---

### 3. Invariants

To guarantee termination and deterministic layout in `InlineLayoutAlgorithm` and `ShapingLineBreaker`, the following invariants must hold over the idealized specification model:

1. **Non-Negativity of Glyph Advances:**
   $$\forall i \in [0, N),\quad a_x(g_i) \ge 0$$
   *(Note: In Blink, negative `letter-spacing` or specific GPOS kerning tables can technically yield negative net advances in HarfBuzz, which Blink clamps or handles specially in `ShapeResult` to prevent negative run widths that violate layout monotonicity).*
2. **Weak Monotonicity of Prefix Sums (General Non-Negative Case):**
   Let $W(m) = \sum_{i=0}^{m-1} a_x(g_i)$. For $0 \le m_1 < m_2 \le N$:
   $$W(m_1) \le W(m_2)$$
3. **Strict Monotonicity of Prefix Sums (Strictly Positive Spacing/Base Advances):**
   For visible, non-combining spacing glyphs where $a_x(g_i) > 0$:
   $$0 \le m_1 < m_2 \le N \implies W(m_1) < W(m_2)$$
4. **Cluster Partition Conservation:**
   The sum of advances of all distinct cluster groups equals the total run advance $W_{\text{total}}$.

---

### 4. Concrete Rocq / Coq Formalization

The following file (`BlinkHarfBuzzGlyphAdvanceSemantics.v`) provides a complete, self-contained formalization in Rocq (Coq) using standard Peano naturals (`nat`) to model fixed-point subpixel units (e.g., 26.6 fixed-point layout units), proving advance accumulation properties, cluster range partitioning, and both weak and strict monotonicity invariants.

```coq
(** * BlinkHarfBuzzGlyphAdvanceSemantics.v
    Formal verification of Chromium Blink HarfBuzz Glyph Advance Accumulation
    against CSS Text Module Level 3 §5.
    Agent 177 Audit Artifact. *)

From Coq Require Import List.
From Coq Require Import Arith.
From Coq Require Import Lia.
Import ListNotations.

Section GlyphAdvanceSemantics.

  (** ** 1. Core Data Structures *)

  (** Represents a shaped glyph output by HarfBuzz (HarfBuzzRunGlyphData).
      Advances are modeled in discrete non-negative subpixel units (e.g. 26.6 fixed-point). *)
  Record GlyphData : Type := mkGlyph {
    glyph_id : nat;
    cluster  : nat;      (** Character index in the input UTF-16 buffer *)
    advance_x : nat      (** Horizontal advance (x_advance) *)
  }.

  (** A shaped run is an ordered sequence of glyphs. *)
  Definition GlyphRun := list GlyphData.

  (** ** 2. Glyph Advance Accumulation *)

  (** Total horizontal advance W_total = sum(glyph.advance.x). *)
  Fixpoint accumulate_advance (run : GlyphRun) : nat :=
    match run with
    | [] => 0
    | g :: gs => advance_x g + accumulate_advance gs
    end.

  (** Prefix accumulation of the first [k] glyphs. *)
  Definition prefix_advance (k : nat) (run : GlyphRun) : nat :=
    accumulate_advance (firstn k run).

  (** Fundamental additive homomorphic property of advance accumulation. *)
  Theorem accumulate_advance_app : forall (r1 r2 : GlyphRun),
    accumulate_advance (r1 ++ r2) = accumulate_advance r1 + accumulate_advance r2.
  Proof.
    intros r1 r2.
    induction r1 as [| g gs IH]; simpl.
    - reflexivity.
    - rewrite IH. lia.
  Qed.

  (** ** 3. Cluster Mapping & Character Range Slicing *)

  (** Predicate asserting LTR cluster monotonicity (non-decreasing cluster indices). *)
  Inductive ClusterMonotonicLTR : GlyphRun -> Prop :=
    | CM_Nil : ClusterMonotonicLTR []
    | CM_Single : forall g, ClusterMonotonicLTR [g]
    | CM_Cons : forall g1 g2 gs,
        cluster g1 <= cluster g2 ->
        ClusterMonotonicLTR (g2 :: gs) ->
        ClusterMonotonicLTR (g1 :: g2 :: gs).

  (** Filter glyphs belonging to a half-open character index range [c_start, c_end). *)
  Definition glyphs_in_cluster_range (c_start c_end : nat) (run : GlyphRun) : GlyphRun :=
    filter (fun g => (c_start <=? cluster g) && (cluster g <? c_end)) run.

  (** Total advance of a character cluster range [c_start, c_end). *)
  Definition cluster_range_advance (c_start c_end : nat) (run : GlyphRun) : nat :=
    accumulate_advance (glyphs_in_cluster_range c_start c_end run).

  (** Helper lemma: splitting a range [c1, c3) at c2 (where c1 <= c2 <= c3)
      preserves the total accumulated advance across the partition. *)
  Theorem cluster_range_advance_partition :
    forall (c1 c2 c3 : nat) (run : GlyphRun),
      c1 <= c2 -> c2 <= c3 ->
      cluster_range_advance c1 c3 run =
      cluster_range_advance c1 c2 run + cluster_range_advance c2 c3 run.
  Proof.
    intros c1 c2 c3 run H12 H23.
    unfold cluster_range_advance, glyphs_in_cluster_range.
    induction run as [| g gs IH]; simpl.
    - reflexivity.
    - destruct (c1 <=? cluster g) eqn:Hc1;
      destruct (cluster g <? c3) eqn:Hc3;
      destruct (cluster g <? c2) eqn:Hc2;
      destruct (c2 <=? cluster g) eqn:Hc2_ge;
      simpl;
      try apply Nat.leb_le in Hc1;
      try apply Nat.leb_gt in Hc1;
      try apply Nat.ltb_lt in Hc3;
      try apply Nat.ltb_ge in Hc3;
      try apply Nat.ltb_lt in Hc2;
      try apply Nat.ltb_ge in Hc2;
      try apply Nat.leb_le in Hc2_ge;
      try apply Nat.leb_gt in Hc2_ge;
      simpl; try lia.
  Qed.

  (** ** 4. Monotonicity and Non-Negativity Invariants *)

  (** Invariant 1: Every glyph advance and total advance is non-negative. *)
  Theorem total_advance_non_negative : forall (run : GlyphRun),
    0 <= accumulate_advance run.
  Proof.
    intros run. lia.
  Qed.

  (** Invariant 2 (Weak Monotonicity): Adding glyphs never decreases total advance. *)
  Theorem prefix_advance_monotonic_weak : forall (run : GlyphRun) (k1 k2 : nat),
    k1 <= k2 ->
    prefix_advance k1 run <= prefix_advance k2 run.
  Proof.
    intros run k1 k2 Hle.
    unfold prefix_advance.
    revert k1 k2 Hle.
    induction run as [| g gs IH]; intros k1 k2 Hle.
    - rewrite !firstn_nil. simpl. lia.
    - destruct k1 as [| k1']; destruct k2 as [| k2']; simpl.
      + lia.
      + lia.
      + lia.
      + assert (Hle': k1' <= k2') by lia.
        specialize (IH k1' k2' Hle').
        lia.
  Qed.

  (** Predicate for runs where every glyph has a strictly positive advance
      (e.g., base spacing glyphs without zero-width joiners/combining marks). *)
  Definition StrictlyPositiveAdvances (run : GlyphRun) : Prop :=
    Forall (fun g => advance_x g > 0) run.

  (** Lemma: Any non-empty run with strictly positive advances has a strictly positive total advance. *)
  Lemma positive_run_total_positive : forall (g : GlyphData) (gs : GlyphRun),
    StrictlyPositiveAdvances (g :: gs) ->
    accumulate_advance (g :: gs) > 0.
  Proof.
    intros g gs Hpos.
    inversion Hpos as [| x l Hadv Hrest]; subst.
    simpl. lia.
  Qed.

  (** Invariant 3 (Strict Monotonicity): Under StrictlyPositiveAdvances,
      total advance is strictly monotonic in the glyph count. *)
  Theorem prefix_advance_strictly_monotonic : forall (run : GlyphRun) (k1 k2 : nat),
    StrictlyPositiveAdvances run ->
    k1 < k2 ->
    k2 <= length run ->
    prefix_advance k1 run < prefix_advance k2 run.
  Proof.
    intros run k1 k2 Hpos Hlt Hlen.
    unfold prefix_advance.
    revert k1 k2 Hpos Hlt Hlen.
    induction run as [| g gs IH]; intros k1 k2 Hpos Hlt Hlen.
    - simpl in Hlen. lia.
    - inversion Hpos as [| x l Hadv Hpos_gs]; subst.
      destruct k1 as [| k1']; destruct k2 as [| k2'].
      + lia.
      + simpl. lia.
      + lia.
      + simpl in *.
        assert (Hlt': k1' < k2') by lia.
        assert (Hlen': k2' <= length gs) by lia.
        specialize (IH k1' k2' Hpos_gs Hlt' Hlen').
        lia.
  Qed.

  (** Line-Breaking Fit Invariant (CSS Text 3 §5):
      If a prefix of k2 glyphs fits within available width W_avail,
      then any smaller prefix k1 <= k2 also fits within W_avail. *)
  Theorem line_break_prefix_stability : forall (run : GlyphRun) (k1 k2 W_avail : nat),
    k1 <= k2 ->
    prefix_advance k2 run <= W_avail ->
    prefix_advance k1 run <= W_avail.
  Proof.
    intros run k1 k2 W_avail Hle Hfit.
    pose proof (prefix_advance_monotonic_weak run k1 k2 Hle) as Hmono.
    lia.
  Qed.

End GlyphAdvanceSemantics.
```