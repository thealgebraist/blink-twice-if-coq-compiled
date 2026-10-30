From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* HTML 5 §4.9.3 & CSS Table 3 §2 Colgroup Expansion *)
Record ColgroupSpec := {
  cgs_span : Z;
  cgs_width : Z
}.

Fixpoint expand_colgroup (spec : ColgroupSpec) (count : nat) : list Z :=
  match count with
  | O => nil
  | S n => cgs_width spec :: expand_colgroup spec n
  end.

Theorem expand_colgroup_length : forall spec n,
  length (expand_colgroup spec n) = n.
Proof.
  induction n as [| n' IH]; cbn; [reflexivity | f_equal; exact IH].
Qed.

Theorem expand_colgroup_uniform_width : forall spec n w,
  In w (expand_colgroup spec n) ->
  w = cgs_width spec.
Proof.
  induction n as [| n' IH]; intros w Hin; cbn in Hin; [contradiction Hin |].
  destruct Hin as [Heq | Hrest].
  - symmetry; exact Heq.
  - apply IH; exact Hrest.
Qed.
