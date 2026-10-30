(* ========================================================================= *)
(*               BlinkTextOffsetRangeSliceSemantics.v                       *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Text Offset Range Slice             *)
(* Intersection. Fully constructive, 0 admits.                               *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Record TextRange := mkTextRange {
  tr_start : Z;
  tr_end   : Z
}.

Definition intersect_text_range (r1 r2 : TextRange) : TextRange :=
  {| tr_start := Z.max (tr_start r1) (tr_start r2);
     tr_end   := Z.min (tr_end r1) (tr_end r2) |}.

Definition text_range_len (r : TextRange) : Z :=
  Z.max 0 (tr_end r - tr_start r).

Theorem intersect_len_le_left : forall r1 r2,
  text_range_len (intersect_text_range r1 r2) <= text_range_len r1.
Proof.
  intros. unfold text_range_len, intersect_text_range; cbn. lia.
Qed.

Theorem intersect_len_le_right : forall r1 r2,
  text_range_len (intersect_text_range r1 r2) <= text_range_len r2.
Proof.
  intros. unfold text_range_len, intersect_text_range; cbn. lia.
Qed.
