Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Web Bluetooth Write Chunk Size Semantics *)
(** Web Bluetooth §4.5 writeValue bounds (ATT MTU - 3 <= 512 bytes) *)

Definition is_valid_write_chunk (chunk_sz mtu : Z) : bool :=
  (1 <=? chunk_sz) && (chunk_sz <=? Z.min (mtu - 3) 512).

Theorem valid_write_chunk_sound : forall chunk_sz mtu,
  is_valid_write_chunk chunk_sz mtu = true ->
  1 <= chunk_sz /\ chunk_sz <= 512 /\ chunk_sz <= mtu - 3.
Proof.
  intros chunk_sz mtu H.
  unfold is_valid_write_chunk in H.
  apply andb_prop in H.
  destruct H as [Hge Hle].
  apply Z.leb_le in Hge.
  apply Z.leb_le in Hle.
  split; [exact Hge |].
  destruct (Z.min_dec (mtu - 3) 512) as [Hmin | Hmin]; rewrite Hmin in Hle; split; lia.
Qed.
