### 1. Audit Summary: Chromium Blink `ShapeResult` Run Splitting vs. CSS Text 3 §5

In Chromium Blink’s LayoutNG text shaping pipeline (`third_party/blink/renderer/platform/fonts/shaping/shape_result.cc`), `ShapeResult::RunInfo` encapsulates a contiguous shaped glyph run produced by HarfBuzz. Under **CSS Text Module Level 3 §5 (Line Breaking and Word Boundaries)**, line breaking must occur at soft wrap opportunities without corrupting glyph positioning, ligatures, or metrics when no re-shaping is required across the break boundary (or prior to boundary re-shaping).

#### 1.1 Run Splitting at Offset $i$
When `ShapeResult::SubRange(start_offset, end_offset)` or line-breaking logic splits a `RunInfo` spanning DOM/text offsets $[S, E)$ at a split offset $i$ where $S \le i \le E$:
* **Left Sub-Run (`left_run`)**: Contains all glyphs whose cluster character offsets fall strictly within $[S, i)$. Its `start_index_` is $S$, and its `num_characters_` is $i - S$.
* **Right Sub-Run (`right_run`)**: Contains all glyphs whose cluster character offsets fall within $[i, E)$. Its `start_index_` is $i$, and its `num_characters_` is $E - i$.

*Note on Grapheme Clusters / Ligatures*: Blink's `RunInfo::CreateSubRun` snaps or requires $i$ to align with a safe-to-break or cluster boundary; within the discrete glyph array model, each glyph $g$ carries a relative character index $g_{\text{char}} \in [0, E - S)$. Splitting at $i$ partitions the glyph list at the threshold $k = i - S$.

#### 1.2 Core Structural Invariants
1. **Character Conservation**:
   $$\text{left\_chars} + \text{right\_chars} = (i - S) + (E - i) = E - S = \text{total\_chars}$$
2. **Advance Width Conservation**:
   Because CSS Text 3 §5 mandates that the measure of a line equals the sum of the advances of its constituent runs, the sum of the inline advance widths of the partitioned glyph vectors must equal the original run's advance width:
   $$\text{left\_width} + \text{right\_width} = \sum_{g \in \text{left}} \text{adv}(g) + \sum_{g \in \text{right}} \text{adv}(g) = \text{total\_width}$$

---

### 2. Concrete Rocq / Coq Formalization (`BlinkShapeResultRunSplitSemantics.v`)

The following file is self-contained and compiles cleanly in Coq / Rocq (8.16+). It models `GlyphData`, `RunInfo`, the run-splitting operation `split_run_at`, and proves both character and width conservation invariants alongside range boundary properties.

```coq
(** * BlinkShapeResultRunSplitSemantics.v
    Formal Audit of Chromium Blink ShapeResult::RunInfo Splitting
    against CSS Text Module Level 3 §5 (Line Breaking & Run Partitioning).
    Agent 179 Audit Artifact. *)

From Coq Require Import Arith PeanoNat List Lia Bool.
Import ListNotations.

(** ** 1. Data Structures Modeling Blink's ShapeResult::RunInfo *)

(** In Blink, HarfBuzz advances are represented in fixed-point (LayoutUnit / float).
    We model inline advance widths in abstract non-negative subpixel units (nat)
    to verify exact algebraic conservation free of floating-point rounding drift. *)
Record GlyphData : Type := mkGlyph {
  glyph_id : nat;
  (** Character offset relative to the run's start_index *)
  char_index : nat;
  (** Inline advance width of the glyph *)
  advance : nat
}.

Record RunInfo : Type := mkRunInfo {
  start_index : nat;
  num_characters : nat;
  glyphs : list GlyphData;
  width : nat
}.

(** Total advance width computed from a list of glyphs. *)
Fixpoint sum_advances (gs : list GlyphData) : nat :=
  match gs with
  | [] => 0
  | g :: rest => advance g + sum_advances rest
  end.

(** A RunInfo is well-formed if:
    1. Its cached width equals the sum of its glyph advances.
    2. Every glyph's relative char_index is strictly within [0, num_characters). *)
Definition wf_run (r : RunInfo) : Prop :=
  width r = sum_advances (glyphs r) /\
  Forall (fun g => char_index g < num_characters r) (glyphs r).

(** End offset of a run in text coordinates. *)
Definition end_index (r : RunInfo) : nat :=
  start_index r + num_characters r.

(** ** 2. Run Splitting Semantics at Offset [i] *)

(** When splitting a run at absolute text offset [i], where [start_index r <= i <= end_index r],
    the relative split offset within the run is [rel_i = i - start_index r].
    - Left run receives glyphs with [char_index g < rel_i]
    - Right run receives glyphs with [char_index g >= rel_i], with their relative
      [char_index] shifted down by [rel_i] so they are relative to the new start [i]. *)

Definition is_left_glyph (rel_i : nat) (g : GlyphData) : bool :=
  char_index g <? rel_i.

Definition is_right_glyph (rel_i : nat) (g : GlyphData) : bool :=
  rel_i <=? char_index g.

Definition shift_glyph (rel_i : nat) (g : GlyphData) : GlyphData :=
  mkGlyph (glyph_id g) (char_index g - rel_i) (advance g).

Definition split_run_at (r : RunInfo) (i : nat) : RunInfo * RunInfo :=
  let rel_i := i - start_index r in
  let left_gs := filter (is_left_glyph rel_i) (glyphs r) in
  let right_gs_raw := filter (is_right_glyph rel_i) (glyphs r) in
  let right_gs := map (shift_glyph rel_i) right_gs_raw in
  let left_run := mkRunInfo
                    (start_index r)
                    rel_i
                    left_gs
                    (sum_advances left_gs) in
  let right_run := mkRunInfo
                     i
                     (end_index r - i)
                     right_gs
                     (sum_advances right_gs) in
  (left_run, right_run).

(** ** 3. Auxiliary Lemmas on Glyph Filtering and Shifting *)

Lemma sum_advances_map_shift : forall (rel_i : nat) (gs : list GlyphData),
  sum_advances (map (shift_glyph rel_i) gs) = sum_advances gs.
Proof.
  intros rel_i gs.
  induction gs as [| g rest IH]; simpl.
  - reflexivity.
  - rewrite IH. reflexivity.
Qed.

Lemma filter_partition_advances : forall (rel_i : nat) (gs : list GlyphData),
  sum_advances (filter (is_left_glyph rel_i) gs) +
  sum_advances (filter (is_right_glyph rel_i) gs) =
  sum_advances gs.
Proof.
  intros rel_i gs.
  induction gs as [| g rest IH]; simpl.
  - reflexivity.
  - unfold is_left_glyph, is_right_glyph.
    destruct (Nat.ltb_spec (char_index g) rel_i) as [Hlt | Hge];
    destruct (Nat.leb_spec rel_i (char_index g)) as [Hle | Hgt].
    + exfalso. lia.
    + simpl. lia.
    + simpl. lia.
    + exfalso. lia.
Qed.

(** ** 4. Main Audit Theorems (Invariants 1 & 2) *)

(** Theorem 1: Range Partitioning [start, i) and [i, end) *)
Theorem split_run_range_boundaries :
  forall (r : RunInfo) (i : nat),
    start_index r <= i ->
    i <= end_index r ->
    let (left_run, right_run) := split_run_at r i in
    start_index left_run = start_index r /\
    end_index left_run = i /\
    start_index right_run = i /\
    end_index right_run = end_index r.
Proof.
  intros r i Hstart Hend.
  unfold split_run_at, end_index in *.
  simpl.
  repeat split; lia.
Qed.

(** Theorem 2: Character Conservation Invariant
    left_chars + right_chars = total_chars *)
Theorem split_run_char_conservation :
  forall (r : RunInfo) (i : nat),
    start_index r <= i ->
    i <= end_index r ->
    let (left_run, right_run) := split_run_at r i in
    num_characters left_run + num_characters right_run = num_characters r.
Proof.
  intros r i Hstart Hend.
  unfold split_run_at, end_index in *.
  simpl.
  lia.
Qed.

(** Theorem 3: Advance Width Conservation Invariant
    left_width + right_width = total_width *)
Theorem split_run_width_conservation :
  forall (r : RunInfo) (i : nat),
    wf_run r ->
    let (left_run, right_run) := split_run_at r i in
    width left_run + width right_run = width r.
Proof.
  intros r i [Hwidth _].
  unfold split_run_at.
  simpl.
  rewrite sum_advances_map_shift.
  rewrite filter_partition_advances.
  symmetry. exact Hwidth.
Qed.

(** Theorem 4: Well-Formedness Preservation
    Both resulting sub-runs satisfy the [wf_run] invariant. *)
Theorem split_run_preserves_wf :
  forall (r : RunInfo) (i : nat),
    wf_run r ->
    start_index r <= i ->
    i <= end_index r ->
    let (left_run, right_run) := split_run_at r i in
    wf_run left_run /\ wf_run right_run.
Proof.
  intros r i [Hwidth Hchars] Hstart Hend.
  unfold split_run_at, wf_run, end_index in *.
  simpl.
  split; split; try reflexivity.
  - (* Left run glyph character indices < i - start_index r *)
    rewrite Forall_forall in *.
    intros g Hg.
    apply filter_In in Hg as [_ Hleft].
    unfold is_left_glyph in Hleft.
    apply Nat.ltb_lt in Hleft.
    exact Hleft.
  - (* Right run glyph character indices < end_index r - i *)
    rewrite Forall_forall in *.
    intros g Hg.
    apply in_map_iff in Hg as [g0 [Heq Hfilt]].
    subst g. simpl.
    apply filter_In in Hfilt as [Hin Hright].
    unfold is_right_glyph in Hright.
    apply Nat.leb_le in Hright.
    specialize (Hchars g0 Hin).
    lia.
Qed.
```