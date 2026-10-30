From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
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

Lemma sum_cross_sizes_nonneg : forall l,
  (forall x, In x l -> x >= 0) ->
  sum_cross_sizes l >= 0.
Proof.
  induction l as [| x xs IH]; intros Hpos; cbn.
  - lia.
  - assert (Hx: x >= 0) by (apply Hpos; left; reflexivity).
    assert (Hxs: sum_cross_sizes xs >= 0) by (apply IH; intros z Hz; apply Hpos; right; exact Hz).
    lia.
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
    { apply sum_cross_sizes_nonneg.
      intros z Hz. assert (Hzp: z > 0) by (apply Hpos; right; exact Hz). lia. }
    lia.
Qed.
