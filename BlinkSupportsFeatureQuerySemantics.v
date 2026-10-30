From Stdlib Require Import Bool Lia.

(* CSS Conditional 3 §3 @supports Feature Query Boolean AST *)
Inductive SupportsAST :=
  | SupportsTrue
  | SupportsFalse
  | SupportsAnd (s1 s2 : SupportsAST)
  | SupportsOr  (s1 s2 : SupportsAST)
  | SupportsNot (s : SupportsAST).

Fixpoint eval_supports (ast : SupportsAST) : bool :=
  match ast with
  | SupportsTrue      => true
  | SupportsFalse     => false
  | SupportsAnd s1 s2 => andb (eval_supports s1) (eval_supports s2)
  | SupportsOr  s1 s2 => orb  (eval_supports s1) (eval_supports s2)
  | SupportsNot s     => negb (eval_supports s)
  end.

Theorem supports_de_morgan_and : forall s1 s2,
  eval_supports (SupportsNot (SupportsAnd s1 s2)) =
  eval_supports (SupportsOr (SupportsNot s1) (SupportsNot s2)).
Proof.
  intros s1 s2; cbn.
  destruct (eval_supports s1); destruct (eval_supports s2); reflexivity.
Qed.

Theorem supports_de_morgan_or : forall s1 s2,
  eval_supports (SupportsNot (SupportsOr s1 s2)) =
  eval_supports (SupportsAnd (SupportsNot s1) (SupportsNot s2)).
Proof.
  intros s1 s2; cbn.
  destruct (eval_supports s1); destruct (eval_supports s2); reflexivity.
Qed.
