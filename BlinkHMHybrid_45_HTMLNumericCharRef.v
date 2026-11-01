(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record HTMLNumericCharRef := mkHTMLNumericCharRef {
  htmlnumericcharref_raw_codepoint : Z
}.

Definition sanitize_char_ref (cp : Z) : Z :=
  if (cp <=? 0) || (1114111 <? cp) || ((55296 <=? cp) && (cp <=? 57343)) then 65533 else cp.

Theorem sanitize_char_ref_always_valid_scalar :
  forall (cp : Z), 1 <= sanitize_char_ref cp <= 1114111 /\ ~ (55296 <= sanitize_char_ref cp <= 57343).
Proof.
  intros cp. unfold sanitize_char_ref.
  destruct (cp <=? 0) eqn:E0; simpl.
  - lia.
  - destruct (1114111 <? cp) eqn:Emax; simpl.
    + lia.
    + destruct ((55296 <=? cp) && (cp <=? 57343)) eqn:Esur; simpl.
      * lia.
      * apply Z.leb_gt in E0. apply Z.ltb_ge in Emax.
        apply andb_false_iff in Esur.
        destruct Esur as [Es1 | Es2]; [apply Z.leb_gt in Es1 | apply Z.leb_gt in Es2]; lia.
Qed.
