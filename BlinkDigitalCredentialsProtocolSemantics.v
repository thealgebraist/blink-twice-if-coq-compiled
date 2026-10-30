Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Digital Credentials Protocol Encapsulation Semantics *)
(** Digital Credentials API §3: supported wallet exchange protocols *)

Definition PROTOCOL_OPENID4VP : Z := 1.
Definition PROTOCOL_ISO_MDL   : Z := 2.

Definition is_supported_protocol (protocol_id : Z) : bool :=
  (protocol_id =? PROTOCOL_OPENID4VP) || (protocol_id =? PROTOCOL_ISO_MDL).

Theorem openid4vp_supported :
  is_supported_protocol PROTOCOL_OPENID4VP = true.
Proof.
  reflexivity.
Qed.

Theorem iso_mdl_supported :
  is_supported_protocol PROTOCOL_ISO_MDL = true.
Proof.
  reflexivity.
Qed.
