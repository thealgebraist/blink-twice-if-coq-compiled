Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Select Element selectedIndex Bounds Semantics *)
(** HTML Standard §4.10.7: selectedIndex within [-1, options.length - 1] *)

Definition clamp_selected_index (idx options_count : Z) : Z :=
  if options_count <=? 0 then -1
  else Z.max (-1) (Z.min (options_count - 1) idx).

Theorem selected_index_bounded : forall i opt,
  0 < opt ->
  -1 <= clamp_selected_index i opt < opt.
Proof.
  intros i opt Hopt.
  unfold clamp_selected_index.
  destruct (opt <=? 0) eqn:Heq.
  - apply Z.leb_le in Heq; lia.
  - lia.
Qed.
