Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Decompression Stream Roundtrip Preservation Semantics *)
(** Compression Streams §3: roundtrip length preservation *)

Definition decompressed_length (raw_len : Z) : Z :=
  raw_len.

Theorem roundtrip_length_preserved : forall raw_len,
  raw_len >= 0 ->
  decompressed_length raw_len = raw_len /\ decompressed_length raw_len >= 0.
Proof.
  intros raw_len Hge.
  unfold decompressed_length.
  split; [reflexivity | exact Hge].
Qed.
