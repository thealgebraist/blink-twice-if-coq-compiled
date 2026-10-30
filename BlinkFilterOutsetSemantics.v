(** * BlinkFilterOutsetSemantics.v
    Formal verification of Chromium Blink CSS Filter Outsets
    vs. W3C Filter Effects Module Level 1.
*)

From Stdlib Require Import ZArith.ZArith.
From Stdlib Require Import Lists.List.
From Stdlib Require Import micromega.Lia.
Import ListNotations.
Open Scope Z_scope.

(** ** 1. Core Data Structures *)

Record Outsets : Type := mkOutsets {
  outset_top    : Z;
  outset_right  : Z;
  outset_bottom : Z;
  outset_left   : Z
}.

Definition zero_outsets : Outsets :=
  mkOutsets 0 0 0 0.

Definition outsets_nonneg (o : Outsets) : Prop :=
  0 <= outset_top o /\
  0 <= outset_right o /\
  0 <= outset_bottom o /\
  0 <= outset_left o.

Definition outsets_le (o1 o2 : Outsets) : Prop :=
  outset_top o1 <= outset_top o2 /\
  outset_right o1 <= outset_right o2 /\
  outset_bottom o1 <= outset_bottom o2 /\
  outset_left o1 <= outset_left o2.

Definition outsets_union (o1 o2 : Outsets) : Outsets :=
  mkOutsets
    (Z.max (outset_top o1) (outset_top o2))
    (Z.max (outset_right o1) (outset_right o2))
    (Z.max (outset_bottom o1) (outset_bottom o2))
    (Z.max (outset_left o1) (outset_left o2)).

Definition outsets_add (o1 o2 : Outsets) : Outsets :=
  mkOutsets
    (outset_top o1 + outset_top o2)
    (outset_right o1 + outset_right o2)
    (outset_bottom o1 + outset_bottom o2)
    (outset_left o1 + outset_left o2).

Inductive FilterOperation : Type :=
  | FOp_ColorMatrix : FilterOperation
  | FOp_Blur        : Z -> FilterOperation
  | FOp_DropShadow  : Z -> Z -> Z -> FilterOperation.

Definition FilterOperations := list FilterOperation.

(** ** 2. Ink Overflow Expansion Semantics *)

Definition blur_spread (sigma : Z) : Z :=
  3 * Z.max 0 sigma.

Definition eval_filter_op (op : FilterOperation) : Outsets :=
  match op with
  | FOp_ColorMatrix => zero_outsets
  | FOp_Blur sigma =>
      let r := blur_spread sigma in
      mkOutsets r r r r
  | FOp_DropShadow dx dy sigma =>
      let r := blur_spread sigma in
      mkOutsets
        (Z.max 0 (r - dy))
        (Z.max 0 (r + dx))
        (Z.max 0 (r + dy))
        (Z.max 0 (r - dx))
  end.

Fixpoint eval_filter_chain (ops : FilterOperations) : Outsets :=
  match ops with
  | [] => zero_outsets
  | op :: rest => outsets_add (eval_filter_op op) (eval_filter_chain rest)
  end.

Fixpoint union_filter_outsets (os : list Outsets) : Outsets :=
  match os with
  | [] => zero_outsets
  | o :: rest => outsets_union o (union_filter_outsets rest)
  end.

(** ** 3. Mathematical Invariants & Proofs *)

Lemma blur_spread_nonneg : forall sigma : Z,
  0 <= blur_spread sigma.
Proof.
  intros sigma. unfold blur_spread. lia.
Qed.

Lemma blur_spread_monotonic : forall s1 s2 : Z,
  s1 <= s2 -> blur_spread s1 <= blur_spread s2.
Proof.
  intros s1 s2 Hle. unfold blur_spread. lia.
Qed.

Theorem eval_filter_op_nonneg : forall op : FilterOperation,
  outsets_nonneg (eval_filter_op op).
Proof.
  intros [ | sigma | dx dy sigma]; unfold eval_filter_op, outsets_nonneg, zero_outsets; simpl.
  - lia.
  - pose proof (blur_spread_nonneg sigma). lia.
  - lia.
Qed.

Lemma outsets_add_nonneg : forall o1 o2 : Outsets,
  outsets_nonneg o1 -> outsets_nonneg o2 -> outsets_nonneg (outsets_add o1 o2).
Proof.
  intros [t1 r1 b1 l1] [t2 r2 b2 l2] H1 H2.
  unfold outsets_nonneg, outsets_add in *; simpl in *. lia.
Qed.

Theorem eval_filter_chain_nonneg : forall ops : FilterOperations,
  outsets_nonneg (eval_filter_chain ops).
Proof.
  intros ops.
  induction ops as [| op rest IH].
  - unfold eval_filter_chain, outsets_nonneg, zero_outsets. simpl. lia.
  - simpl.
    apply outsets_add_nonneg.
    + apply eval_filter_op_nonneg.
    + exact IH.
Qed.

Theorem outsets_add_comm : forall o1 o2,
  outsets_add o1 o2 = outsets_add o2 o1.
Proof.
  intros [t1 r1 b1 l1] [t2 r2 b2 l2].
  unfold outsets_add. simpl.
  rewrite (Z.add_comm t1 t2).
  rewrite (Z.add_comm r1 r2).
  rewrite (Z.add_comm b1 b2).
  rewrite (Z.add_comm l1 l2).
  reflexivity.
Qed.

Theorem outsets_add_assoc : forall o1 o2 o3,
  outsets_add (outsets_add o1 o2) o3 = outsets_add o1 (outsets_add o2 o3).
Proof.
  intros [t1 r1 b1 l1] [t2 r2 b2 l2] [t3 r3 b3 l3].
  unfold outsets_add. simpl.
  rewrite (Z.add_assoc t1 t2 t3).
  rewrite (Z.add_assoc r1 r2 r3).
  rewrite (Z.add_assoc b1 b2 b3).
  rewrite (Z.add_assoc l1 l2 l3).
  reflexivity.
Qed.

Theorem eval_filter_chain_app : forall ops1 ops2,
  eval_filter_chain (ops1 ++ ops2) =
  outsets_add (eval_filter_chain ops1) (eval_filter_chain ops2).
Proof.
  intros ops1 ops2.
  induction ops1 as [| op rest IH].
  - simpl.
    destruct (eval_filter_chain ops2) as [t r b l].
    unfold outsets_add, zero_outsets. simpl.
    reflexivity.
  - simpl.
    rewrite IH.
    symmetry.
    apply outsets_add_assoc.
Qed.

Theorem chain_monotonicity_prefix : forall ops1 ops2,
  outsets_le (eval_filter_chain ops1) (eval_filter_chain (ops1 ++ ops2)).
Proof.
  intros ops1 ops2.
  rewrite eval_filter_chain_app.
  pose proof (eval_filter_chain_nonneg ops2) as [H2t [H2r [H2b H2l]]].
  unfold outsets_le, outsets_add. simpl.
  lia.
Qed.

Theorem outsets_union_comm : forall o1 o2,
  outsets_union o1 o2 = outsets_union o2 o1.
Proof.
  intros [t1 r1 b1 l1] [t2 r2 b2 l2].
  unfold outsets_union. simpl.
  rewrite (Z.max_comm t1 t2).
  rewrite (Z.max_comm r1 r2).
  rewrite (Z.max_comm b1 b2).
  rewrite (Z.max_comm l1 l2).
  reflexivity.
Qed.

Theorem outsets_union_idempotent : forall o,
  outsets_union o o = o.
Proof.
  intros [t r b l].
  unfold outsets_union. simpl.
  rewrite !Z.max_idempotent.
  reflexivity.
Qed.
