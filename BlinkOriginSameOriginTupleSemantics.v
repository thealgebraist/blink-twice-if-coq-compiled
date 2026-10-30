Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Same-Origin Tuple Equivalence Semantics *)
(** HTML Standard §7.5 / RFC 6454: Origin := (scheme, host, port) *)

Record OriginTuple := {
  origin_scheme : Z;
  origin_host   : Z;
  origin_port   : Z
}.

Definition same_origin (o1 o2 : OriginTuple) : bool :=
  (origin_scheme o1 =? origin_scheme o2) &&
  (origin_host o1 =? origin_host o2) &&
  (origin_port o1 =? origin_port o2).

Theorem same_origin_refl : forall o,
  same_origin o o = true.
Proof.
  intros [s h p].
  unfold same_origin. cbn [origin_scheme origin_host origin_port].
  rewrite !Z.eqb_refl.
  reflexivity.
Qed.

Theorem same_origin_sym : forall o1 o2,
  same_origin o1 o2 = same_origin o2 o1.
Proof.
  intros [s1 h1 p1] [s2 h2 p2].
  unfold same_origin. cbn [origin_scheme origin_host origin_port].
  destruct (s1 =? s2) eqn:Hs;
  destruct (s2 =? s1) eqn:Hs2;
  destruct (h1 =? h2) eqn:Hh;
  destruct (h2 =? h1) eqn:Hh2;
  destruct (p1 =? p2) eqn:Hp;
  destruct (p2 =? p1) eqn:Hp2; auto;
  try (apply Z.eqb_eq in Hs; apply Z.eqb_neq in Hs2; subst; lia);
  try (apply Z.eqb_eq in Hs2; apply Z.eqb_neq in Hs; subst; lia);
  try (apply Z.eqb_eq in Hh; apply Z.eqb_neq in Hh2; subst; lia);
  try (apply Z.eqb_eq in Hh2; apply Z.eqb_neq in Hh; subst; lia);
  try (apply Z.eqb_eq in Hp; apply Z.eqb_neq in Hp2; subst; lia);
  try (apply Z.eqb_eq in Hp2; apply Z.eqb_neq in Hp; subst; lia).
Qed.
