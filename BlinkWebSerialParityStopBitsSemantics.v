Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Web Serial Parity and Stop Bits Semantics *)
(** Web Serial API §3.2 ParityType and StopBits enums *)

Inductive serial_parity : Type :=
| ParityNone
| ParityEven
| ParityOdd.

Inductive serial_stop_bits : Type :=
| StopBits1
| StopBits2.

Definition parity_to_int (p : serial_parity) : Z :=
  match p with
  | ParityNone => 0
  | ParityEven => 1
  | ParityOdd  => 2
  end.

Definition stop_bits_to_int (s : serial_stop_bits) : Z :=
  match s with
  | StopBits1 => 1
  | StopBits2 => 2
  end.

Theorem parity_distinct : forall p1 p2,
  parity_to_int p1 = parity_to_int p2 -> p1 = p2.
Proof.
  intros p1 p2 H; destruct p1; destruct p2; simpl in H; try reflexivity; discriminate.
Qed.

Theorem stop_bits_distinct : forall s1 s2,
  stop_bits_to_int s1 = stop_bits_to_int s2 -> s1 = s2.
Proof.
  intros s1 s2 H; destruct s1; destruct s2; simpl in H; try reflexivity; discriminate.
Qed.
