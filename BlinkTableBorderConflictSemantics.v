(* ========================================================================= *)
(*               BlinkTableBorderConflictSemantics.v                         *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink collapsed table border conflict       *)
(* resolution per W3C CSS 2.1 §17.6.2.1.                                    *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Inductive TableBorderStyle :=
  | BNone
  | BHidden
  | BDotted
  | BDashed
  | BSolid
  | BDouble
  | BGroove
  | BRidge
  | BInset
  | BOutset.

Inductive TableElementLevel :=
  | LevelTable
  | LevelColGroup
  | LevelCol
  | LevelRowGroup
  | LevelRow
  | LevelCell.

Record TableBorder := {
  b_style : TableBorderStyle;
  b_width : Z;
  b_level : TableElementLevel;
  b_id : Z
}.

Definition style_rank (s : TableBorderStyle) : Z :=
  match s with
  | BHidden => 10
  | BDouble => 9
  | BSolid => 8
  | BDashed => 7
  | BDotted => 6
  | BRidge => 5
  | BOutset => 4
  | BGroove => 3
  | BInset => 2
  | BNone => 0
  end.

Definition level_rank (l : TableElementLevel) : Z :=
  match l with
  | LevelCell => 6
  | LevelRow => 5
  | LevelRowGroup => 4
  | LevelCol => 3
  | LevelColGroup => 2
  | LevelTable => 1
  end.

Definition is_hidden (b : TableBorder) : bool :=
  match b_style b with
  | BHidden => true
  | _ => false
  end.

Definition is_none (b : TableBorder) : bool :=
  match b_style b with
  | BNone => true
  | _ => false
  end.

Definition border_wins_first (b1 b2 : TableBorder) : bool :=
  if is_hidden b1 then true
  else if is_hidden b2 then false
  else if is_none b2 then true
  else if is_none b1 then false
  else if b_width b2 <? b_width b1 then true
  else if b_width b1 <? b_width b2 then false
  else if style_rank (b_style b2) <? style_rank (b_style b1) then true
  else if style_rank (b_style b1) <? style_rank (b_style b2) then false
  else if level_rank (b_level b2) <? level_rank (b_level b1) then true
  else if level_rank (b_level b1) <? level_rank (b_level b2) then false
  else b_id b1 <=? b_id b2.

Definition resolve_border_conflict (b1 b2 : TableBorder) : TableBorder :=
  if border_wins_first b1 b2 then b1 else b2.

Theorem conflict_resolution_choice : forall b1 b2,
  resolve_border_conflict b1 b2 = b1 \/ resolve_border_conflict b1 b2 = b2.
Proof.
  intros b1 b2.
  unfold resolve_border_conflict.
  destruct (border_wins_first b1 b2); [left | right]; reflexivity.
Qed.

Theorem hidden_wins_left : forall b1 b2,
  b_style b1 = BHidden ->
  b_style (resolve_border_conflict b1 b2) = BHidden.
Proof.
  intros b1 b2 Hh1.
  unfold resolve_border_conflict, border_wins_first, is_hidden.
  rewrite Hh1.
  cbn.
  exact Hh1.
Qed.

Theorem hidden_wins_right : forall b1 b2,
  b_style b2 = BHidden ->
  b_style (resolve_border_conflict b1 b2) = BHidden.
Proof.
  intros b1 b2 Hh2.
  unfold resolve_border_conflict, border_wins_first.
  destruct (is_hidden b1) eqn:Hhb1.
  - unfold is_hidden in Hhb1.
    destruct (b_style b1); try discriminate.
    reflexivity.
  - unfold is_hidden.
    rewrite Hh2.
    cbn.
    exact Hh2.
Qed.

Theorem conflict_idempotent : forall b,
  resolve_border_conflict b b = b.
Proof.
  intros b.
  unfold resolve_border_conflict, border_wins_first.
  destruct (is_hidden b) eqn:Hh; [reflexivity |].
  destruct (is_none b) eqn:Hn; [reflexivity |].
  rewrite Z.ltb_irrefl.
  rewrite Z.ltb_irrefl.
  rewrite Z.ltb_irrefl.
  rewrite Z.leb_refl.
  reflexivity.
Qed.

Theorem thicker_width_wins : forall b1 b2,
  is_hidden b1 = false ->
  is_hidden b2 = false ->
  is_none b1 = false ->
  is_none b2 = false ->
  b_width b1 > b_width b2 ->
  resolve_border_conflict b1 b2 = b1.
Proof.
  intros b1 b2 Hh1 Hh2 Hn1 Hn2 Hw.
  unfold resolve_border_conflict, border_wins_first.
  rewrite Hh1, Hh2, Hn1, Hn2.
  assert (b_width b2 <? b_width b1 = true) by (apply Z.ltb_lt; lia).
  rewrite H.
  reflexivity.
Qed.

Theorem half_width_split_conservation : forall w,
  ((w / 2) + (w - (w / 2))) = w.
Proof.
  intros w.
  lia.
Qed.
