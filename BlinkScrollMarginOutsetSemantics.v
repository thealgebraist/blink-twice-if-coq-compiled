Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Scroll Margin Outset Semantics *)
(** CSS Scroll Snap 1 §4: snap area expansion *)

Definition expand_snap_area (area_dim margin : Z) : Z :=
  area_dim + 2 * Z.max 0 margin.

Theorem snap_area_expansion_monotonic : forall area m,
  0 <= area ->
  area <= expand_snap_area area m.
Proof.
  intros area m Harea.
  unfold expand_snap_area.
  lia.
Qed.
