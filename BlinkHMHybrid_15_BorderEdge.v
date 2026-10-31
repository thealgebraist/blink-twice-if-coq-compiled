(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record BorderEdge := mkBorderEdge {
  borderedge_width : Z;
  borderedge_style : Z;
  borderedge_is_present : bool
}.

Definition resolve_edge_width (w : Z) (style : Z) (present : bool) : Z :=
  if negb present then 0 else if style =? 0 then 0 else if style =? 2 then 0 else w.

Theorem resolve_edge_width_bounded :
  forall (w style : Z) (present : bool), 0 <= w -> 0 <= resolve_edge_width w style present <= w.
Proof.
  intros w style present Hw.
  unfold resolve_edge_width.
  destruct present; simpl.
  - destruct (style =? 0) eqn:Es0; [lia |].
    destruct (style =? 2) eqn:Es2; [lia |].
    lia.
  - lia.
Qed.
