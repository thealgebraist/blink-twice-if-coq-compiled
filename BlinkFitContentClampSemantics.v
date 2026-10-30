From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Sizing 3 §4 Fit-Content Clamping Formula *)
Definition fit_content_clamp (min_c : Z) (max_c : Z) (avail : Z) : Z :=
  Z.max min_c (Z.min max_c avail).

Theorem fit_content_ge_min : forall min_c max_c avail,
  fit_content_clamp min_c max_c avail >= min_c.
Proof.
  intros. unfold fit_content_clamp.
  apply Z.le_ge. apply Z.le_max_l.
Qed.

Theorem fit_content_le_max : forall min_c max_c avail,
  min_c <= max_c ->
  fit_content_clamp min_c max_c avail <= max_c.
Proof.
  intros min_c max_c avail Hle.
  unfold fit_content_clamp.
  assert (Z.min max_c avail <= max_c) by (apply Z.le_min_l).
  destruct (Z.max_dec min_c (Z.min max_c avail)) as [Hmax | Hmin]; lia.
Qed.

Theorem fit_content_exact_when_within : forall min_c max_c avail,
  min_c <= avail <= max_c ->
  fit_content_clamp min_c max_c avail = avail.
Proof.
  intros min_c max_c avail [H1 H2].
  unfold fit_content_clamp.
  assert (Hmin: Z.min max_c avail = avail).
  { destruct (Z.min_dec max_c avail); lia. }
  rewrite Hmin.
  destruct (Z.max_dec min_c avail); lia.
Qed.
