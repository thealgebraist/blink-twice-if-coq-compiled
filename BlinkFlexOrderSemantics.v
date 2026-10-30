(* =========================================================================
   BlinkFlexOrderSemantics.v
   Formalization of Chromium Blink Flex Child Order Iteration & Sorting
   Source: third_party/blink/renderer/core/layout/flex/flex_child_iterator.cc
   Specification: W3C CSS Flexible Box Layout Module Level 1 §5.4
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Arith.Arith.
From Coq Require Import Lia.
Open Scope Z_scope.

Record FlexOrderEntry : Type := mkFlexOrderEntry {
  entry_id : nat;
  entry_doc_index : nat;
  entry_order : Z
}.

Definition flex_entry_lt (a b : FlexOrderEntry) : bool :=
  if a.(entry_order) <? b.(entry_order) then
    true
  else if b.(entry_order) <? a.(entry_order) then
    false
  else
    Nat.ltb a.(entry_doc_index) b.(entry_doc_index).

Theorem flex_entry_lt_irrefl :
  forall a,
    flex_entry_lt a a = false.
Proof.
  intros a.
  unfold flex_entry_lt.
  rewrite Z.ltb_irrefl.
  apply Nat.ltb_irrefl.
Qed.

Theorem flex_entry_lt_asym :
  forall a b,
    flex_entry_lt a b = true ->
    flex_entry_lt b a = false.
Proof.
  intros a b Hlt.
  unfold flex_entry_lt in Hlt.
  unfold flex_entry_lt.
  destruct (a.(entry_order) <? b.(entry_order)) eqn:Eab.
  - apply Z.ltb_lt in Eab.
    assert (Eba : (b.(entry_order) <? a.(entry_order)) = false) by (apply Z.ltb_ge; lia).
    rewrite Eba.
    reflexivity.
  - destruct (b.(entry_order) <? a.(entry_order)) eqn:Eba; [discriminate Hlt |].
    apply Nat.ltb_lt in Hlt.
    apply Nat.ltb_ge.
    lia.
Qed.

Theorem flex_entry_lt_trans :
  forall a b c,
    flex_entry_lt a b = true ->
    flex_entry_lt b c = true ->
    flex_entry_lt a c = true.
Proof.
  intros a b c Hab Hbc.
  unfold flex_entry_lt in Hab, Hbc.
  unfold flex_entry_lt.
  destruct (a.(entry_order) <? b.(entry_order)) eqn:Eab.
  - apply Z.ltb_lt in Eab.
    destruct (b.(entry_order) <? c.(entry_order)) eqn:Ebc.
    + apply Z.ltb_lt in Ebc.
      assert (Eac : (a.(entry_order) <? c.(entry_order)) = true) by (apply Z.ltb_lt; lia).
      rewrite Eac. reflexivity.
    + destruct (c.(entry_order) <? b.(entry_order)) eqn:Ecb; [discriminate Hbc |].
      apply Z.ltb_ge in Ebc.
      apply Z.ltb_ge in Ecb.
      assert (Eac : (a.(entry_order) <? c.(entry_order)) = true) by (apply Z.ltb_lt; lia).
      rewrite Eac. reflexivity.
  - destruct (b.(entry_order) <? a.(entry_order)) eqn:Eba; [discriminate Hab |].
    apply Z.ltb_ge in Eab.
    apply Z.ltb_ge in Eba.
    destruct (b.(entry_order) <? c.(entry_order)) eqn:Ebc.
    + apply Z.ltb_lt in Ebc.
      assert (Eac : (a.(entry_order) <? c.(entry_order)) = true) by (apply Z.ltb_lt; lia).
      rewrite Eac. reflexivity.
    + destruct (c.(entry_order) <? b.(entry_order)) eqn:Ecb; [discriminate Hbc |].
      apply Z.ltb_ge in Ebc.
      apply Z.ltb_ge in Ecb.
      assert (Eac : (a.(entry_order) <? c.(entry_order)) = false) by (apply Z.ltb_ge; lia).
      assert (Eca : (c.(entry_order) <? a.(entry_order)) = false) by (apply Z.ltb_ge; lia).
      rewrite Eac.
      rewrite Eca.
      apply Nat.ltb_lt in Hab.
      apply Nat.ltb_lt in Hbc.
      apply Nat.ltb_lt.
      lia.
Qed.

Theorem flex_order_stability :
  forall a b,
    a.(entry_order) = b.(entry_order) ->
    (a.(entry_doc_index) < b.(entry_doc_index))%nat ->
    flex_entry_lt a b = true.
Proof.
  intros a b Heq Hdoc.
  unfold flex_entry_lt.
  rewrite Heq.
  rewrite Z.ltb_irrefl.
  apply Nat.ltb_lt.
  exact Hdoc.
Qed.
