From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(** * Synthesized Rocq/Coq Theory for Non-Trivial Python: TimSort Run Stack Invariant
    Synthesized autonomously from Python AST by PythonToCoqTranspiler.
    Algorithm: CPython TimSort pending run collapsing invariant (Objects/listobject.c).
*)

Definition timsort_collapse_triplet (r0 r1 r2 : Z) : (Z * Z * bool) :=
  if r0 <=? r1 + r2 then
    if r0 <? r2 then
      (r0 + r1, r2, true)
    else
      (r0, r1 + r2, true)
  else
    if r1 <=? r2 then
      (r0, r1 + r2, true)
    else
      (r0, r1, false).

(** THEOREM 1: Total Resource Conservation Law (Conservation of Elements)
    The sum of run lengths is strictly preserved under collapse.
*)
Theorem timsort_collapse_resource_conservation :
  forall r0 r1 r2 : Z,
    let '(new_r0, new_r1, merged) := timsort_collapse_triplet r0 r1 r2 in
    merged = true ->
    new_r0 + new_r1 = r0 + r1 + r2 \/
    new_r0 + new_r1 = r0 + (r1 + r2).
Proof.
  intros r0 r1 r2.
  unfold timsort_collapse_triplet.
  destruct (r0 <=? r1 + r2) eqn:H0.
  - destruct (r0 <? r2) eqn:H1.
    + intros Hmerge. left. ring.
    + intros Hmerge. right. ring.
  - destruct (r1 <=? r2) eqn:H2.
    + intros Hmerge. right. ring.
    + intros Hmerge. discriminate.
Qed.

(** THEOREM 2: Non-Negativity Invariant Preservation
    If input runs are strictly positive, the collapsed runs remain strictly positive.
*)
Theorem timsort_collapse_positive_preservation :
  forall r0 r1 r2 : Z,
    r0 > 0 -> r1 > 0 -> r2 > 0 ->
    let '(new_r0, new_r1, merged) := timsort_collapse_triplet r0 r1 r2 in
    new_r0 > 0 /\ new_r1 > 0.
Proof.
  intros r0 r1 r2 H0 H1 H2.
  unfold timsort_collapse_triplet.
  destruct (r0 <=? r1 + r2).
  - destruct (r0 <? r2); simpl; lia.
  - destruct (r1 <=? r2); simpl; lia.
Qed.

(** THEOREM 3: Idempotence & Quiescence on Balanced Input
    If the TimSort invariants (r0 > r1 + r2 and r1 > r2) already hold,
    the function performs no collapse (merged = false) and leaves runs unchanged.
*)
Theorem timsort_collapse_quiescence_on_balanced :
  forall r0 r1 r2 : Z,
    r0 > r1 + r2 ->
    r1 > r2 ->
    timsort_collapse_triplet r0 r1 r2 = (r0, r1, false).
Proof.
  intros r0 r1 r2 Hinv1 Hinv2.
  unfold timsort_collapse_triplet.
  assert (Hle0: (r0 <=? r1 + r2) = false) by (apply Z.leb_gt; lia).
  assert (Hle1: (r1 <=? r2) = false) by (apply Z.leb_gt; lia).
  rewrite Hle0, Hle1.
  reflexivity.
Qed.

(** THEOREM 4: Strict Progress Property
    Whenever an invariant is violated, a merge is guaranteed to occur (merged = true).
*)
Theorem timsort_collapse_progress :
  forall r0 r1 r2 : Z,
    (r0 <= r1 + r2 \/ r1 <= r2) ->
    let '(_, _, merged) := timsort_collapse_triplet r0 r1 r2 in
    merged = true.
Proof.
  intros r0 r1 r2 Hviol.
  unfold timsort_collapse_triplet.
  destruct (r0 <=? r1 + r2) eqn:H0.
  - destruct (r0 <? r2); reflexivity.
  - apply Z.leb_gt in H0.
    destruct (r1 <=? r2) eqn:H1.
    + reflexivity.
    + apply Z.leb_gt in H1.
      destruct Hviol as [Hviol0 | Hviol1]; lia.
Qed.
