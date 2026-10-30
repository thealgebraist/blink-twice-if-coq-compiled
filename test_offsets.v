From Stdlib Require Import ZArith Lists.List Lia.
Open Scope Z_scope.

Fixpoint sum_cross_sizes (cross_sizes : list Z) : Z :=
  match cross_sizes with
  | nil => 0
  | sz :: rest => sz + sum_cross_sizes rest
  end.

Lemma sum_cross_sizes_app : forall l1 l2,
  sum_cross_sizes (l1 ++ l2) = sum_cross_sizes l1 + sum_cross_sizes l2.
Proof.
  induction l1 as [| x xs IH]; intros l2; cbn.
  - reflexivity.
  - rewrite IH. lia.
Qed.

Lemma sum_cross_sizes_pos : forall l,
  l <> nil ->
  (forall x, In x l -> x > 0) ->
  sum_cross_sizes l > 0.
Proof.
  intros [| x xs] Hnil Hpos.
  - contradiction Hnil; reflexivity.
  - cbn.
    assert (Hx: x > 0) by (apply Hpos; left; reflexivity).
    assert (Hxs: sum_cross_sizes xs >= 0).
    { clear Hx. induction xs as [| y ys IHy]; cbn; [lia |].
      assert (Hy: y > 0) by (apply Hpos; right; left; reflexivity).
      assert (Hys: forall z, In z ys -> z > 0) by (intros z Hz; apply Hpos; right; right; exact Hz).
      specialize (IHy Hys). lia. }
    lia.
Qed.

Lemma sum_cross_sizes_firstn_lt : forall l i j,
  (forall x, In x l -> x > 0) ->
  (i < j)%nat ->
  (j <= length l)%nat ->
  sum_cross_sizes (firstn i l) < sum_cross_sizes (firstn j l).
Proof.
  intros l i j Hpos Hlt Hj.
  rewrite (firstn_rem i j l) by lia.
  rewrite sum_cross_sizes_app.
  assert (Hsub: sum_cross_sizes (firstn (j - i) (skipn i l)) > 0).
  { apply sum_cross_sizes_pos.
    - intros Hnil.
      apply (f_equal (@length Z)) in Hnil.
      rewrite firstn_length in Hnil.
      rewrite skipn_length in Hnil.
      cbn in Hnil. lia.
    - intros x Hx.
      apply Hpos.
      eapply In_firstn.
      eapply in_skipn.
      exact Hx. }
  lia.
Qed.
