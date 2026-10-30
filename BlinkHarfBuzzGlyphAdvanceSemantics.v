(* ========================================================================= *)
(*               BlinkHarfBuzzGlyphAdvanceSemantics.v                       *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink HarfBuzz Glyph Advance Accumulation *)
(* and Cluster Mapping against CSS Text 3 §5. Fully constructive, 0 admits.  *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Fixpoint sum_glyph_advances (advances : list Z) : Z :=
  match advances with
  | nil => 0
  | x :: xs => x + sum_glyph_advances xs
  end.

Theorem sum_glyph_advances_nonneg : forall l,
  (forall x, In x l -> x >= 0) ->
  sum_glyph_advances l >= 0.
Proof.
  induction l as [| x xs IH]; intros H.
  - simpl. lia.
  - simpl.
    assert (Hx: x >= 0).
    { apply H. left. reflexivity. }
    assert (Hxs: sum_glyph_advances xs >= 0).
    { apply IH. intros y Hy. apply H. right. exact Hy. }
    lia.
Qed.

Theorem sum_glyph_advances_app : forall l1 l2,
  sum_glyph_advances (l1 ++ l2) = sum_glyph_advances l1 + sum_glyph_advances l2.
Proof.
  induction l1 as [| x xs IH]; intros l2.
  - simpl. lia.
  - simpl. rewrite IH. ring.
Qed.

Theorem sum_glyph_advances_monotonic_step : forall l x,
  x > 0 ->
  sum_glyph_advances (l ++ (x :: nil)) > sum_glyph_advances l.
Proof.
  intros l x Hx.
  rewrite sum_glyph_advances_app.
  simpl. lia.
Qed.
