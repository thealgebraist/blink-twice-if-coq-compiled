Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Barcode Detection Format Semantics *)
(** Shape Detection API §3: BarcodeFormat enum distinctness *)

Inductive barcode_format : Type :=
| BarcodeQR
| BarcodeEAN13
| BarcodeCode128
| BarcodeAztec.

Definition barcode_to_int (b : barcode_format) : Z :=
  match b with
  | BarcodeQR      => 0
  | BarcodeEAN13   => 1
  | BarcodeCode128 => 2
  | BarcodeAztec   => 3
  end.

Theorem barcode_format_distinct : forall b1 b2,
  barcode_to_int b1 = barcode_to_int b2 -> b1 = b2.
Proof.
  intros b1 b2 H; destruct b1; destruct b2; simpl in H; try reflexivity; discriminate.
Qed.
