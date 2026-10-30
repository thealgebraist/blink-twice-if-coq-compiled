Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Web Bluetooth 16-bit to 128-bit UUID Expansion Semantics *)
(** Bluetooth Core Spec v5.4 Vol 3 Part B §2.5.1: 16-bit UUID expansion *)

Definition base_uuid_low : Z := 100080000080599.
Definition two_to_96 : Z := 79228162514264337593543950336.

Definition expand_uuid16 (u16 : Z) : Z :=
  u16 * two_to_96 + base_uuid_low.

Theorem expand_uuid16_injective : forall u1 u2,
  expand_uuid16 u1 = expand_uuid16 u2 ->
  u1 = u2.
Proof.
  intros u1 u2 H.
  unfold expand_uuid16 in H.
  assert (Heq : u1 * two_to_96 = u2 * two_to_96) by lia.
  assert (Hnz : two_to_96 <> 0) by (unfold two_to_96; lia).
  apply (Z.mul_reg_r u1 u2 two_to_96 Hnz Heq).
Qed.

Theorem expand_uuid16_range : forall u16,
  0 <= u16 < 65536 ->
  base_uuid_low <= expand_uuid16 u16 < 65536 * two_to_96 + base_uuid_low.
Proof.
  intros u16 [H0 H1].
  unfold expand_uuid16.
  assert (two_to_96 > 0) by (unfold two_to_96; lia).
  split.
  - assert (0 <= u16 * two_to_96) by (apply Z.mul_nonneg_nonneg; lia). lia.
  - assert (u16 * two_to_96 < 65536 * two_to_96).
    { apply Z.mul_lt_mono_pos_r; [lia | lia]. }
    lia.
Qed.
