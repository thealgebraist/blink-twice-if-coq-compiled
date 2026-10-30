Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink FileList Allocation Semantics *)
(** File API §3: file list length non-negativity *)

Definition file_list_count (n : Z) : Z :=
  Z.max 0 n.

Theorem file_list_nonneg : forall n,
  0 <= file_list_count n.
Proof.
  intros n.
  unfold file_list_count; lia.
Qed.
