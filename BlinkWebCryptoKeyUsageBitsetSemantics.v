Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebCrypto KeyUsage Bitset Containment Semantics *)
(** Web Cryptography API §13.2: key usage permission verification *)

Definition has_key_usage (mask usage : Z) : bool :=
  Z.land mask usage =? usage.

Theorem usage_contained : forall mask usage,
  Z.land mask usage = usage ->
  has_key_usage mask usage = true.
Proof.
  intros mask usage H.
  unfold has_key_usage.
  rewrite H.
  apply Z.eqb_refl.
Qed.
