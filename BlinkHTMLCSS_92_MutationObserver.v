(* Blink2Coq HTML/CSS Synthesis for MutationObserver *)
(* Source: renderer/core/dom/mutation_observer.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition enqueue_mutations (current_size added : Z) : Z := current_size + added.
Theorem mutation_queue_growth : forall sz k,
  0 < k -> sz < enqueue_mutations sz k.
Proof. intros. unfold enqueue_mutations. lia. Qed.
