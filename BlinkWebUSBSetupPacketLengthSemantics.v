Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebUSB Setup Packet Length Semantics *)
(** WebUSB API §3.3 / USB 2.0 §9.3 Setup Packet (8 bytes) *)

Record usb_setup_packet : Type := mk_setup {
  bmRequestType : Z;
  bRequest      : Z;
  wValue        : Z;
  wIndex        : Z;
  wLength       : Z
}.

Definition setup_packet_size (p : usb_setup_packet) : Z :=
  1 + 1 + 2 + 2 + 2.

Theorem setup_packet_size_is_8 : forall p,
  setup_packet_size p = 8.
Proof.
  intros p.
  unfold setup_packet_size.
  reflexivity.
Qed.
