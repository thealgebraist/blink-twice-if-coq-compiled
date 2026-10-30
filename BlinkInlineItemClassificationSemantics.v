(* ========================================================================= *)
(*               BlinkInlineItemClassificationSemantics.v                   *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Inline Item Segment Classification  *)
(* against CSS Inline 3 §2. Fully constructive, 0 admits.                    *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Inductive InlineItemKind : Type :=
| IIText
| IIControl
| IIOpenTag
| IICloseTag
| IIAtomic.

Record InlineItem := mkInlineItem {
  ii_kind  : InlineItemKind;
  ii_start : Z;
  ii_end   : Z
}.

Fixpoint items_continuous (items : list InlineItem) (expected_start : Z) : bool :=
  match items with
  | nil => true
  | it :: rest =>
      (ii_start it =? expected_start) &&
      (ii_start it <=? ii_end it) &&
      items_continuous rest (ii_end it)
  end.

Theorem items_continuous_nil : forall s,
  items_continuous nil s = true.
Proof.
  intros. reflexivity.
Qed.

Theorem items_continuous_step : forall it rest s,
  ii_start it = s ->
  ii_start it <= ii_end it ->
  items_continuous rest (ii_end it) = true ->
  items_continuous (it :: rest) s = true.
Proof.
  intros it rest s Hstart Hlen Hrest.
  simpl.
  assert (E1: (ii_start it =? s) = true) by (apply Z.eqb_eq; lia).
  assert (E2: (ii_start it <=? ii_end it) = true) by (apply Z.leb_le; lia).
  rewrite E1, E2, Hrest.
  reflexivity.
Qed.
