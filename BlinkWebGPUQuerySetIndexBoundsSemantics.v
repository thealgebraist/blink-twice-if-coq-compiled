Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebGPU Query Set Index Bounds Semantics *)
(** WebGPU §14.1: query index within [0, query_count) *)

Definition is_valid_query_index (idx count : Z) : bool :=
  (0 <=? idx) && (idx <? count).

Theorem query_index_sound : forall idx cnt,
  is_valid_query_index idx cnt = true <-> (0 <= idx /\ idx < cnt).
Proof.
  intros idx cnt.
  unfold is_valid_query_index.
  rewrite andb_true_iff, Z.leb_le, Z.ltb_lt.
  tauto.
Qed.
