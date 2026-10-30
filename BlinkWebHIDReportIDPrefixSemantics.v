Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebHID Report ID Prefix Semantics *)
(** WebHID API §4.2 Input/Output Report ID prefixing *)

Definition effective_hid_payload_len (raw_len : Z) (has_report_id : bool) : Z :=
  if has_report_id then raw_len - 1 else raw_len.

Theorem hid_payload_length_sound : forall raw_len has_id,
  raw_len >= 1 ->
  has_id = true ->
  effective_hid_payload_len raw_len has_id = raw_len - 1 /\
  effective_hid_payload_len raw_len has_id >= 0.
Proof.
  intros raw_len has_id Hraw Hid.
  unfold effective_hid_payload_len.
  rewrite Hid.
  split; lia.
Qed.
