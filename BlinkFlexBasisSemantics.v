(* =========================================================================
   BlinkFlexBasisSemantics.v
   Formalization of Chromium Blink Flex Basis & Hypothetical Main Size
   Source: third_party/blink/renderer/core/layout/flex/flexible_box_algorithm.cc
   Specification: W3C CSS Flexible Box Layout Level 1 §9.2
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

Inductive FlexBasisType : Type :=
  | BasisContent
  | BasisAuto
  | BasisFixed (specified_length : Z).

Definition resolve_hypothetical_main_size
    (flex_base_size : Z) (min_main : Z) (max_main : Z) : Z :=
  Z.max min_main (Z.min flex_base_size max_main).

Definition compute_transferred_main_size
    (cross_size : Z) (aspect_ratio_num : Z) (aspect_ratio_den : Z) : Z :=
  if aspect_ratio_den =? 0 then
    cross_size
  else
    (cross_size * aspect_ratio_num) / aspect_ratio_den.

Theorem hypothetical_size_satisfies_bounds :
  forall base_size min_main max_main,
    min_main <= max_main ->
    min_main <= resolve_hypothetical_main_size base_size min_main max_main <= max_main.
Proof.
  intros base_size min_main max_main Hle.
  unfold resolve_hypothetical_main_size.
  lia.
Qed.

Theorem min_overrides_max_in_hypothetical_size :
  forall base_size min_main max_main,
    max_main < min_main ->
    resolve_hypothetical_main_size base_size min_main max_main = min_main.
Proof.
  intros base_size min_main max_main Hlt.
  unfold resolve_hypothetical_main_size.
  lia.
Qed.

Theorem transferred_size_identity_aspect_ratio :
  forall cross_size d,
    0 < d ->
    compute_transferred_main_size cross_size d d = cross_size.
Proof.
  intros cross_size d Hpos.
  unfold compute_transferred_main_size.
  assert (Hneq : (d =? 0) = false) by (apply Z.eqb_neq; lia).
  rewrite Hneq.
  apply Z.div_mul.
  lia.
Qed.

Theorem resolve_hypothetical_main_size_deterministic :
  forall base_s min_s max_s s1 s2,
    s1 = resolve_hypothetical_main_size base_s min_s max_s ->
    s2 = resolve_hypothetical_main_size base_s min_s max_s ->
    s1 = s2.
Proof.
  intros base_s min_s max_s s1 s2 H1 H2.
  subst. reflexivity.
Qed.
