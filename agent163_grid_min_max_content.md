### Audit Report: Agent 163 — Chromium Blink Grid Track Min/Max Content Contribution vs. CSS Grid 1 §11.5

**Target Implementation:** `third_party/blink/renderer/core/layout/grid/grid_track_sizing_algorithm.cc`  
**Target Specification:** CSS Grid Layout Module Level 1, §11.5 (Resolve Intrinsic Track Sizes)

---

### 1. Calculation of Base Size and Growth Limit

In CSS Grid Layout Level 1 §11.5 (specifically steps 2 and 3 for non-spanning items, and steps 4 and 5 for spanning items), intrinsic track sizing resolves the `base_size` and `growth_limit` of each track by evaluating the grid items placed within it.

#### A. Base Track Size (from Min-Content Contributions)
For a track with an intrinsic minimum track sizing function (`min-content`, `max-content`, `auto`, or `fit-content`), its `base_size` is initialized (commonly to `0`) and progressively increased. 
* **Step 2.1 (Min-Content Minima):** For each item with a span of 1 occupying a track with a `min-content` (or `auto` under certain alignment/overflow constraints) minimum sizing function, the track's `base_size` is updated to:
  $$\text{base\_size}' = \max(\text{base\_size}, \text{min\_content\_contribution}(\text{item}))$$
* **Chromium Blink Implementation:** In `GridTrackSizingAlgorithm::ResolveIntrinsicTrackSizes`, Blink iterates over `GridItemData` grouped by span size. For span-1 items, `IncreaseTrackSizeAccommodatingGridItems` computes the item's min-content contribution via `ContributionSizeForGridItem(..., GridItemContributionType::kForIntrinsicMinimums)` and clamps the track's `base_size` upward.

#### B. Growth Limit (from Max-Content Contributions)
For a track with an intrinsic maximum track sizing function (`min-content`, `max-content`, `auto`, `fit-content`, or `flex` during intrinsic resolution), its `growth_limit` is initially set to $\infty$ (represented in Blink as `kIndefiniteSize` or `-1` until resolved) or `base_size`.
* **Step 2.3 / 2.4 (Max-Content Maxima):** For each span-1 item in a track with a `max-content` (or `auto` / `fit-content`) maximum sizing function, the track's `growth_limit` is updated to:
  $$\text{growth\_limit}' = \max(\text{growth\_limit}, \text{max\_content\_contribution}(\text{item}))$$
  *(Note: If the growth limit was previously $\infty$, it is first initialized to the item's contribution or the track's `base_size` before taking the maximum over all items).*
* **Step 2.5 (Invariant Enforcement):** If at any point after updating `base_size` or `growth_limit`, $\text{growth\_limit} < \text{base\_size}$ (and $\text{growth\_limit} \neq \infty$), then $\text{growth\_limit}$ is set to $\text{base\_size}$.
* **Chromium Blink Implementation:** Blink computes the max-content contribution using `GridItemContributionType::kForMaxContentMaximums`. In `GridSet::IncreaseGrowthLimit` (and finalization passes in `GridTrackSizingAlgorithm`), Blink explicitly enforces `growth_limit = std::max(growth_limit, base_size)`.

---

### 2. Core Invariants

1. **Monotonicity Invariant (`base_size <= growth_limit`):**
   At the conclusion of every sub-step in §11.5 (and enforced explicitly in step 2.5 and throughout extra-space distribution), a track's resolved `growth_limit` is never strictly less than its `base_size`. Even if an item anomaly (e.g., complex subgrid or aspect-ratio clamping edge cases) produces a `max_content_contribution < min_content_contribution`, the algorithm clamps `growth_limit` upward to `base_size`.

2. **Lower-Bound Invariant (Min-Content Dominance):**
   For any track $T$ with an intrinsic minimum sizing function (specifically `min-content`), after processing all span-1 items $I$ placed in $T$, the track's `base_size` is lower-bounded by the largest `min_content_contribution` among all $i \in I$:
   $$\forall i \in I, \quad \text{min\_content\_contribution}(i) \le \text{base\_size}(T)$$

---

### 3. Concrete Rocq / Coq Formalization

Below is the complete, self-contained formalization for `BlinkGridMinMaxContentSemantics.v`, modeling the span-1 intrinsic resolution step and proving both required invariants.

```coq
(** * BlinkGridMinMaxContentSemantics.v
    Formal audit of Chromium Blink Grid Track Min/Max Content Contributions
    against CSS Grid Layout Module Level 1, Section 11.5. *)

Require Import Coq.Arith.Arith.
Require Import Coq.Lists.List.
Require Import Coq.micromega.Lia.
Import ListNotations.

Module BlinkGridMinMaxContentSemantics.

  (** ** 1. Data Structures *)

  (** Represents a grid item's intrinsic size contributions in layout units. *)
  Record GridItemContribution := mkItem {
    min_content_contribution : nat;
    max_content_contribution : nat
  }.

  (** Represents the state of a single Grid Track (or Blink GridSet).
      Note: For resolved intrinsic tracks, growth_limit is modeled as a finite nat
      initialized to at least base_size (matching CSS Grid §11.5 Step 1 & 2.5). *)
  Record TrackState := mkTrack {
    base_size : nat;
    growth_limit : nat
  }.

  (** Initial state of an intrinsic track prior to item resolution (§11.5 Step 1).
      Both base_size and resolved finite growth_limit start at 0. *)
  Definition init_track : TrackState :=
    mkTrack 0 0.

  (** ** 2. Track Sizing Semantics (Blink & CSS Grid §11.5 Step 2) *)

  (** Enforces §11.5 Step 2.5: "If the track's growth limit is now less than
      its base size, increase the growth limit to match the base size." *)
  Definition enforce_growth_limit_invariant (b g : nat) : nat :=
    Nat.max b g.

  (** Updates a track's base_size and growth_limit for a single span-1 item
      assuming intrinsic min-content minimum and max-content maximum sizing functions. *)
  Definition accommodate_item (t : TrackState) (item : GridItemContribution) : TrackState :=
    let new_base := Nat.max (base_size t) (min_content_contribution item) in
    let raw_limit := Nat.max (growth_limit t) (max_content_contribution item) in
    let new_limit := enforce_growth_limit_invariant new_base raw_limit in
    mkTrack new_base new_limit.

  (** Resolves intrinsic track sizes across a list of span-1 grid items.
      Corresponds to Blink's ResolveIntrinsicTrackSizes for span=1. *)
  Definition resolve_intrinsic_track_sizes (items : list GridItemContribution) (t : TrackState) : TrackState :=
    fold_left accommodate_item items t.

  (** ** 3. Lemmas and Helper Properties *)

  Lemma accommodate_item_base_monotonic :
    forall (t : TrackState) (item : GridItemContribution),
      base_size t <= base_size (accommodate_item t item).
  Proof.
    intros t item.
    unfold accommodate_item; simpl.
    apply Nat.le_max_l.
  Qed.

  Lemma fold_base_monotonic :
    forall (items : list GridItemContribution) (t : TrackState),
      base_size t <= base_size (resolve_intrinsic_track_sizes items t).
  Proof.
    induction items as [| item rest IH]; intros t.
    - simpl. lia.
    - simpl.
      pose proof (accommodate_item_base_monotonic t item) as Hstep.
      pose proof (IH (accommodate_item t item)) as Hrest.
      lia.
  Qed.

  (** ** 4. Main Audit Theorems *)

  (** Theorem 1 (Invariant: base_size <= growth_limit):
      Regardless of item contributions (even if max_content < min_content),
      the resolved track state satisfies base_size <= growth_limit. *)
  Theorem base_size_le_growth_limit_step :
    forall (t : TrackState) (item : GridItemContribution),
      base_size (accommodate_item t item) <= growth_limit (accommodate_item t item).
  Proof.
    intros t item.
    unfold accommodate_item, enforce_growth_limit_invariant; simpl.
    apply Nat.le_max_l.
  Qed.

  Theorem base_size_le_growth_limit_invariant :
    forall (items : list GridItemContribution) (t : TrackState),
      base_size t <= growth_limit t ->
      let t' := resolve_intrinsic_track_sizes items t in
      base_size t' <= growth_limit t'.
  Proof.
    induction items as [| item rest IH]; intros t Hinit; simpl.
    - exact Hinit.
    - apply IH.
      apply base_size_le_growth_limit_step.
  Qed.

  Corollary init_track_preserves_growth_limit_invariant :
    forall (items : list GridItemContribution),
      let t' := resolve_intrinsic_track_sizes items init_track in
      base_size t' <= growth_limit t'.
  Proof.
    intros items.
    apply base_size_le_growth_limit_invariant.
    unfold init_track; simpl; lia.
  Qed.

  (** Theorem 2 (Lower-Bound Invariant):
      The resolved track base_size is lower-bounded by every spanning item's
      min-content contribution (and thus by the largest min-content contribution). *)
  Theorem track_base_size_lower_bounded_by_items :
    forall (items : list GridItemContribution) (t : TrackState) (item : GridItemContribution),
      In item items ->
      min_content_contribution item <= base_size (resolve_intrinsic_track_sizes items t).
  Proof.
    induction items as [| x rest IH]; intros t item Hin.
    - contradiction.
    - simpl in Hin. destruct Hin as [Heq | Hin_rest].
      + subst x. simpl.
        assert (Hitem: min_content_contribution item <= base_size (accommodate_item t item)).
        { unfold accommodate_item; simpl. apply Nat.le_max_r. }
        pose proof (fold_base_monotonic rest (accommodate_item t item)) as Hmono.
        lia.
      + simpl.
        apply IH.
        exact Hin_rest.
  Qed.

  (** Definition of the maximum min-content contribution across a list of items. *)
  Fixpoint max_min_content (items : list GridItemContribution) : nat :=
    match items with
    | [] => 0
    | i :: rest => Nat.max (min_content_contribution i) (max_min_content rest)
    end.

  (** Theorem 3 (Largest Spanning Item Lower Bound):
      The resolved track base_size is explicitly >= the maximum min-content
      contribution of all items in the track. *)
  Theorem track_base_size_ge_max_min_content :
    forall (items : list GridItemContribution) (t : TrackState),
      max_min_content items <= base_size (resolve_intrinsic_track_sizes items t).
  Proof.
    induction items as [| item rest IH]; intros t.
    - simpl. lia.
    - simpl.
      apply Nat.max_lub.
      + apply (track_base_size_lower_bounded_by_items (item :: rest) t item).
        simpl. left. reflexivity.
      + apply IH.
  Qed.

End BlinkGridMinMaxContentSemantics.
```