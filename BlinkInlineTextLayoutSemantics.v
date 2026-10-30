(* ========================================================================= *)
(*               BlinkInlineTextLayoutSemantics.v                            *)
(* ========================================================================= *)
(* Formal Semantics of Chromium Blink Complex Text Run Advances & Inline     *)
(* Greedy Line Breaking per W3C CSS Text Module Level 3 and Unicode UAX #14. *)
(* Verified with Rocq / Coq 9.3.0, strictly 0 admits.                       *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Import ListNotations.
Open Scope Z_scope.

(** * 1. Text Token Representation *)

(** A text token represents an atomic shaped unit (character, glyph cluster, or word slice)
    with layout metrics and line breaking properties per CSS Text 3 and UAX #14. *)
Record TextToken : Type := {
  token_width : Z;
  is_break_opportunity : bool;
  is_space : bool
}.

(** * 2. Advance Calculation with Spacings *)

(** CSS Text 3 §8.1 / §8.2:
    - Letter spacing adds spacing between typographic letter units.
    - Word spacing adds spacing to space characters. *)
Definition compute_token_advance (token : TextToken) (letter_spacing word_spacing : Z) : Z :=
  token.(token_width) + letter_spacing + (if token.(is_space) then word_spacing else 0).

(** Invariant: Advance is non-negative when token width and spacings are non-negative. *)
Theorem advance_nonnegative : forall (token : TextToken) (letter_spacing word_spacing : Z),
  0 <= token.(token_width) ->
  0 <= letter_spacing ->
  0 <= word_spacing ->
  0 <= compute_token_advance token letter_spacing word_spacing.
Proof.
  intros token letter_spacing word_spacing Hw Hl Hws.
  unfold compute_token_advance.
  destruct (is_space token); lia.
Qed.

(** Advance is monotonic with respect to letter-spacing and word-spacing. *)
Theorem advance_monotonic_spacings :
  forall (token : TextToken) (ls1 ls2 ws1 ws2 : Z),
    ls1 <= ls2 ->
    ws1 <= ws2 ->
    compute_token_advance token ls1 ws1 <= compute_token_advance token ls2 ws2.
Proof.
  intros token ls1 ls2 ws1 ws2 Hls Hws.
  unfold compute_token_advance.
  destruct (is_space token); lia.
Qed.

(** Spacings of zero preserve the intrinsic token advance. *)
Theorem zero_spacing_identity :
  forall (token : TextToken),
    compute_token_advance token 0 0 = token.(token_width).
Proof.
  intros token.
  unfold compute_token_advance.
  destruct (is_space token); lia.
Qed.

(** * 3. Line Width and Width Conservation *)

(** The width of a line is the sum of constituent token advances. *)
Fixpoint line_width (line : list TextToken) (letter_spacing word_spacing : Z) : Z :=
  match line with
  | [] => 0
  | t :: ts => compute_token_advance t letter_spacing word_spacing + line_width ts letter_spacing word_spacing
  end.

(** Theorem: Line length is the sum of constituent token advances (fold_right equivalence). *)
Theorem line_width_conservation : forall (line : list TextToken) (letter_spacing word_spacing : Z),
  line_width line letter_spacing word_spacing =
  fold_right (fun t acc => compute_token_advance t letter_spacing word_spacing + acc) 0 line.
Proof.
  intros line ls ws.
  induction line as [| t ts IH]; simpl.
  - reflexivity.
  - rewrite IH. reflexivity.
Qed.

Lemma line_width_app : forall l1 l2 ls ws,
  line_width (l1 ++ l2) ls ws = line_width l1 ls ws + line_width l2 ls ws.
Proof.
  intros l1 l2 ls ws.
  induction l1 as [| t ts IH]; simpl.
  - reflexivity.
  - rewrite IH. lia.
Qed.

Lemma line_width_rev_cons : forall t l ls ws,
  line_width (rev (t :: l)) ls ws = line_width (rev l) ls ws + compute_token_advance t ls ws.
Proof.
  intros t l ls ws.
  change (rev (t :: l)) with (rev l ++ [t]).
  rewrite line_width_app.
  simpl. lia.
Qed.

(** * 4. Greedy Line Breaking Algorithm *)

(** Standard greedy line breaking algorithm per W3C CSS Text Module Level 3 §5
    and Unicode Standard Annex #14 (UAX #14).
    Tokens are accumulated into the current line as long as they fit within max_width.
    When a token overflows, if it provides a break opportunity (or starts after one),
    the current line is broken and emitted; otherwise, the token is kept together
    as part of an unbreakable long word. *)
Fixpoint break_into_lines_aux
    (tokens : list TextToken)
    (max_width : Z)
    (ls ws : Z)
    (cur_rev : list TextToken)
    (cur_w : Z) : list (list TextToken) :=
  match tokens with
  | [] =>
      match cur_rev with
      | [] => []
      | _ => [rev cur_rev]
      end
  | t :: rest =>
      let adv := compute_token_advance t ls ws in
      match cur_rev with
      | [] =>
          break_into_lines_aux rest max_width ls ws [t] adv
      | _ =>
          if cur_w + adv <=? max_width then
            break_into_lines_aux rest max_width ls ws (t :: cur_rev) (cur_w + adv)
          else if is_break_opportunity t then
            rev cur_rev :: break_into_lines_aux rest max_width ls ws [t] adv
          else
            break_into_lines_aux rest max_width ls ws (t :: cur_rev) (cur_w + adv)
      end
  end.

Definition break_into_lines
    (tokens : list TextToken)
    (max_width : Z)
    (letter_spacing word_spacing : Z) : list (list TextToken) :=
  break_into_lines_aux tokens max_width letter_spacing word_spacing [] 0.

(** Lemma: Token order and content are strictly conserved across line breaking. *)
Lemma concat_break_into_lines_aux : forall tokens max_width ls ws cur_rev cur_w,
  concat (break_into_lines_aux tokens max_width ls ws cur_rev cur_w) = rev cur_rev ++ tokens.
Proof.
  induction tokens as [| t rest IH]; intros max_width ls ws cur_rev cur_w.
  - simpl. destruct cur_rev; simpl; rewrite ?app_nil_r; reflexivity.
  - simpl.
    destruct cur_rev as [| c cs].
    + specialize (IH max_width ls ws [t] (compute_token_advance t ls ws)).
      simpl in IH. rewrite IH. reflexivity.
    + destruct (cur_w + compute_token_advance t ls ws <=? max_width) eqn:Efit.
      * specialize (IH max_width ls ws (t :: c :: cs) (cur_w + compute_token_advance t ls ws)).
        rewrite IH. simpl. rewrite <- app_assoc. reflexivity.
      * destruct (is_break_opportunity t) eqn:Eopp.
        -- simpl. specialize (IH max_width ls ws [t] (compute_token_advance t ls ws)).
           rewrite IH. simpl. reflexivity.
        -- specialize (IH max_width ls ws (t :: c :: cs) (cur_w + compute_token_advance t ls ws)).
           rewrite IH. simpl. rewrite <- app_assoc. reflexivity.
Qed.

Theorem break_into_lines_preserves_tokens : forall tokens max_width ls ws,
  concat (break_into_lines tokens max_width ls ws) = tokens.
Proof.
  intros.
  unfold break_into_lines.
  rewrite concat_break_into_lines_aux.
  simpl. reflexivity.
Qed.

(** Conservation of total advance width across all broken lines. *)
Definition lines_total_width (lines : list (list TextToken)) (letter_spacing word_spacing : Z) : Z :=
  fold_right (fun l acc => line_width l letter_spacing word_spacing + acc) 0 lines.

Lemma lines_total_width_concat : forall lines ls ws,
  lines_total_width lines ls ws = line_width (concat lines) ls ws.
Proof.
  induction lines as [| l ls' IH]; intros ls ws.
  - reflexivity.
  - simpl. rewrite IH. rewrite line_width_app. reflexivity.
Qed.

Theorem lines_width_conservation : forall tokens max_width ls ws,
  lines_total_width (break_into_lines tokens max_width ls ws) ls ws =
  line_width tokens ls ws.
Proof.
  intros.
  rewrite lines_total_width_concat.
  rewrite break_into_lines_preserves_tokens.
  reflexivity.
Qed.

(** * 5. Boundedness of Greedy Line Breaking *)

(** An unbreakable long word is a line whose total advance exceeds max_width because
    it contains tokens that could not be broken (is_break_opportunity = false). *)
Definition is_unbreakable_long_word
    (line : list TextToken) (max_width : Z) (letter_spacing word_spacing : Z) : Prop :=
  line_width line letter_spacing word_spacing > max_width /\
  exists t, In t line /\ is_break_opportunity t = false.

(** Inductive invariant helper for line breaking boundedness. *)
Lemma break_into_lines_aux_bounded :
  forall tokens max_width ls ws,
    0 <= max_width ->
    forall cur_rev cur_w,
      (forall t, In t tokens -> compute_token_advance t ls ws <= max_width) ->
      cur_w = line_width (rev cur_rev) ls ws ->
      (cur_rev = [] \/
       cur_w <= max_width \/
       (exists t, In t (rev cur_rev) /\ is_break_opportunity t = false)) ->
      forall line,
        In line (break_into_lines_aux tokens max_width ls ws cur_rev cur_w) ->
        line_width line ls ws <= max_width \/
        is_unbreakable_long_word line max_width ls ws.
Proof.
  intros tokens max_width ls ws Hmax_pos.
  induction tokens as [| t rest IH]; intros cur_rev cur_w Htok_adv Hcur_w Hcur_inv line Hline.
  - simpl in Hline.
    destruct cur_rev as [| c cs].
    + contradiction Hline.
    + simpl in Hline. destruct Hline as [Heq | Hcontra]; [| contradiction].
      subst line.
      change (rev cs ++ [c]) with (rev (c :: cs)).
      destruct Hcur_inv as [Hemp | [Hle | [t0 [Hin0 Hopp0]]]].
      * discriminate Hemp.
      * left. rewrite <- Hcur_w. exact Hle.
      * destruct (Z_le_gt_dec cur_w max_width) as [Hwle | Hwgt].
        -- left. rewrite <- Hcur_w. exact Hwle.
        -- right. unfold is_unbreakable_long_word.
           split; [rewrite <- Hcur_w; exact Hwgt | exists t0; auto].
  - simpl in Hline.
    assert (Hadv_t : compute_token_advance t ls ws <= max_width).
    { apply Htok_adv. simpl. left. reflexivity. }
    assert (Hrest_adv : forall t', In t' rest -> compute_token_advance t' ls ws <= max_width).
    { intros t' Hin'. apply Htok_adv. simpl. right. exact Hin'. }
    destruct cur_rev as [| c cs].
    + (* cur_rev is empty *)
      apply (IH [t] (compute_token_advance t ls ws) Hrest_adv).
      * simpl; lia.
      * right; left; lia.
      * exact Hline.
    + (* cur_rev is non-empty *)
      destruct (cur_w + compute_token_advance t ls ws <=? max_width) eqn:Efit.
      * apply Z.leb_le in Efit.
        apply (IH (t :: c :: cs) (cur_w + compute_token_advance t ls ws) Hrest_adv).
        -- rewrite line_width_rev_cons. rewrite Hcur_w. reflexivity.
        -- right; left; lia.
        -- exact Hline.
      * apply Z.leb_gt in Efit.
        destruct (is_break_opportunity t) eqn:Eopp.
        -- simpl in Hline.
           destruct Hline as [Heq | Hin_rest].
           ++ subst line.
              change (rev cs ++ [c]) with (rev (c :: cs)).
              destruct Hcur_inv as [Hemp | [Hle | [t0 [Hin0 Hopp0]]]].
              ** discriminate Hemp.
              ** left. rewrite <- Hcur_w. exact Hle.
              ** destruct (Z_le_gt_dec cur_w max_width) as [Hwle | Hwgt].
                 --- left. rewrite <- Hcur_w. exact Hwle.
                 --- right. unfold is_unbreakable_long_word.
                     split; [rewrite <- Hcur_w; exact Hwgt | exists t0; auto].
           ++ apply (IH [t] (compute_token_advance t ls ws) Hrest_adv).
              ** simpl; lia.
              ** right; left; lia.
              ** exact Hin_rest.
        -- apply (IH (t :: c :: cs) (cur_w + compute_token_advance t ls ws) Hrest_adv).
           ++ rewrite line_width_rev_cons. rewrite Hcur_w. reflexivity.
           ++ right; right.
              exists t.
              split.
              ** change (rev (t :: c :: cs)) with (rev (c :: cs) ++ [t]).
                 apply in_or_app. right. simpl. left. reflexivity.
              ** exact Eopp.
           ++ exact Hline.
Qed.

(** Theorem: For tokens whose individual advances do not exceed max_width,
    every resulting line has total width <= max_width (except unbreakable long words). *)
Theorem greedy_break_bounded :
  forall (tokens : list TextToken) (max_width letter_spacing word_spacing : Z) (line : list TextToken),
    0 <= max_width ->
    (forall t, In t tokens -> compute_token_advance t letter_spacing word_spacing <= max_width) ->
    In line (break_into_lines tokens max_width letter_spacing word_spacing) ->
    line_width line letter_spacing word_spacing <= max_width \/
    is_unbreakable_long_word line max_width letter_spacing word_spacing.
Proof.
  intros tokens max_width ls ws line Hmax Hadv Hin.
  unfold break_into_lines in Hin.
  eapply break_into_lines_aux_bounded; eauto.
Qed.

(** Corollary: When words can be broken at all opportunities,
    every resulting line strictly satisfies line_width <= max_width. *)
Theorem greedy_break_bounded_when_all_breakable :
  forall (tokens : list TextToken) (max_width letter_spacing word_spacing : Z) (line : list TextToken),
    0 <= max_width ->
    (forall t, In t tokens -> compute_token_advance t letter_spacing word_spacing <= max_width) ->
    (forall t, In t line -> is_break_opportunity t = true) ->
    In line (break_into_lines tokens max_width letter_spacing word_spacing) ->
    line_width line letter_spacing word_spacing <= max_width.
Proof.
  intros tokens max_width ls ws line Hmax Hadv Hopp Hin.
  destruct (greedy_break_bounded tokens max_width ls ws line Hmax Hadv Hin) as [Hfit | Hlong].
  - exact Hfit.
  - destruct Hlong as [_ [t [Hin_line Hnot_opp]]].
    specialize (Hopp t Hin_line).
    congruence.
Qed.

(** Corollary: If a line is not an unbreakable long word, its width is <= max_width. *)
Theorem greedy_break_bounded_except_unbreakable :
  forall (tokens : list TextToken) (max_width letter_spacing word_spacing : Z) (line : list TextToken),
    0 <= max_width ->
    (forall t, In t tokens -> compute_token_advance t letter_spacing word_spacing <= max_width) ->
    In line (break_into_lines tokens max_width letter_spacing word_spacing) ->
    ~ is_unbreakable_long_word line max_width letter_spacing word_spacing ->
    line_width line letter_spacing word_spacing <= max_width.
Proof.
  intros tokens max_width ls ws line Hmax Hadv Hin Hnot_long.
  destruct (greedy_break_bounded tokens max_width ls ws line Hmax Hadv Hin) as [Hfit | Hlong].
  - exact Hfit.
  - contradiction (Hnot_long Hlong).
Qed.
