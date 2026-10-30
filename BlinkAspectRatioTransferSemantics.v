(**
  BlinkAspectRatioTransferSemantics.v
  Formal specification of Chromium Blink CSS aspect-ratio dimension transfer
  derived from third_party/blink/renderer/core/layout/aspect_ratio.cc and length_utils.cc
  according to W3C CSS Box Sizing Module Level 4 (§2 & §3 The aspect-ratio Property).
*)

From Stdlib Require Import ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

Record LogicalAspectRatio := {
  ratio_w : Z;
  ratio_h : Z
}.

Definition inline_to_block (inline_size : Z) (ar : LogicalAspectRatio) : Z :=
  if ar.(ratio_w) <=? 0 then 0
  else (inline_size * ar.(ratio_h)) / ar.(ratio_w).

Definition block_to_inline (block_size : Z) (ar : LogicalAspectRatio) : Z :=
  if ar.(ratio_h) <=? 0 then 0
  else (block_size * ar.(ratio_w)) / ar.(ratio_h).

Definition clamp_dim (val min_v max_v : Z) : Z :=
  Z.max min_v (Z.min val max_v).

(** 1. Non-negativity and Monotonicity *)

Theorem transfer_inline_to_block_nonneg :
  forall (inline_size : Z) (ar : LogicalAspectRatio),
    0 <= inline_size ->
    0 < ar.(ratio_w) ->
    0 <= ar.(ratio_h) ->
    0 <= inline_to_block inline_size ar.
Proof.
  intros inline_size ar Hi Hw Hh.
  unfold inline_to_block.
  destruct (ar.(ratio_w) <=? 0) eqn:Ew; [lia|].
  apply Z.div_pos.
  - apply Z.mul_nonneg_nonneg; lia.
  - lia.
Qed.

Theorem transfer_block_to_inline_nonneg :
  forall (block_size : Z) (ar : LogicalAspectRatio),
    0 <= block_size ->
    0 <= ar.(ratio_w) ->
    0 < ar.(ratio_h) ->
    0 <= block_to_inline block_size ar.
Proof.
  intros block_size ar Hb Hw Hh.
  unfold block_to_inline.
  destruct (ar.(ratio_h) <=? 0) eqn:Eh; [lia|].
  apply Z.div_pos.
  - apply Z.mul_nonneg_nonneg; lia.
  - lia.
Qed.

Theorem inline_to_block_monotonic :
  forall (i1 i2 : Z) (ar : LogicalAspectRatio),
    0 <= i1 <= i2 ->
    0 < ar.(ratio_w) ->
    0 <= ar.(ratio_h) ->
    inline_to_block i1 ar <= inline_to_block i2 ar.
Proof.
  intros i1 i2 ar Hi Hw Hh.
  unfold inline_to_block.
  destruct (ar.(ratio_w) <=? 0) eqn:Ew; [lia|].
  apply Z.div_le_mono; [lia|].
  apply Z.mul_le_mono_nonneg_r; lia.
Qed.

(** 2. Clamping: Min Overrides Max *)

Theorem clamp_min_overrides_max :
  forall (val min_v max_v : Z),
    max_v <= min_v ->
    clamp_dim val min_v max_v = min_v.
Proof.
  intros val min_v max_v Hle.
  unfold clamp_dim.
  lia.
Qed.

(** 3. Exact Involution under Divisibility *)

Theorem ratio_transfer_involution_exact :
  forall (inline_size : Z) (ar : LogicalAspectRatio),
    0 < ar.(ratio_w) ->
    0 < ar.(ratio_h) ->
    (inline_size * ar.(ratio_h)) mod ar.(ratio_w) = 0 ->
    block_to_inline (inline_to_block inline_size ar) ar = inline_size.
Proof.
  intros inline_size ar Hw Hh Hmod.
  unfold inline_to_block, block_to_inline.
  destruct (ar.(ratio_w) <=? 0) eqn:Ew; [lia|].
  destruct (ar.(ratio_h) <=? 0) eqn:Eh; [lia|].
  rewrite <- Z.div_exact in Hmod by lia.
  rewrite Z.mul_comm with (n := (inline_size * ratio_h ar) / ratio_w ar).
  rewrite <- Hmod.
  rewrite Z.div_mul by lia.
  reflexivity.
Qed.
