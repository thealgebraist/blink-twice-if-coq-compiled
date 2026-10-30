Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Inline Hyphenation Opportunity Semantics *)
(** CSS Text 3 §5.4: soft hyphen width and available space *)

Definition hyphenated_width (segment_w hyphen_w : Z) : Z :=
  segment_w + hyphen_w.

Definition fits_inline_space (segment_w hyphen_w avail_w : Z) : bool :=
  hyphenated_width segment_w hyphen_w <=? avail_w.

Theorem fits_inline_space_sound : forall seg hyp avail,
  fits_inline_space seg hyp avail = true ->
  seg + hyp <= avail.
Proof.
  intros seg hyp avail H.
  unfold fits_inline_space, hyphenated_width in H.
  apply Z.leb_le in H.
  exact H.
Qed.
