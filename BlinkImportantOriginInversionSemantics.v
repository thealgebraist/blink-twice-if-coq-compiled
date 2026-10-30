From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Cascading 5 §3 !important Origin Inversion *)
Definition rank_author_normal : Z := 2.
Definition rank_user_normal   : Z := 1.
Definition rank_user_important   : Z := 5.
Definition rank_author_important : Z := 4.

Theorem normal_author_beats_user :
  rank_author_normal > rank_user_normal.
Proof.
  unfold rank_author_normal, rank_user_normal. lia.
Qed.

Theorem important_inverts_precedence :
  rank_user_important > rank_author_important.
Proof.
  unfold rank_user_important, rank_author_important. lia.
Qed.
