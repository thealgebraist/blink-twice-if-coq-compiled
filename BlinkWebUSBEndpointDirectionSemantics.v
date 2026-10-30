Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebUSB Endpoint Direction Classification Semantics *)
(** WebUSB API §3.7 / USB 2.0 §9.6.6 endpoint address bit 7 *)

Inductive usb_direction : Type :=
| USB_OUT
| USB_IN.

Definition endpoint_direction (addr : Z) : usb_direction :=
  if Z.testbit addr 7 then USB_IN else USB_OUT.

Definition endpoint_number (addr : Z) : Z :=
  Z.land addr 15.

Theorem endpoint_in_has_bit7 : forall addr,
  endpoint_direction addr = USB_IN <-> Z.testbit addr 7 = true.
Proof.
  intros addr.
  unfold endpoint_direction.
  destruct (Z.testbit addr 7) eqn:E; split; intro H; try reflexivity; try discriminate; assumption.
Qed.
