Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Payment Amount Decimal Format Semantics *)
(** Payment Request API §5.5: PaymentCurrencyAmount value syntax *)

Record decimal_amount : Type := mk_decimal {
  int_part   : Z;
  frac_part  : option Z;
  frac_scale : Z
}.

Definition is_valid_decimal_amount (d : decimal_amount) : bool :=
  (0 <=? int_part d) &&
  match frac_part d with
  | Some f => (0 <=? f) && (0 <? frac_scale d)
  | None   => true
  end.

Theorem valid_decimal_amount_sound : forall d,
  is_valid_decimal_amount d = true ->
  0 <= int_part d /\
  (forall f, frac_part d = Some f -> 0 <= f /\ 0 < frac_scale d).
Proof.
  intros [ip fp fs] H.
  unfold is_valid_decimal_amount in H; simpl in H.
  apply andb_prop in H.
  destruct H as [Hip Hfp].
  apply Z.leb_le in Hip.
  split; [exact Hip |].
  intros f Hf.
  simpl in Hf.
  rewrite Hf in Hfp.
  apply andb_prop in Hfp.
  destruct Hfp as [Hf0 Hfs].
  apply Z.leb_le in Hf0.
  apply Z.ltb_lt in Hfs.
  split; assumption.
Qed.
