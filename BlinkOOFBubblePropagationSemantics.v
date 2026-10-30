(* ========================================================================= *)
(*               BlinkOOFBubblePropagationSemantics.v                        *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Out-of-Flow Bubble Propagation in      *)
(* Fragment Tree per W3C CSS Positioned Layout 3 & Fragmentation 3.          *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Record OOFNode := {
  oof_id : Z;
  oof_cb_id : Z
}.

Fixpoint partition_oof_nodes (builder_id : Z) (nodes : list OOFNode) : list OOFNode * list OOFNode :=
  match nodes with
  | nil => (nil, nil)
  | n :: rest =>
      let (consumed, forwarded) := partition_oof_nodes builder_id rest in
      if oof_cb_id n =? builder_id then
        (n :: consumed, forwarded)
      else
        (consumed, n :: forwarded)
  end.

Theorem partition_oof_length_conservation : forall builder_id nodes,
  (length (fst (partition_oof_nodes builder_id nodes)) +
   length (snd (partition_oof_nodes builder_id nodes)) =
   length nodes)%nat.
Proof.
  intros builder_id nodes.
  induction nodes as [|n rest IH].
  - cbn. reflexivity.
  - cbn [partition_oof_nodes length].
    destruct (partition_oof_nodes builder_id rest) as [cons fwd].
    cbn in IH.
    destruct (oof_cb_id n =? builder_id); cbn; lia.
Qed.

Theorem partition_oof_membership_iff : forall builder_id nodes n,
  In n nodes <->
  (In n (fst (partition_oof_nodes builder_id nodes)) \/
   In n (snd (partition_oof_nodes builder_id nodes))).
Proof.
  intros builder_id nodes n.
  induction nodes as [|hd rest IH]; cbn.
  - split; [intros [] | intros [[] | []]].
  - destruct (partition_oof_nodes builder_id rest) as [cons fwd] eqn:Hpart; cbn.
    destruct (oof_cb_id hd =? builder_id) eqn:Hmatch; cbn.
    + split.
      * intros [Heq | Hin].
        -- subst hd. left. left. reflexivity.
        -- apply IH in Hin. destruct Hin as [Hcons | Hfwd].
           ++ left. right. assumption.
           ++ right. assumption.
      * intros [[Heq | Hcons] | Hfwd].
        -- subst hd. left. reflexivity.
        -- right. apply IH. left. assumption.
        -- right. apply IH. right. assumption.
    + split.
      * intros [Heq | Hin].
        -- subst hd. right. left. reflexivity.
        -- apply IH in Hin. destruct Hin as [Hcons | Hfwd].
           ++ left. assumption.
           ++ right. right. assumption.
      * intros [Hcons | [Heq | Hfwd]].
        -- right. apply IH. left. assumption.
        -- subst hd. left. reflexivity.
        -- right. apply IH. right. assumption.
Qed.

Theorem partition_oof_consumed_matches_cb : forall builder_id nodes n,
  In n (fst (partition_oof_nodes builder_id nodes)) ->
  oof_cb_id n = builder_id.
Proof.
  intros builder_id nodes n.
  induction nodes as [|hd rest IH]; cbn.
  - intros [].
  - destruct (partition_oof_nodes builder_id rest) as [cons fwd] eqn:Hpart; cbn.
    destruct (oof_cb_id hd =? builder_id) eqn:Hmatch; cbn.
    + intros [Heq | Hin].
      * subst hd. apply Z.eqb_eq in Hmatch. exact Hmatch.
      * apply (IH Hin).
    + intros Hin.
      apply (IH Hin).
Qed.

Theorem partition_oof_forwarded_differs_cb : forall builder_id nodes n,
  In n (snd (partition_oof_nodes builder_id nodes)) ->
  oof_cb_id n <> builder_id.
Proof.
  intros builder_id nodes n.
  induction nodes as [|hd rest IH]; cbn.
  - intros [].
  - destruct (partition_oof_nodes builder_id rest) as [cons fwd] eqn:Hpart; cbn.
    destruct (oof_cb_id hd =? builder_id) eqn:Hmatch; cbn.
    + intros Hin.
      apply (IH Hin).
    + intros [Heq | Hin].
      * subst hd. apply Z.eqb_neq in Hmatch. exact Hmatch.
      * apply (IH Hin).
Qed.

Theorem bubbling_union_length : forall (l1 l2 : list OOFNode),
  (length (l1 ++ l2) = length l1 + length l2)%nat.
Proof.
  intros l1 l2.
  apply length_app.
Qed.
