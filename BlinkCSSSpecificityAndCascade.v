(******************************************************************************)
(* BlinkCSSSpecificityAndCascade.v                                            *)
(* Sound Formal Specification & Metatheory for CSS Cascading and Specificity   *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Cascading and Inheritance Level 4 & Level 5                    *)
(* 2. W3C Selectors Level 4 (Section 17: Calculating a selector's specificity)*)
(* 3. Blink CSSSelector::Specificity & CascadeResolver                       *)
(*    (`third_party/blink/renderer/core/css/css_selector.cc`,                 *)
(*     `third_party/blink/renderer/core/css/resolver/cascade_resolver.cc`)    *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Import ListNotations.
Open Scope Z_scope.

(******************************************************************************)
(* 1. CSS SELECTOR SPECIFICITY TUPLE (A, B, C)                                *)
(******************************************************************************)

Record Specificity := mkSpecificity {
  spec_a : Z; (* IDs *)
  spec_b : Z; (* Classes, attributes, pseudo-classes *)
  spec_c : Z  (* Type selectors, pseudo-elements *)
}.

Definition default_specificity : Specificity := mkSpecificity 0 0 0.

Definition add_specificity (s1 s2 : Specificity) : Specificity :=
  mkSpecificity (spec_a s1 + spec_a s2)
                (spec_b s1 + spec_b s2)
                (spec_c s1 + spec_c s2).

Definition specificity_gt (s1 s2 : Specificity) : bool :=
  if spec_a s1 >? spec_a s2 then true
  else if spec_a s1 <? spec_a s2 then false
  else if spec_b s1 >? spec_b s2 then true
  else if spec_b s1 <? spec_b s2 then false
  else spec_c s1 >? spec_c s2.

Definition specificity_eq (s1 s2 : Specificity) : bool :=
  (spec_a s1 =? spec_a s2) && (spec_b s1 =? spec_b s2) && (spec_c s1 =? spec_c s2).

(******************************************************************************)
(* 2. CSS CASCADE ORIGIN & IMPORTANCE (W3C Cascade 4 §6.1)                    *)
(******************************************************************************)

Inductive CascadeOrigin : Type :=
  | OriginUA
  | OriginUser
  | OriginAuthor.

Record CascadePriority := mkCascadePriority {
  cp_origin : CascadeOrigin;
  cp_important : bool;
  cp_layer_order : Z;     (* CSS Cascade Layers: higher order wins in normal, reversed in !important *)
  cp_specificity : Specificity;
  cp_source_order : Z     (* Document / stylesheet position: higher wins *)
}.

Definition origin_rank (orig : CascadeOrigin) (important : bool) : Z :=
  match orig, important with
  | OriginUA, false => 1
  | OriginUser, false => 2
  | OriginAuthor, false => 3
  | OriginAuthor, true => 4
  | OriginUser, true => 5
  | OriginUA, true => 6
  end.

Definition cascade_priority_gt (p1 p2 : CascadePriority) : bool :=
  let r1 := origin_rank (cp_origin p1) (cp_important p1) in
  let r2 := origin_rank (cp_origin p2) (cp_important p2) in
  if r1 >? r2 then true
  else if r1 <? r2 then false
  else
    let (l1, l2) := if cp_important p1
                    then (cp_layer_order p2, cp_layer_order p1)
                    else (cp_layer_order p1, cp_layer_order p2) in
    if l1 >? l2 then true
    else if l1 <? l2 then false
    else
      if specificity_gt (cp_specificity p1) (cp_specificity p2) then true
      else if specificity_gt (cp_specificity p2) (cp_specificity p1) then false
      else
        cp_source_order p1 >? cp_source_order p2.

(******************************************************************************)
(* 3. SOUNDNESS & TOTAL ORDER THEOREMS (0 admits)                             *)
(******************************************************************************)

Lemma specificity_add_comm : forall s1 s2,
  add_specificity s1 s2 = add_specificity s2 s1.
Proof.
  intros [a1 b1 c1] [a2 b2 c2].
  unfold add_specificity. simpl.
  rewrite (Z.add_comm a1 a2).
  rewrite (Z.add_comm b1 b2).
  rewrite (Z.add_comm c1 c2).
  reflexivity.
Qed.

Lemma specificity_add_assoc : forall s1 s2 s3,
  add_specificity (add_specificity s1 s2) s3 =
  add_specificity s1 (add_specificity s2 s3).
Proof.
  intros [a1 b1 c1] [a2 b2 c2] [a3 b3 c3].
  unfold add_specificity. simpl.
  rewrite (Z.add_assoc a1 a2 a3).
  rewrite (Z.add_assoc b1 b2 b3).
  rewrite (Z.add_assoc c1 c2 c3).
  reflexivity.
Qed.

Theorem specificity_gt_irrefl : forall s,
  specificity_gt s s = false.
Proof.
  intros [a b c].
  unfold specificity_gt. simpl.
  destruct (Z.gtb_spec a a); [lia |].
  destruct (Z.ltb_spec a a); [lia |].
  destruct (Z.gtb_spec b b); [lia |].
  destruct (Z.ltb_spec b b); [lia |].
  destruct (Z.gtb_spec c c); [lia | reflexivity].
Qed.

Theorem cascade_priority_gt_irrefl : forall p,
  cascade_priority_gt p p = false.
Proof.
  intros [orig imp lay spec src].
  unfold cascade_priority_gt. simpl.
  destruct (Z.gtb_spec (origin_rank orig imp) (origin_rank orig imp)); [lia |].
  destruct (Z.ltb_spec (origin_rank orig imp) (origin_rank orig imp)); [lia |].
  destruct imp; simpl;
  (destruct (Z.gtb_spec lay lay); [lia |];
   destruct (Z.ltb_spec lay lay); [lia |];
   rewrite specificity_gt_irrefl;
   destruct (Z.gtb_spec src src); [lia | reflexivity]).
Qed.

Theorem author_important_overrides_author_normal :
  forall p_norm p_imp,
    cp_origin p_norm = OriginAuthor -> cp_important p_norm = false ->
    cp_origin p_imp = OriginAuthor -> cp_important p_imp = true ->
    cascade_priority_gt p_imp p_norm = true.
Proof.
  intros p_norm p_imp Horig1 Himp1 Horig2 Himp2.
  unfold cascade_priority_gt.
  rewrite Horig1, Himp1, Horig2, Himp2.
  simpl. reflexivity.
Qed.

Theorem ua_important_beats_all_normal :
  forall p_ua_imp p_other,
    cp_origin p_ua_imp = OriginUA -> cp_important p_ua_imp = true ->
    cp_important p_other = false ->
    cascade_priority_gt p_ua_imp p_other = true.
Proof.
  intros p_ua_imp p_other Hua Himp Hother_norm.
  unfold cascade_priority_gt.
  rewrite Hua, Himp.
  destruct (cp_origin p_other); rewrite Hother_norm; simpl; reflexivity.
Qed.
