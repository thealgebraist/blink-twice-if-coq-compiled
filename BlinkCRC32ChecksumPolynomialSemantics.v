Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CRC-32 Checksum Polynomial Bounds Semantics *)
(** RFC 1952 §2.3.1: CRC-32 output is bounded within 32-bit unsigned range *)

Definition is_valid_crc32 (crc : Z) : bool :=
  (0 <=? crc) && (crc <? 4294967296).

Theorem crc32_bounds_sound : forall crc,
  is_valid_crc32 crc = true ->
  0 <= crc < 4294967296.
Proof.
  intros crc H.
  unfold is_valid_crc32 in H.
  apply andb_prop in H.
  destruct H as [H0 H4G].
  apply Z.leb_le in H0.
  apply Z.ltb_lt in H4G.
  split; assumption.
Qed.
