Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebAuthn authenticatorData Flags Bitmask Semantics *)
(** WebAuthn Level 3 §6.1: authenticator flags bitmask containment *)

Definition FLAG_UP : Z := 1.
Definition FLAG_UV : Z := 4.
Definition FLAG_AT : Z := 64.
Definition FLAG_ED : Z := 128.

Definition has_auth_data_flag (flags flag : Z) : bool :=
  Z.land flags flag =? flag.

Theorem flag_contained : forall f fl,
  Z.land f fl = fl ->
  has_auth_data_flag f fl = true.
Proof.
  intros f fl H.
  unfold has_auth_data_flag.
  rewrite H.
  apply Z.eqb_refl.
Qed.
