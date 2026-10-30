From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §17.6.2.1 Collapsed Border Style Precedence *)
Inductive TableBorderStyle :=
  | TBS_None
  | TBS_Dotted
  | TBS_Dashed
  | TBS_Solid
  | TBS_Double
  | TBS_Hidden.

Definition border_style_precedence (s : TableBorderStyle) : Z :=
  match s with
  | TBS_Hidden => 5
  | TBS_Double => 4
  | TBS_Solid  => 3
  | TBS_Dashed => 2
  | TBS_Dotted => 1
  | TBS_None   => 0
  end.

Definition resolve_border_style (s1 s2 : TableBorderStyle) : TableBorderStyle :=
  if border_style_precedence s2 <=? border_style_precedence s1 then s1 else s2.

Theorem resolve_border_style_hidden_l : forall s,
  resolve_border_style TBS_Hidden s = TBS_Hidden.
Proof.
  intros s. unfold resolve_border_style. cbn.
  destruct s; reflexivity.
Qed.

Theorem resolve_border_style_hidden_r : forall s,
  s <> TBS_Hidden ->
  resolve_border_style s TBS_Hidden = TBS_Hidden.
Proof.
  intros s Hneq. unfold resolve_border_style. cbn.
  destruct s; [reflexivity | reflexivity | reflexivity | reflexivity | reflexivity | contradiction Hneq; reflexivity].
Qed.

Theorem resolve_border_style_precedence_ge : forall s1 s2,
  border_style_precedence (resolve_border_style s1 s2) >= border_style_precedence s1 /\
  border_style_precedence (resolve_border_style s1 s2) >= border_style_precedence s2.
Proof.
  intros s1 s2. unfold resolve_border_style.
  destruct (border_style_precedence s2 <=? border_style_precedence s1) eqn:E;
  [apply Z.leb_le in E | apply Z.leb_gt in E]; lia.
Qed.
