(* ========================================================================= *)
(*               BlinkFontFallbackSemantics.v                                *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Font Fallback Selection & Glyph        *)
(* Availability per W3C CSS Fonts Module Level 4 §5.                         *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Record FontData := {
  font_id : Z;
  font_covers : Z -> bool
}.

Fixpoint find_font_for_char (fonts : list FontData) (system_fallback : FontData) (c : Z) : FontData :=
  match fonts with
  | nil => system_fallback
  | f :: rest =>
      if font_covers f c then f
      else find_font_for_char rest system_fallback c
  end.

Theorem find_font_in_list_or_fallback : forall fonts sys c,
  let res := find_font_for_char fonts sys c in
  In res fonts \/ res = sys.
Proof.
  intros fonts sys c.
  induction fonts as [|f rest IH]; cbn.
  - right. reflexivity.
  - destruct (font_covers f c) eqn:Hcov.
    + left. left. reflexivity.
    + destruct IH as [Hin | Heq].
      * left. right. assumption.
      * right. assumption.
Qed.

Theorem find_font_system_fallback_iff : forall fonts sys c,
  (forall f, In f fonts -> font_covers f c = false) ->
  find_font_for_char fonts sys c = sys.
Proof.
  intros fonts sys c.
  induction fonts as [|f rest IH]; cbn.
  - intros _. reflexivity.
  - intros Hnone.
    assert (Hf: font_covers f c = false).
    { apply Hnone. left. reflexivity. }
    rewrite Hf.
    apply IH.
    intros f0 Hin.
    apply Hnone. right. assumption.
Qed.

Theorem find_font_first_match : forall fonts sys c f,
  find_font_for_char fonts sys c = f ->
  f <> sys ->
  In f fonts /\ font_covers f c = true.
Proof.
  intros fonts sys c f.
  induction fonts as [|hd rest IH]; cbn.
  - intros Heq Hneq. subst. contradiction.
  - destruct (font_covers hd c) eqn:Hcov.
    + intros Heq _. subst. split; [left; reflexivity | assumption].
    + intros Heq Hneq.
      apply IH in Heq; [| assumption].
      destruct Heq as [Hin Hc].
      split; [right; assumption | assumption].
Qed.

Theorem find_font_skip_prefix : forall prefix rest sys c,
  (forall p, In p prefix -> font_covers p c = false) ->
  find_font_for_char (prefix ++ rest) sys c = find_font_for_char rest sys c.
Proof.
  intros prefix rest sys c.
  induction prefix as [|p pr_rest IH]; cbn.
  - reflexivity.
  - intros Hnone.
    assert (Hp: font_covers p c = false).
    { apply Hnone. left. reflexivity. }
    rewrite Hp.
    apply IH.
    intros p0 Hin.
    apply Hnone. right. assumption.
Qed.

Theorem find_font_first_cover_in_head : forall prefix f suffix sys c,
  (forall p, In p prefix -> font_covers p c = false) ->
  font_covers f c = true ->
  find_font_for_char (prefix ++ f :: suffix) sys c = f.
Proof.
  intros prefix f suffix sys c Hpref Hcov.
  rewrite find_font_skip_prefix; [| assumption].
  cbn.
  rewrite Hcov.
  reflexivity.
Qed.
