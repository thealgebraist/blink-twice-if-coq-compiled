Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebCrypto ECDSA Named Curve Semantics *)
(** Web Cryptography API §24.2: named curves P-256, P-384, P-521 *)

Definition is_valid_curve (c : Z) : bool :=
  (c =? 256) || (c =? 384) || (c =? 521).

Theorem p256_curve_valid :
  is_valid_curve 256 = true.
Proof.
  reflexivity.
Qed.

Theorem p521_curve_valid :
  is_valid_curve 521 = true.
Proof.
  reflexivity.
Qed.

Theorem curve_25519_invalid_for_ecdsa :
  is_valid_curve 25519 = false.
Proof.
  reflexivity.
Qed.
