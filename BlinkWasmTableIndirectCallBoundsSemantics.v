Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebAssembly Table Indirect Call Bounds Semantics *)
(** WebAssembly Core Spec §5.4: call_indirect trap unless index in bounds *)

Definition call_indirect_valid (index table_size : Z) : bool :=
  (0 <=? index) && (index <? table_size).

Theorem call_indirect_sound : forall idx sz,
  call_indirect_valid idx sz = true <-> (0 <= idx /\ idx < sz).
Proof.
  intros idx sz.
  unfold call_indirect_valid.
  rewrite andb_true_iff.
  rewrite Z.leb_le, Z.ltb_lt.
  tauto.
Qed.
