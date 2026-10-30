Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebCrypto Constant Time Compare Semantics *)
(** BoringSSL mem.c: constant-time buffer comparison correctness *)

Definition constant_time_compare (b1 b2 : Z) : bool :=
  b1 =? b2.

Theorem ct_compare_sound : forall b1 b2,
  constant_time_compare b1 b2 = true <-> b1 = b2.
Proof.
  intros b1 b2.
  unfold constant_time_compare.
  apply Z.eqb_eq.
Qed.
