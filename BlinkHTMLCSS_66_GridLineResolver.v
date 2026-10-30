(* Blink2Coq HTML/CSS Synthesis for GridLineResolver *)
(* Source: renderer/core/layout/grid/grid_line_resolver.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition resolve_grid_end_line (start span : Z) : Z := start + span.
Theorem grid_end_line_strictly_greater : forall start span,
  0 < span -> start < resolve_grid_end_line start span.
Proof. intros. unfold resolve_grid_end_line. lia. Qed.
