Require Import Bool.

(** * Blink CSP Directive List Intersection Semantics *)
(** CSP Level 3 §4: multiple policies enforce conjunction / intersection *)

Definition csp_effective_allow (p1 p2 : bool) : bool :=
  p1 && p2.

Theorem csp_intersection_strictest : forall p1 p2,
  csp_effective_allow p1 p2 = true ->
  p1 = true /\ p2 = true.
Proof.
  intros p1 p2 H.
  unfold csp_effective_allow in H.
  apply andb_prop in H.
  exact H.
Qed.

Theorem csp_single_violation_blocks : forall p,
  csp_effective_allow false p = false.
Proof.
  intros p. reflexivity.
Qed.
