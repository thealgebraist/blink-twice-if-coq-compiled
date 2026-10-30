(**
  BlinkPercentageResolutionSemantics.v
  Formal specification of Chromium Blink percentage logical height and indefinite sizing resolution
  derived from third_party/blink/renderer/core/layout/layout_box.cc (ComputePercentageLogicalHeight)
  according to W3C CSS Box Sizing Module Level 3 (§5.2 Resolving Percentage Values in Indefinite Containing Blocks).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

(** 1. Definite vs Indefinite Containing Block Basis *)

Definition resolve_percentage_height (cb_height : option Z) (percentage : Z) : option Z :=
  match cb_height with
  | None => None
  | Some h =>
      if h <? 0 then Some 0
      else Some (h * percentage / 100)
  end.

Definition clamp_height (val min_h : Z) (max_h : option Z) : Z :=
  let clamped_min := Z.max val min_h in
  match max_h with
  | None => clamped_min
  | Some mx =>
      let effective_max := Z.max mx min_h in
      Z.min clamped_min effective_max
  end.

(** 2. Core Sizing Theorems *)

Theorem indefinite_cb_yields_indefinite_child :
  forall pct : Z,
    resolve_percentage_height None pct = None.
Proof.
  intros pct.
  reflexivity.
Qed.

Theorem definite_cb_yields_definite_child :
  forall (h pct : Z),
    0 <= h ->
    resolve_percentage_height (Some h) pct = Some (h * pct / 100).
Proof.
  intros h pct Hh.
  unfold resolve_percentage_height.
  destruct (h <? 0) eqn:Elt.
  - apply Z.ltb_lt in Elt. lia.
  - reflexivity.
Qed.

Theorem percentage_resolution_nonneg :
  forall (h pct : Z),
    0 <= h ->
    0 <= pct ->
    match resolve_percentage_height (Some h) pct with
    | Some res => 0 <= res
    | None => False
    end.
Proof.
  intros h pct Hh Hpct.
  rewrite definite_cb_yields_definite_child by exact Hh.
  apply Z.div_pos.
  - apply Z.mul_nonneg_nonneg; lia.
  - lia.
Qed.

Theorem percentage_resolution_monotonic :
  forall (h p1 p2 : Z),
    0 <= h ->
    0 <= p1 <= p2 ->
    match resolve_percentage_height (Some h) p1, resolve_percentage_height (Some h) p2 with
    | Some r1, Some r2 => r1 <= r2
    | _, _ => False
    end.
Proof.
  intros h p1 p2 Hh Hp.
  rewrite definite_cb_yields_definite_child by exact Hh.
  rewrite definite_cb_yields_definite_child by exact Hh.
  apply Z.div_le_mono; [lia|].
  apply Z.mul_le_mono_nonneg_l; lia.
Qed.

Theorem clamp_satisfies_min_bound :
  forall (val min_h : Z) (max_h : option Z),
    min_h <= clamp_height val min_h max_h.
Proof.
  intros val min_h max_h.
  unfold clamp_height.
  destruct max_h as [mx|].
  - apply Z.min_glb_iff.
    split.
    + apply Z.le_max_r.
    + apply Z.le_max_r.
  - apply Z.le_max_r.
Qed.

Theorem clamp_satisfies_max_bound :
  forall (val min_h mx : Z),
    min_h <= mx ->
    clamp_height val min_h (Some mx) <= mx.
Proof.
  intros val min_h mx Horder.
  unfold clamp_height.
  assert (Z.max mx min_h = mx) by (apply Z.max_l; exact Horder).
  rewrite H.
  apply Z.le_min_r.
Qed.

