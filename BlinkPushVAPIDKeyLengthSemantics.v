Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Push VAPID Key Length Semantics *)
(** RFC 8292 §3 / Push API: VAPID uncompressed P-256 public key length is 65 bytes *)

Definition is_valid_vapid_length (len : Z) : bool :=
  len =? 65.

Theorem vapid_length_sound : forall len,
  is_valid_vapid_length len = true <-> len = 65.
Proof.
  intros len.
  unfold is_valid_vapid_length.
  split; intro H.
  - apply Z.eqb_eq in H. exact H.
  - apply Z.eqb_eq. exact H.
Qed.
