Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebUSB Alternate Settings Validation Semantics *)
(** WebUSB API §3.5 selectAlternateSetting *)

Definition is_valid_alternate_setting (alt_idx num_alts : Z) : bool :=
  (0 <=? alt_idx) && (alt_idx <? num_alts).

Theorem valid_alternate_setting_sound : forall alt num,
  is_valid_alternate_setting alt num = true ->
  0 <= alt < num.
Proof.
  intros alt num H.
  unfold is_valid_alternate_setting in H.
  apply andb_prop in H.
  destruct H as [Hge Hlt].
  apply Z.leb_le in Hge.
  apply Z.ltb_lt in Hlt.
  split; assumption.
Qed.
