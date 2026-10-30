Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Web Bluetooth GATT Characteristic Properties Bitmask Semantics *)
(** Web Bluetooth §4.5 Characteristic Properties Bitmask *)

Definition PROP_BROADCAST : Z := 1.
Definition PROP_READ : Z := 2.
Definition PROP_WRITE_WITHOUT_RESPONSE : Z := 4.
Definition PROP_WRITE : Z := 8.
Definition PROP_NOTIFY : Z := 16.
Definition PROP_INDICATE : Z := 32.

Definition has_property (mask prop : Z) : bool :=
  negb (Z.land mask prop =? 0).

Definition can_read (mask : Z) : bool :=
  has_property mask PROP_READ.

Definition can_write (mask : Z) : bool :=
  (has_property mask PROP_WRITE) || (has_property mask PROP_WRITE_WITHOUT_RESPONSE).

Theorem read_enabled_by_prop_read : forall mask,
  Z.land mask PROP_READ <> 0 ->
  can_read mask = true.
Proof.
  intros mask H.
  unfold can_read, has_property, PROP_READ.
  apply negb_true_iff.
  apply Z.eqb_neq.
  assumption.
Qed.
