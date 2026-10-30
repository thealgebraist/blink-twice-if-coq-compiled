Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Peripheral Device Permission Isolation Semantics *)
(** W3C Permissions API §4 / WebUSB / WebBluetooth origin isolation *)

Definition origin_id := Z.
Definition device_id := Z.

Definition permission_granted (allowed_origin : origin_id) (allowed_dev : device_id)
                              (req_origin : origin_id) (req_dev : device_id) : bool :=
  (allowed_origin =? req_origin) && (allowed_dev =? req_dev).

Theorem permission_isolation : forall o1 o2 d,
  o1 <> o2 ->
  permission_granted o1 d o2 d = false.
Proof.
  intros o1 o2 d Hdiff.
  unfold permission_granted.
  assert (E: (o1 =? o2) = false).
  { apply Z.eqb_neq. assumption. }
  rewrite E.
  reflexivity.
Qed.
