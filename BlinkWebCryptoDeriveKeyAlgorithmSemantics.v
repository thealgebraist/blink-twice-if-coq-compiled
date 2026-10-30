Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebCrypto deriveKey Algorithm Constraint Semantics *)
(** Web Cryptography API §14.3.8: deriveKey requires USAGE_DERIVE_KEY *)

Definition USAGE_DERIVE_KEY : Z := 8.

Definition derive_key_allowed (usage_mask : Z) : bool :=
  Z.land usage_mask USAGE_DERIVE_KEY =? USAGE_DERIVE_KEY.

Theorem derive_key_sound : forall u,
  derive_key_allowed u = true <-> Z.land u USAGE_DERIVE_KEY = USAGE_DERIVE_KEY.
Proof.
  intros u.
  unfold derive_key_allowed.
  apply Z.eqb_eq.
Qed.
