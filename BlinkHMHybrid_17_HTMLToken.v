(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record HTMLToken := mkHTMLToken {
  htmltoken_tag_code : Z;
  htmltoken_token_kind : Z;
  htmltoken_self_closing : bool;
  htmltoken_attr_count : Z
}.

Definition html_ascii_lower (c : Z) : Z :=
  if (65 <=? c) && (c <=? 90) then c + 32 else c.

Theorem html_ascii_lower_idempotent :
  forall (c : Z), html_ascii_lower (html_ascii_lower c) = html_ascii_lower c.
Proof.
  intros c. unfold html_ascii_lower.
  destruct ((65 <=? c) && (c <=? 90)) eqn:E1.
  - apply andb_true_iff in E1 as [H1 H2].
    apply Z.leb_le in H1. apply Z.leb_le in H2.
    assert (E2 : ((65 <=? c + 32) && (c + 32 <=? 90)) = false).
    { apply andb_false_iff. right. apply Z.leb_gt. lia. }
    rewrite E2. reflexivity.
  - rewrite E1. reflexivity.
Qed.
