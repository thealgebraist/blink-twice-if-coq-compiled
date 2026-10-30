Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Masonry Shortest Column Placement Semantics *)
(** CSS Grid 3 (Masonry) §2: minimal accumulated block height track selection *)

Definition select_shortest_column (h1 h2 : Z) : Z :=
  if h1 <=? h2 then 0 else 1.

Theorem shortest_column_picks_min : forall h1 h2,
  (select_shortest_column h1 h2 = 0 /\ h1 <= h2) \/
  (select_shortest_column h1 h2 = 1 /\ h2 < h1).
Proof.
  intros h1 h2.
  unfold select_shortest_column.
  destruct (h1 <=? h2) eqn:Heq.
  - apply Z.leb_le in Heq; left; split; [reflexivity | exact Heq].
  - apply Z.leb_gt in Heq; right; split; [reflexivity | exact Heq].
Qed.
