(* Blink2Coq HTML/CSS Synthesis for HTMLTokenizer *)
(* Source: renderer/core/html/parser/html_tokenizer.cc *)

Require Import ZArith Bool Lia. Open Scope Z_scope.
Definition ascii_to_lower (c : Z) : Z :=
  if (65 <=? c) && (c <=? 90) then c + 32 else c.
Theorem ascii_to_lower_idempotent : forall c,
  ascii_to_lower (ascii_to_lower c) = ascii_to_lower c.
Proof.
  intros c. unfold ascii_to_lower.
  destruct ((65 <=? c) && (c <=? 90)) eqn:E.
  - apply andb_prop in E. destruct E as [E1 E2].
    apply Z.leb_le in E1. apply Z.leb_le in E2.
    assert (E3: (c + 32 <=? 90) = false) by (apply Z.leb_gt; lia).
    rewrite E3, andb_false_r. reflexivity.
  - rewrite E. reflexivity.
Qed.
