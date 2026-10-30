Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebHID 32-Bit Usage Page Decomposition Semantics *)
(** WebHID API §3.3 / USB HID 1.11 §5.5 Usage Page & Usage ID *)

Definition hid_usage_page (u32 : Z) : Z := u32 / 65536.
Definition hid_usage_id (u32 : Z) : Z := u32 mod 65536.

Theorem hid_usage_decomposition_sound : forall u32,
  0 <= u32 < 4294967296 ->
  0 <= hid_usage_page u32 < 65536 /\
  0 <= hid_usage_id u32 < 65536 /\
  u32 = (hid_usage_page u32) * 65536 + hid_usage_id u32.
Proof.
  intros u32 [H0 H1].
  unfold hid_usage_page, hid_usage_id.
  assert (Hpos : 0 < 65536) by lia.
  assert (Hpos' : 65536 <> 0) by lia.
  pose proof (Z.div_mod u32 65536 Hpos') as Hdm.
  pose proof (Z.mod_pos_bound u32 65536 Hpos) as Hmod.
  pose proof (Z.div_pos u32 65536 H0 Hpos) as Hdiv0.
  assert (Hdiv65536 : u32 / 65536 < 65536).
  { apply Z.div_lt_upper_bound; lia. }
  split; [| split].
  - lia.
  - lia.
  - rewrite (Z.mul_comm (u32 / 65536) 65536).
    exact Hdm.
Qed.
