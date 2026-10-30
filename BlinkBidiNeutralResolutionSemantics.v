(* ========================================================================= *)
(*               BlinkBidiNeutralResolutionSemantics.v                       *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink BiDi Neutral Character Resolution   *)
(* per UAX #9 Rules N1 & N2 and CSS Writing Modes Level 3 §2.                *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import Lists.List Bool PeanoNat Lia.
Import ListNotations.

Inductive BidiType : Type :=
  | L : BidiType
  | R : BidiType
  | N : BidiType.

Definition is_strong (t : BidiType) : bool :=
  match t with
  | L => true
  | R => true
  | N => false
  end.

Definition max_embedding_level : nat := 125.

Definition embedding_direction (lvl : nat) : BidiType :=
  if Nat.even lvl then L else R.

Definition resolve_neutral_type (prev next : BidiType) (lvl : nat) : BidiType :=
  match prev, next with
  | L, L => L
  | R, R => R
  | _, _ => embedding_direction lvl
  end.

Fixpoint next_strong (seq : list BidiType) (eos : BidiType) : BidiType :=
  match seq with
  | []      => eos
  | L :: _  => L
  | R :: _  => R
  | N :: xs => next_strong xs eos
  end.

Fixpoint resolve_neutrals_aux (seq : list BidiType) (prev eos : BidiType) (lvl : nat) : list BidiType :=
  match seq with
  | []      => []
  | L :: xs => L :: resolve_neutrals_aux xs L eos lvl
  | R :: xs => R :: resolve_neutrals_aux xs R eos lvl
  | N :: xs =>
      let resolved := resolve_neutral_type prev (next_strong xs eos) lvl in
      resolved :: resolve_neutrals_aux xs prev eos lvl
  end.

Definition resolve_neutrals (seq : list BidiType) (sos eos : BidiType) (lvl : nat) : list BidiType :=
  resolve_neutrals_aux seq sos eos lvl.

(* ------------------------------------------------------------------------- *)
(* Theorems                                                                  *)
(* ------------------------------------------------------------------------- *)

Lemma embedding_direction_is_strong : forall lvl,
  is_strong (embedding_direction lvl) = true.
Proof.
  intros lvl. unfold embedding_direction.
  destruct (Nat.even lvl); reflexivity.
Qed.

Lemma even_level_is_LTR : forall lvl,
  Nat.even lvl = true -> embedding_direction lvl = L.
Proof.
  intros lvl Heven. unfold embedding_direction. rewrite Heven. reflexivity.
Qed.

Lemma odd_level_is_RTL : forall lvl,
  Nat.even lvl = false -> embedding_direction lvl = R.
Proof.
  intros lvl Hodd. unfold embedding_direction. rewrite Hodd. reflexivity.
Qed.

Lemma resolve_neutral_type_is_strong : forall prev next lvl,
  is_strong (resolve_neutral_type prev next lvl) = true.
Proof.
  intros prev next lvl. unfold resolve_neutral_type.
  destruct prev, next; try reflexivity; apply embedding_direction_is_strong.
Qed.

Theorem resolve_neutrals_length : forall seq prev eos lvl,
  length (resolve_neutrals_aux seq prev eos lvl) = length seq.
Proof.
  induction seq as [| x xs IH]; intros prev eos lvl; simpl.
  - reflexivity.
  - destruct x; simpl; f_equal; apply IH.
Qed.

Theorem resolve_neutrals_no_N : forall seq prev eos lvl,
  forallb is_strong (resolve_neutrals_aux seq prev eos lvl) = true.
Proof.
  induction seq as [| x xs IH]; intros prev eos lvl; simpl.
  - reflexivity.
  - destruct x; simpl.
    + apply IH.
    + apply IH.
    + rewrite resolve_neutral_type_is_strong. simpl. apply IH.
Qed.

Lemma next_strong_repeat_N : forall k rest eos,
  next_strong (repeat N k ++ rest) eos = next_strong rest eos.
Proof.
  induction k as [| k' IH]; intros rest eos; simpl.
  - reflexivity.
  - apply IH.
Qed.

Lemma resolve_neutrals_repeat_N : forall k prev eos lvl rest,
  let target := resolve_neutral_type prev (next_strong rest eos) lvl in
  resolve_neutrals_aux (repeat N k ++ rest) prev eos lvl =
  repeat target k ++ resolve_neutrals_aux rest prev eos lvl.
Proof.
  induction k as [| k' IH]; intros prev eos lvl rest target; simpl.
  - reflexivity.
  - rewrite next_strong_repeat_N.
    fold target. f_equal. apply IH.
Qed.

Theorem rule_N1_L_N_L : forall k tail prev eos lvl,
  resolve_neutrals_aux (L :: repeat N k ++ L :: tail) prev eos lvl =
  L :: repeat L k ++ L :: resolve_neutrals_aux tail L eos lvl.
Proof.
  intros k tail prev eos lvl. simpl.
  f_equal.
  rewrite resolve_neutrals_repeat_N.
  simpl. reflexivity.
Qed.

Theorem rule_N1_R_N_R : forall k tail prev eos lvl,
  resolve_neutrals_aux (R :: repeat N k ++ R :: tail) prev eos lvl =
  R :: repeat R k ++ R :: resolve_neutrals_aux tail R eos lvl.
Proof.
  intros k tail prev eos lvl. simpl.
  f_equal.
  rewrite resolve_neutrals_repeat_N.
  simpl. reflexivity.
Qed.

Corollary rule_N1_LNL_concrete : forall sos eos lvl,
  resolve_neutrals [L; N; L] sos eos lvl = [L; L; L].
Proof.
  intros. reflexivity.
Qed.

Corollary rule_N1_RNR_concrete : forall sos eos lvl,
  resolve_neutrals [R; N; R] sos eos lvl = [R; R; R].
Proof.
  intros. reflexivity.
Qed.

