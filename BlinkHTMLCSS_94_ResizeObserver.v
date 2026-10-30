(* Blink2Coq HTML/CSS Synthesis for ResizeObserver *)
(* Source: renderer/core/resize_observer/resize_observer.cc *)

From Stdlib Require Import ZArith Bool Lia. Open Scope Z_scope.
Definition is_size_changed (w1 h1 w2 h2 : Z) : bool :=
  negb ((w1 =? w2) && (h1 =? h2)).
Theorem size_unchanged_implies_zero_delta : forall w1 h1 w2 h2,
  is_size_changed w1 h1 w2 h2 = false ->
  w1 = w2 /\ h1 = h2.
Proof.
  intros w1 h1 w2 h2 H. unfold is_size_changed in H.
  apply negb_false_iff in H.
  apply andb_prop in H. destruct H as [Hw Hh].
  apply Z.eqb_eq in Hw. apply Z.eqb_eq in Hh.
  split; assumption.
Qed.
