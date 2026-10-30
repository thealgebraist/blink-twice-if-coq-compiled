Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebCrypto Wrapping Key Usage Enforcement Semantics *)
(** Web Cryptography API §14.3.11: wrapping requires USAGE_WRAP_KEY *)

Definition USAGE_WRAP_KEY : Z := 16.

Definition can_wrap_key (usage_mask : Z) : bool :=
  Z.land usage_mask USAGE_WRAP_KEY =? USAGE_WRAP_KEY.

Theorem wrap_key_sound : forall u,
  can_wrap_key u = true <-> Z.land u USAGE_WRAP_KEY = USAGE_WRAP_KEY.
Proof.
  intros u.
  unfold can_wrap_key.
  apply Z.eqb_eq.
Qed.
