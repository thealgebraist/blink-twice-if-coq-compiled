Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Compression Stream Format Semantics *)
(** Compression Streams §3: format enum {deflate, gzip, deflate-raw} *)

Inductive comp_format : Type :=
| FormatDeflate
| FormatGzip
| FormatDeflateRaw.

Definition comp_format_to_int (f : comp_format) : Z :=
  match f with
  | FormatDeflate    => 0
  | FormatGzip       => 1
  | FormatDeflateRaw => 2
  end.

Theorem comp_format_distinct : forall f1 f2,
  comp_format_to_int f1 = comp_format_to_int f2 -> f1 = f2.
Proof.
  intros f1 f2 H; destruct f1; destruct f2; simpl in H; try reflexivity; discriminate.
Qed.
