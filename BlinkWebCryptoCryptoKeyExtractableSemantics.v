Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebCrypto CryptoKey Extractable Invariance *)
(** Web Cryptography API §13.1: extractable boolean is immutable *)

Record CryptoKey := {
  key_extractable : bool;
  key_algorithm   : Z
}.

Definition set_key_algorithm (k : CryptoKey) (new_alg : Z) : CryptoKey := {|
  key_extractable := key_extractable k;
  key_algorithm   := new_alg
|}.

Theorem extractable_preserved_across_ops : forall k alg,
  key_extractable (set_key_algorithm k alg) = key_extractable k.
Proof.
  intros k alg.
  reflexivity.
Qed.
