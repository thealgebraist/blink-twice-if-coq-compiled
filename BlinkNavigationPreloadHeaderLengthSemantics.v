Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Navigation Preload Header Length Semantics *)
(** Navigation Preload §4: Service-Worker-Navigation-Preload header length <= 8192 *)

Definition is_valid_preload_len (len : Z) : bool :=
  (0 <=? len) && (len <=? 8192).

Theorem preload_len_sound : forall len,
  is_valid_preload_len len = true ->
  0 <= len <= 8192.
Proof.
  intros len H.
  unfold is_valid_preload_len in H.
  apply andb_prop in H.
  destruct H as [H0 H8k].
  apply Z.leb_le in H0.
  apply Z.leb_le in H8k.
  split; assumption.
Qed.
