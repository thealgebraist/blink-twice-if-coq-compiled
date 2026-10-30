### Agent 183 Audit Report: Chromium Blink `TextOffsetRange` Slicing

This report details the formalization and invariant verification of `TextOffsetRange` slicing and intersection logic, corresponding to the range manipulation primitives found in Chromium Blink's layout and text fragmentation subsystems (`third_party/blink/renderer/core/layout/`).

---

### 1. Range Intersection Semantics

A `TextOffsetRange` represents a half-open interval $[start, end)$ of UTF-16 code unit offsets within a text node or layout block flow. 

* **Validity:** A range is valid if $start \le end$.
* **Length:** Defined as $end - start$. Under unsigned arithmetic saturation or valid range pre-conditions, if $start \ge end$, the length is $0$.
* **Intersection (Slicing):** Given two ranges $R_1 = [start_1, end_1)$ and $R_2 = [start_2, end_2)$, their raw intersection is bounded by:
  $$start_{int} = \max(start_1, start_2)$$
  $$end_{int} = \min(end_1, end_2)$$
  If $start_{int} \ge end_{int}$, the ranges are disjoint (or touch at a single point), resulting in an empty range where the length is $0$. In canonical form, an empty intersection is normalized such that $end'_{int} = \max(start_{int}, end_{int})$, collapsing the interval to $[start_{int}, start_{int})$.

---

### 2. Core Invariants

For any two ranges $R_1$ and $R_2$, the intersection operation $R_{int} = R_1 \cap R_2$ satisfies two fundamental safety invariants required to prevent out-of-bounds string slicing and buffer over-reads in Blink:

1. **Length Bound Invariant:** The length of the intersected slice never exceeds the length of either parent range:
   $$\text{length}(R_1 \cap R_2) \le \min(\text{length}(R_1), \text{length}(R_2))$$

2. **Containment Invariant:** The intersected range is a strict sub-interval of both parent ranges. For all offsets $x \in \mathbb{N}$:
   $$x \in (R_1 \cap R_2) \iff x \in R_1 \land x \in R_2$$
   And structurally, whenever $R_1 \cap R_2$ is non-empty:
   $$start_1 \le start_{int} \land end_{int} \le end_1$$
   $$start_2 \le start_{int} \land end_{int} \le end_2$$

---

### 3. Rocq / Coq Formalization (`BlinkTextOffsetRangeSliceSemantics.v`)

The following script is fully self-contained and verifies the slicing semantics using the `Lia` (Linear Integer Arithmetic) decision procedure.

```coq
(** 
  File: BlinkTextOffsetRangeSliceSemantics.v
  Audit: Agent 183 - Chromium Blink TextOffsetRange Slicing Semantics
*)

From Coq Require Import Arith PeanoNat Lia Bool.

Record TextOffsetRange : Type := mkRange {
  start : nat;
  end_offset : nat
}.

(** A range is well-formed if start <= end_offset. *)
Definition wf_range (r : TextOffsetRange) : Prop :=
  start r <= end_offset r.

(** Length of a range. Evaluates to 0 if start >= end_offset due to nat subtraction. *)
Definition range_length (r : TextOffsetRange) : nat :=
  end_offset r - start r.

(** Empty predicate: a range is empty if start >= end_offset. *)
Definition is_empty (r : TextOffsetRange) : Prop :=
  start r >= end_offset r.

(** Boolean emptiness check used in runtime assertions. *)
Definition is_empty_b (r : TextOffsetRange) : bool :=
  Nat.leb (end_offset r) (start r).

(** Pointwise containment: offset x lies within [start, end). *)
Definition contains_offset (r : TextOffsetRange) (x : nat) : Prop :=
  start r <= x < end_offset r.

(** Structural containment: r_sub is bounded by r_parent (if non-empty). *)
Definition sub_range (r_sub r_parent : TextOffsetRange) : Prop :=
  ~ is_empty r_sub -> 
  start r_parent <= start r_sub /\ end_offset r_sub <= end_offset r_parent.

(** Raw intersection: [max(s1, s2), min(e1, e2)). *)
Definition raw_intersect (r1 r2 : TextOffsetRange) : TextOffsetRange :=
  mkRange (Nat.max (start r1) (start r2))
          (Nat.min (end_offset r1) (end_offset r2)).

(** Canonical intersection: normalizes empty ranges to [s, s) to preserve wf_range. *)
Definition canonical_intersect (r1 r2 : TextOffsetRange) : TextOffsetRange :=
  let s := Nat.max (start r1) (start r2) in
  let e := Nat.min (end_offset r1) (end_offset r2) in
  mkRange s (Nat.max s e).

(* ========================================================================== *)
(* Verification of Theorems and Invariants                                    *)
(* ========================================================================== *)

Lemma is_empty_b_iff : forall r,
  is_empty_b r = true <-> is_empty r.
Proof.
  intros [s e]. unfold is_empty_b, is_empty. simpl.
  rewrite Nat.leb_le. lia.
Qed.

Lemma empty_length_zero : forall r,
  is_empty r <-> range_length r = 0.
Proof.
  intros [s e]. unfold is_empty, range_length. simpl. lia.
Qed.

Theorem canonical_intersect_wf : forall r1 r2,
  wf_range (canonical_intersect r1 r2).
Proof.
  intros [s1 e1] [s2 e2]. unfold canonical_intersect, wf_range. simpl. lia.
Qed.

Theorem raw_and_canonical_length_eq : forall r1 r2,
  range_length (raw_intersect r1 r2) = range_length (canonical_intersect r1 r2).
Proof.
  intros [s1 e1] [s2 e2].
  unfold range_length, raw_intersect, canonical_intersect. simpl. lia.
Qed.

(** INVARIANT 1: Intersection length <= min(len1, len2) *)
Theorem intersect_length_bound : forall r1 r2,
  range_length (raw_intersect r1 r2) <= Nat.min (range_length r1) (range_length r2).
Proof.
  intros [s1 e1] [s2 e2].
  unfold range_length, raw_intersect. simpl. lia.
Qed.

Theorem canonical_intersect_length_bound : forall r1 r2,
  range_length (canonical_intersect r1 r2) <= Nat.min (range_length r1) (range_length r2).
Proof.
  intros r1 r2.
  rewrite <- raw_and_canonical_length_eq.
  apply intersect_length_bound.
Qed.

(** INVARIANT 2a: Pointwise containment in both parent ranges *)
Theorem intersect_contains_iff : forall r1 r2 x,
  contains_offset (raw_intersect r1 r2) x <->
  contains_offset r1 x /\ contains_offset r2 x.
Proof.
  intros [s1 e1] [s2 e2] x.
  unfold contains_offset, raw_intersect. simpl. lia.
Qed.

Theorem canonical_intersect_contains_iff : forall r1 r2 x,
  contains_offset (canonical_intersect r1 r2) x <->
  contains_offset r1 x /\ contains_offset r2 x.
Proof.
  intros [s1 e1] [s2 e2] x.
  unfold contains_offset, canonical_intersect. simpl. lia.
Qed.

(** INVARIANT 2b: Structural interval containment within both parent ranges *)
Theorem raw_intersect_sub_range_l : forall r1 r2,
  sub_range (raw_intersect r1 r2) r1.
Proof.
  intros [s1 e1] [s2 e2].
  unfold sub_range, raw_intersect, is_empty. simpl. lia.
Qed.

Theorem raw_intersect_sub_range_r : forall r1 r2,
  sub_range (raw_intersect r1 r2) r2.
Proof.
  intros [s1 e1] [s2 e2].
  unfold sub_range, raw_intersect, is_empty. simpl. lia.
Qed.

Theorem canonical_intersect_sub_range_l : forall r1 r2,
  sub_range (canonical_intersect r1 r2) r1.
Proof.
  intros [s1 e1] [s2 e2].
  unfold sub_range, canonical_intersect, is_empty. simpl. lia.
Qed.

Theorem canonical_intersect_sub_range_r : forall r1 r2,
  sub_range (canonical_intersect r1 r2) r2.
Proof.
  intros [s1 e1] [s2 e2].
  unfold sub_range, canonical_intersect, is_empty. simpl. lia.
Qed.

(** Algebraic Properties of Slicing *)
Theorem intersect_comm : forall r1 r2,
  raw_intersect r1 r2 = raw_intersect r2 r1.
Proof.
  intros [s1 e1] [s2 e2]. unfold raw_intersect. simpl.
  f_equal; lia.
Qed.

Theorem intersect_assoc : forall r1 r2 r3,
  raw_intersect (raw_intersect r1 r2) r3 = raw_intersect r1 (raw_intersect r2 r3).
Proof.
  intros [s1 e1] [s2 e2] [s3 e3]. unfold raw_intersect. simpl.
  f_equal; lia.
Qed.

Theorem intersect_idempotent : forall r,
  raw_intersect r r = r.
Proof.
  intros [s e]. unfold raw_intersect. simpl.
  f_equal; lia.
Qed.
```