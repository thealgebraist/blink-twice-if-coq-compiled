(******************************************************************************)
(* BlinkFlexWrapSemantics.v                                                   *)
(* Sound Formal Specification for Multi-Line Flexbox Wrapping (flex-wrap: wrap)*)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Flexible Box Layout Level 1 (§9.3 Line Breaking)                *)
(* 2. Blink FlexLine & FlexLayoutAlgorithm (`flex_line.cc`)                   *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool PeanoNat.
Require Import BlinkOperationalSemantics.
Require Import BlinkFlexboxContainerSemantics.
Import ListNotations.
Open Scope Z_scope.

Fixpoint pack_flex_line (items : list FlexItemStyle) (avail_main : Z)
                        (cur_main : Z) (acc : list FlexItemStyle) : (list FlexItemStyle * list FlexItemStyle) :=
  match items with
  | [] => (rev acc, [])
  | it :: rest =>
      let b := fis_basis it in
      let sz := if b =? kIndefiniteSize then 0 else sat_clamp b in
      if (cur_main + sz <=? avail_main) || (cur_main =? 0) then
        (* Fits or first item on the line *)
        pack_flex_line rest avail_main (cur_main + sz) (it :: acc)
      else
        (* Break to next line *)
        (rev acc, items)
  end.

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Lemma pack_flex_line_rest_len : forall items avail cur acc,
  let '(_, rest) := pack_flex_line items avail cur acc in
  (length rest <= length items)%nat.
Proof.
  induction items as [| it rest IH]; intros avail cur acc; simpl.
  - lia.
  - destruct ((cur + (if fis_basis it =? kIndefiniteSize then 0 else sat_clamp (fis_basis it)) <=? avail) || (cur =? 0)).
    + specialize (IH avail (cur + (if fis_basis it =? kIndefiniteSize then 0 else sat_clamp (fis_basis it))) (it :: acc)).
      destruct (pack_flex_line rest avail (cur + (if fis_basis it =? kIndefiniteSize then 0 else sat_clamp (fis_basis it))) (it :: acc)) as [tk rs].
      simpl. lia.
    + simpl. lia.
Qed.

Theorem pack_flex_line_strictly_progresses :
  forall it items avail,
    let '(_, rest) := pack_flex_line (it :: items) avail 0 [] in
    (length rest < length (it :: items))%nat.
Proof.
  intros it items avail.
  change (pack_flex_line (it :: items) avail 0 []) with
    (if (0 + (if fis_basis it =? kIndefiniteSize then 0 else sat_clamp (fis_basis it)) <=? avail) || (0 =? 0)
     then pack_flex_line items avail (0 + (if fis_basis it =? kIndefiniteSize then 0 else sat_clamp (fis_basis it))) [it]
     else (rev [], it :: items)).
  assert (Hcond : ((0 + (if fis_basis it =? kIndefiniteSize then 0 else sat_clamp (fis_basis it)) <=? avail) || (0 =? 0)) = true).
  { rewrite orb_true_iff. right. reflexivity. }
  rewrite Hcond.
  assert (Hle := pack_flex_line_rest_len items avail (0 + (if fis_basis it =? kIndefiniteSize then 0 else sat_clamp (fis_basis it))) [it]).
  destruct (pack_flex_line items avail (0 + (if fis_basis it =? kIndefiniteSize then 0 else sat_clamp (fis_basis it))) [it]) as [tk rs].
  simpl in *. lia.
Qed.

Theorem pack_flex_line_deterministic :
  forall items avail cur acc r1 r2,
    r1 = pack_flex_line items avail cur acc ->
    r2 = pack_flex_line items avail cur acc ->
    r1 = r2.
Proof.
  intros items avail cur acc r1 r2 H1 H2. subst. reflexivity.
Qed.
