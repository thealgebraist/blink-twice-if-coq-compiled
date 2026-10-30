(* Blink2Coq HTML/CSS Synthesis for Hyphenator *)
(* Source: renderer/core/layout/inline/hyphenator.cc *)

From Stdlib Require Import ZArith Bool Lia. Open Scope Z_scope.
Definition is_hyphen_valid (len pos min_pref min_suff : Z) : bool :=
  (min_pref <=? pos) && (pos <=? len - min_suff).
Theorem hyphen_valid_implies_prefix_suffix : forall len pos min_pref min_suff,
  is_hyphen_valid len pos min_pref min_suff = true ->
  min_pref <= pos /\ pos <= len - min_suff.
Proof.
  intros len pos min_pref min_suff H.
  unfold is_hyphen_valid in H.
  apply andb_prop in H. destruct H as [H1 H2].
  apply Z.leb_le in H1. apply Z.leb_le in H2.
  split; assumption.
Qed.
