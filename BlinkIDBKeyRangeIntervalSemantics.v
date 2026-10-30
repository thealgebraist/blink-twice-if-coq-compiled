Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink IndexedDB IDBKeyRange Interval Semantics *)
(** IndexedDB 3 §4: closed key range containment *)

Record IDBClosedRange := {
  range_lower : Z;
  range_upper : Z
}.

Definition key_in_closed_range (k : Z) (r : IDBClosedRange) : bool :=
  (range_lower r <=? k) && (k <=? range_upper r).

Theorem key_in_closed_range_sound : forall k r,
  key_in_closed_range k r = true <-> (range_lower r <= k /\ k <= range_upper r).
Proof.
  intros k [l u].
  unfold key_in_closed_range. cbn [range_lower range_upper].
  rewrite andb_true_iff.
  rewrite Z.leb_le, Z.leb_le.
  tauto.
Qed.
