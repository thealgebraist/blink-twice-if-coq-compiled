Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebCrypto HKDF Info Length Bounds Semantics *)
(** RFC 5869 §2.3: info parameter length within bounds *)

Definition MAX_HKDF_INFO : Z := 65536.

Definition is_valid_hkdf_info (len : Z) : bool :=
  (0 <=? len) && (len <=? MAX_HKDF_INFO).

Theorem hkdf_info_sound : forall len,
  is_valid_hkdf_info len = true <-> (0 <= len /\ len <= MAX_HKDF_INFO).
Proof.
  intros len.
  unfold is_valid_hkdf_info, MAX_HKDF_INFO.
  rewrite andb_true_iff, Z.leb_le, Z.leb_le.
  tauto.
Qed.
