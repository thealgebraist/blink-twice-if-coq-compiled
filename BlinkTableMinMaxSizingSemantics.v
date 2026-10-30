From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS Table 3 §3.1 Table Intrinsic Min/Max Content Sizing *)
Record ColSizing := {
  col_min_content : Z;
  col_max_content : Z
}.

Fixpoint sum_min_content (cols : list ColSizing) : Z :=
  match cols with
  | nil => 0
  | c :: rest => col_min_content c + sum_min_content rest
  end.

Fixpoint sum_max_content (cols : list ColSizing) : Z :=
  match cols with
  | nil => 0
  | c :: rest => col_max_content c + sum_max_content rest
  end.

Theorem table_min_le_max_content : forall cols,
  (forall c, In c cols -> col_min_content c <= col_max_content c) ->
  sum_min_content cols <= sum_max_content cols.
Proof.
  induction cols as [| c rest IH]; intros Hle; cbn.
  - lia.
  - assert (Hc: col_min_content c <= col_max_content c) by (apply Hle; left; reflexivity).
    assert (Hrest: sum_min_content rest <= sum_max_content rest).
    { apply IH. intros x Hx; apply Hle; right; exact Hx. }
    lia.
Qed.
