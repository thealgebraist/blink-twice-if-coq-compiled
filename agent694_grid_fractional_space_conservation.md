# Formal Verification Report: CSS Grid `fr` Fractional Track Space Conservation
**Agent:** 694 (W3C/WHATWG Layout Rules — Grid, Tables, Shapes)  
**Target Theory:** `BlinkGridFractionalSpaceConservationSemantics.v`  
**Chromium Component:** `third_party/blink/renderer/core/layout/grid/grid_track_collection.cc`  
**Specification:** CSS Grid Layout Module Level 1, §11.7.1 (Find the Size of an `fr`)

---

## 1. Normative W3C Specification Requirements

In the **CSS Grid Layout Module Level 1**, §11.7 (*Expand Flexible Tracks*) and §11.7.1 (*Find the Size of an `fr`*), the track sizing algorithm distributes leftover available grid container space among flexible tracks sized with `<flex>` (`fr`) units.

### Normative Rules (§11.7.1)
Given a set of flexible grid tracks $T = \{1, \dots, n\}$ with flex factors $\{f_1, \dots, f_n\}$ where $f_i > 0$, and non-negative leftover space $A \ge 0$ (`leftover space`):

1. **Flex Factor Sum:** Let $F = \max\left(1, \sum_{i=1}^n f_i\right)$ (or in normalized fixed-point/integer scaled space where $\sum f_i \ge F_{\text{min}}$, let $F = \sum_{i=1}^n f_i > 0$ when $\sum f_i \ge 1$).
2. **Hypothetical `fr` Size:** The hypothetical size of a 1`fr` unit is $S_{\text{fr}} = \frac{A}{F}$.
3. **Track Share Allocation:** Each flexible track $i$ with flex factor $f_i$ receives an allocated share of the available space:
   $$\text{share}(f_i, F, A) = \left\lfloor \frac{f_i \cdot A}{F} \right\rfloor$$
4. **Space Conservation Invariant:** Because subpixel layout in Blink uses fixed-point integers (`LayoutUnit`, representing $\frac{1}{64}$th of a CSS pixel), truncation/floor rounding occurs per track. The fundamental conservation law required by the layout engine to prevent unintended container overflow is:
   $$\sum_{i=1}^n \text{share}(f_i, F, A) \le A$$
   Furthermore, the unallocated remainder due to quantization is strictly bounded by the number of tracks:
   $$A - \sum_{i=1}^n \text{share}(f_i, F, A) < n$$

---

## 2. Chromium Blink Implementation & Invariants

In Chromium's LayoutNG Grid implementation (`third_party/blink/renderer/core/layout/grid/`), track sizing and `fr` distribution are governed by `GridTrackSizingAlgorithm` and `GridLayoutTrackCollection` (`grid_track_collection.cc` and `grid_sizing_tree.cc`).

### Implementation Mechanics
1. **`LayoutUnit` Fixed-Point Arithmetic:**
   Available space $A$ (`free_space`) is represented as a non-negative `LayoutUnit` (backed by a 32-bit or 64-bit integer in raw subpixel units).
2. **Flex Factor Scaling:**
   Each track's `flex_factor` ($f_i$) is a positive `double`/`float` or scaled integer. When computing individual track shares in integer subpixels (or when scaling flex factors to integer weights $f_i \in \mathbb{Z}_{\ge 0}$):
   ```cpp
   // Conceptual fixed-point / integer share calculation in Blink Grid:
   // Given leftover free_space >= 0 and total_flex_factor >= sum(track_flex_i):
   LayoutUnit track_share = LayoutUnit::FromRawValue(
       (track_flex_i * free_space.RawValue()) / total_flex_factor);
   ```
3. **Critical Engine Invariants:**
   - **Non-Negativity Invariant:** For all $f_i \ge 0$, $A \ge 0$, and $F > 0$, each allocated track share is $\ge 0$.
   - **Monotonicity Invariant:** Increasing available space $A$ or flex factor $f_i$ never decreases the allocated share.
   - **Conservation Invariant:** If $F \ge \sum_{i=1}^n f_i$ and $F > 0$, then the sum of all allocated track shares never exceeds $A$:
     $$\sum_{i=1}^n \left( (f_i \cdot A) \div F \right) \le A$$
   - **Exactness under Divisibility:** When $F = \sum_{i=1}^n f_i$, the lost subpixel remainder is $\sum_{i=1}^n ((f_i \cdot A) \bmod F) \div F$, which is strictly bounded by $n$.

---

## 3. Formal Specification in Rocq / Coq

We model `LayoutUnit` raw subpixel values and scaled integer flex weights in $\mathbb{Z}$ (`ZArith`).

- `avail : Z` represents the raw subpixel value of `free_space` ($A \ge 0$).
- `frs : list Z` represents the list of non-negative scaled flex factors $[f_1; \dots; f_n]$.
- `total_fr : Z` represents the denominator $F$ (either $\sum f_i$ or $\max(\text{scale}, \sum f_i) \ge \sum f_i$).

---

## 4. Formal Verification Theory (`BlinkGridFractionalSpaceConservationSemantics.v`)

Below is the complete, self-contained, admitted-free Rocq/Coq verification module establishing the space conservation, non-negativity, remainder identity, and tight error bound theorems.

```coq
(** * BlinkGridFractionalSpaceConservationSemantics.v
    Formal Verification of CSS Grid Layout 1 §11.7.1 Fractional (fr) Track
    Space Conservation in Chromium Blink (grid_track_collection.cc). *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

Section GridFractionalSpaceConservation.

  (** ** 1. Formal Definitions *)

  (** Individual track share for a flex factor [fr_i], total flex [total_fr],
      and available leftover space [avail]. *)
  Definition fr_share (fr_i total_fr avail : Z) : Z :=
    (fr_i * avail) / total_fr.

  (** Individual track truncation remainder (subpixel quantization loss). *)
  Definition fr_rem (fr_i total_fr avail : Z) : Z :=
    (fr_i * avail) mod total_fr.

  (** Sum of a list of integers. *)
  Fixpoint sum_list (l : list Z) : Z :=
    match l with
    | [] => 0
    | x :: xs => x + sum_list xs
    end.

  (** Map [fr_share] across all tracks in the collection. *)
  Definition fr_shares (frs : list Z) (total_fr avail : Z) : list Z :=
    map (fun fr_i => fr_share fr_i total_fr avail) frs.

  (** Sum of all allocated fractional track shares. *)
  Definition sum_fr_shares (frs : list Z) (total_fr avail : Z) : Z :=
    sum_list (fr_shares frs total_fr avail).

  (** Sum of all track remainders. *)
  Definition sum_fr_rems (frs : list Z) (total_fr avail : Z) : Z :=
    sum_list (map (fun fr_i => fr_rem fr_i total_fr avail) frs).

  (** Predicate asserting all flex factors in the track list are non-negative. *)
  Definition all_nonneg (l : list Z) : Prop :=
    Forall (fun x => 0 <= x) l.

  (** ** 2. Helper Lemmas *)

  (** Non-negativity of sum_list when all elements are non-negative. *)
  Lemma sum_list_nonneg : forall (l : list Z),
    all_nonneg l -> 0 <= sum_list l.
  Proof.
    intros l H.
    induction H as [| x xs Hx Hxs IH].
    - simpl. lia.
    - simpl. lia.
  Qed.

  (** Non-negativity of a single track's fr_share. *)
  Lemma fr_share_nonneg : forall (fr_i total_fr avail : Z),
    0 <= fr_i ->
    0 < total_fr ->
    0 <= avail ->
    0 <= fr_share fr_i total_fr avail.
  Proof.
    intros fr_i total_fr avail Hfr Htot Havail.
    unfold fr_share.
    apply Z.div_pos.
    - apply Z.mul_nonneg_nonneg; lia.
    - lia.
  Qed.

  (** Non-negativity of a single track's remainder. *)
  Lemma fr_rem_nonneg : forall (fr_i total_fr avail : Z),
    0 < total_fr ->
    0 <= fr_rem fr_i total_fr avail.
  Proof.
    intros fr_i total_fr avail Htot.
    unfold fr_rem.
    destruct (Z_mod_lt (fr_i * avail) total_fr) as [Hle _]; lia.
  Qed.

  (** Strict upper bound of a single track's remainder. *)
  Lemma fr_rem_lt_total : forall (fr_i total_fr avail : Z),
    0 < total_fr ->
    fr_rem fr_i total_fr avail < total_fr.
  Proof.
    intros fr_i total_fr avail Htot.
    unfold fr_rem.
    destruct (Z_mod_lt (fr_i * avail) total_fr) as [_ Hlt]; lia.
  Qed.

  (** Fundamental Euclidean decomposition for a single track allocation:
      fr_i * avail = total_fr * fr_share + fr_rem. *)
  Lemma fr_share_rem_eq : forall (fr_i total_fr avail : Z),
    0 < total_fr ->
    fr_i * avail = total_fr * fr_share fr_i total_fr avail + fr_rem fr_i total_fr avail.
  Proof.
    intros fr_i total_fr avail Htot.
    unfold fr_share, fr_rem.
    apply Z_div_mod_eq_full.
  Qed.

  (** Fundamental Euclidean decomposition across a list of tracks:
      (sum_list frs) * avail = total_fr * (sum_fr_shares frs) + (sum_fr_rems frs). *)
  Lemma sum_fr_shares_rems_identity : forall (frs : list Z) (total_fr avail : Z),
    0 < total_fr ->
    (sum_list frs) * avail =
      total_fr * sum_fr_shares frs total_fr avail + sum_fr_rems frs total_fr avail.
  Proof.
    intros frs total_fr avail Htot.
    induction frs as [| f fs IH].
    - simpl. unfold sum_fr_shares, sum_fr_rems, fr_shares. simpl. lia.
    - unfold sum_fr_shares, sum_fr_rems, fr_shares in *.
      simpl in *.
      pose proof (fr_share_rem_eq f total_fr avail Htot) as Hdecomp.
      lia.
  Qed.

  (** Sum of remainders is always non-negative. *)
  Lemma sum_fr_rems_nonneg : forall (frs : list Z) (total_fr avail : Z),
    0 < total_fr ->
    0 <= sum_fr_rems frs total_fr avail.
  Proof.
    intros frs total_fr avail Htot.
    induction frs as [| f fs IH].
    - unfold sum_fr_rems. simpl. lia.
    - unfold sum_fr_rems in *. simpl in *.
      pose proof (fr_rem_nonneg f total_fr avail Htot) as Hrem.
      lia.
  Qed.

  (** Sum of remainders is bounded by (length frs) * total_fr. *)
  Lemma sum_fr_rems_upper_bound : forall (frs : list Z) (total_fr avail : Z),
    0 < total_fr ->
    sum_fr_rems frs total_fr avail <= Z.of_nat (length frs) * (total_fr - 1).
  Proof.
    intros frs total_fr avail Htot.
    induction frs as [| f fs IH].
    - unfold sum_fr_rems. simpl. lia.
    - unfold sum_fr_rems in *. simpl in *.
      pose proof (fr_rem_lt_total f total_fr avail Htot) as Hlt.
      replace (Z.of_nat (S (length fs))) with (1 + Z.of_nat (length fs)) by lia.
      lia.
  Qed.

  (** ** 3. Main Conservation & Layout Invariant Theorems *)

  (** Theorem 1: Non-negativity of total allocated fractional space. *)
  Theorem sum_fr_shares_nonneg : forall (frs : list Z) (total_fr avail : Z),
    all_nonneg frs ->
    0 < total_fr ->
    0 <= avail ->
    0 <= sum_fr_shares frs total_fr avail.
  Proof.
    intros frs total_fr avail Hnonneg Htot Havail.
    induction Hnonneg as [| f fs Hf Hfs IH].
    - unfold sum_fr_shares, fr_shares. simpl. lia.
    - unfold sum_fr_shares, fr_shares in *. simpl in *.
      pose proof (fr_share_nonneg f total_fr avail Hf Htot Havail) as Hshare.
      lia.
  Qed.

  (** Theorem 2 (Exact Flex Sum Conservation):
      When [total_fr = sum_list frs] and [0 < total_fr], the sum of fractional
      track shares never exceeds [avail]. *)
  Theorem fr_space_conservation_exact : forall (frs : list Z) (total_fr avail : Z),
    total_fr = sum_list frs ->
    0 < total_fr ->
    0 <= avail ->
    sum_fr_shares frs total_fr avail <= avail.
  Proof.
    intros frs total_fr avail Heq Htot Havail.
    pose proof (sum_fr_shares_rems_identity frs total_fr avail Htot) as Hid.
    pose proof (sum_fr_rems_nonneg frs total_fr avail H