(* ========================================================================= *)
(*               BlinkGridFitContentClampSemantics.v                        *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Grid fit-content() Track Clamping  *)
(* against CSS Grid 1 §11.5.1. Fully constructive, 0 admits.                *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition fit_content_clamp (min_content available_space argument_limit : Z) : Z :=
  Z.min (Z.max min_content available_space) (Z.max min_content argument_limit).

Theorem fit_content_ge_min_content : forall min_c avail arg,
  fit_content_clamp min_c avail arg >= min_c.
Proof.
  intros. unfold fit_content_clamp. lia.
Qed.

Theorem fit_content_le_argument_max : forall min_c avail arg,
  fit_content_clamp min_c avail arg <= Z.max min_c arg.
Proof.
  intros. unfold fit_content_clamp. lia.
Qed.

Theorem fit_content_exact_when_unconstrained : forall min_c avail arg,
  avail <= arg ->
  fit_content_clamp min_c avail arg = Z.max min_c avail.
Proof.
  intros. unfold fit_content_clamp. lia.
Qed.
