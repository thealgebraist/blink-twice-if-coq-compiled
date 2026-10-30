### 1. Threshold Crossing Semantics

In Chromium Blink's `IntersectionObserver` implementation (evaluating W3C Intersection Observer 1, §3 "Processing Model"), threshold crossings are evaluated by comparing the previous intersection ratio (`old_ratio`) and the current intersection ratio (`new_ratio`) against a configured threshold (`th`).

To model this deterministically in discrete arithmetic without floating-point representation drift, ratios and thresholds in the range $[0.0, 1.0]$ are mapped to integer milli-units in the closed interval $[0, 1000]$.

The boolean predicate defining a threshold crossing is:
$$\text{crossed}(\text{old\_ratio}, \text{new\_ratio}, \text{th}) \triangleq (\text{old\_ratio} < \text{th} \land \text{th} \le \text{new\_ratio}) \lor (\text{new\_ratio} < \text{th} \land \text{th} \le \text{old\_ratio})$$

---

### 2. Core Invariants

1. **Domain Bounds (Milli-units):** All intersection ratios and configured thresholds satisfy the invariant $0 \le x \le 1000$.
2. **Stasis Non-Triggering (Irreflexivity):** If the intersection ratio remains unchanged ($\text{old\_ratio} = \text{new\_ratio}$), no threshold is crossed regardless of the threshold value.
3. **Directional Symmetry:** Crossing a threshold upward ($\text{old\_ratio} \to \text{new\_ratio}$) is logically equivalent to crossing the same threshold downward ($\text{new\_ratio} \to \text{old\_ratio}$).
4. **Strict Traversal:** A threshold crossing occurs if and only if the status of the ratio being at or above the threshold ($\text{ratio} \ge \text{th}$) strictly inverts between the previous and current observations.

---

### 3. Rocq / Coq Formalization (`BlinkIntersectionObserverThresholdSemantics.v`)

```coq
(** * BlinkIntersectionObserverThresholdSemantics.v
    Formal verification of Chromium Blink IntersectionObserver threshold
    crossing semantics against W3C Intersection Observer 1, Section 3.
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Domain Definitions *)

(** Ratios and thresholds are represented in milli-units [0, 1000] *)
Definition valid_milli_unit (x : Z) : Prop :=
  0 <= x <= 1000.

(** Boolean decision procedure for threshold crossing:
    crossed(old_ratio, new_ratio, th) = 
      (old_ratio < th && th <= new_ratio) || (new_ratio < th && th <= old_ratio)
*)
Definition crossed (old_ratio new_ratio th : Z) : bool :=
  ((old_ratio <? th) && (th <=? new_ratio)) ||
  ((new_ratio <? th) && (th <=? old_ratio)).

(** Propositional specification of threshold crossing *)
Definition crossed_spec (old_ratio new_ratio th : Z) : Prop :=
  (old_ratio < th /\ th <= new_ratio) \/
  (new_ratio < th /\ th <= old_ratio).

(** ** 2. Equivalence and Structural Theorems *)

(** Soundness and completeness of the boolean implementation wrt the specification *)
Theorem crossed_iff_spec : forall old_ratio new_ratio th : Z,
  crossed old_ratio new_ratio th = true <-> crossed_spec old_ratio new_ratio th.
Proof.
  intros old_ratio new_ratio th.
  unfold crossed, crossed_spec.
  rewrite orb_true_iff.
  repeat rewrite andb_true_iff.
  repeat rewrite Z.ltb_lt.
  repeat rewrite Z.leb_le.
  reflexivity.
Qed.

(** Invariant: If the ratio does not change, no threshold is crossed *)
Theorem crossed_irreflexive : forall r th : Z,
  crossed r r th = false.
Proof.
  intros r th.
  unfold crossed.
  rewrite orb_false_iff.
  repeat rewrite andb_false_iff.
  repeat rewrite Z.ltb_ge.
  repeat rewrite Z.leb_gt.
  lia.
Qed.

(** Invariant: Crossing detection is symmetric with respect to transition direction *)
Theorem crossed_symmetric : forall r1 r2 th : Z,
  crossed r1 r2 th = crossed r2 r1 th.
Proof.
  intros r1 r2 th.
  unfold crossed.
  apply orb_comm.
Qed.

(** Invariant: A crossing strictly implies that the old and new ratios are distinct *)
Theorem crossed_implies_change : forall old_ratio new_ratio th : Z,
  crossed old_ratio new_ratio th = true ->
  old_ratio <> new_ratio.
Proof.
  intros old_ratio new_ratio th H.
   apply crossed_iff_spec in H.
  unfold crossed_spec in H.
  lia.
Qed.

(** ** 3. Strict Traversal Invariants *)

(** Helper predicate: ratio is at or above the threshold *)
Definition above_th (r th : Z) : bool :=
  th <=? r.

(** Invariant: A threshold is crossed if and only if the boolean state of being
    at-or-above the threshold strictly flips (XOR). *)
Theorem crossed_characterization_xor : forall old_ratio new_ratio th : Z,
  crossed old_ratio new_ratio th = xorb (above_th old_ratio th) (above_th new_ratio th).
Proof.
  intros old_ratio new_ratio th.
  unfold crossed, above_th.
  destruct ( Z.ltb_spec old_ratio th );
  destruct ( Z.leb_spec th new_ratio );
  destruct ( Z.ltb_spec new_ratio th );
  destruct ( Z.leb_spec th old_ratio );
  simpl; try reflexivity; lia.
Qed.

(** Invariant: Under valid milli-unit bounds, if a threshold is crossed, the threshold 
    itself must lie within the half-open interval bounded by the two ratios. *)
Theorem crossed_bounds_traversal : forall old_ratio new_ratio th : Z,
  valid_milli_unit old_ratio ->
  valid_milli_unit new_ratio ->
  valid_milli_unit th ->
  crossed old_ratio new_ratio th = true ->
  Z.min old_ratio new_ratio < th <= Z.max old_ratio new_ratio.
Proof.
  intros old_ratio new_ratio th Hold Hnew Hth Hcross.
  apply crossed_iff_spec in Hcross.
  unfold crossed_spec in Hcross.
  lia.
Qed.

(** Transitivity of non-crossing: If neither step (r1 -> r2) nor (r2 -> r3)
    crosses th, then the composite step (r1 -> r3) does not cross th. *)
Theorem uncrossed_transitive : forall r1 r2 r3 th : Z,
  crossed r1 r2 th = false ->
  crossed r2 r3 th = false ->
  crossed r1 r3 th = false.
Proof.
  intros r1 r2 r3 th H12 H23.
  rewrite crossed_characterization_xor in *.
  destruct (above_th r1 th), (above_th r2 th), (above_th r3 th);
  simpl in *; congruence.
Qed.
```