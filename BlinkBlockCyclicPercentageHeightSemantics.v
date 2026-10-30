Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Block Cyclic Percentage Height Semantics *)
(** CSS 2.1 §10.5: indefinite containing block percentage height fallback *)

Definition resolve_block_pct_height (is_cb_definite : bool) (pct cb_height content_height : Z) : Z :=
  if is_cb_definite then (pct * cb_height) / 100 else content_height.

Theorem indefinite_breaks_cycle : forall pct cb content,
  resolve_block_pct_height false pct cb content = content.
Proof.
  intros pct cb content.
  unfold resolve_block_pct_height.
  reflexivity.
Qed.
