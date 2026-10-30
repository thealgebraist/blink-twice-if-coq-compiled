Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Popover Backdrop Coverage Semantics *)
(** HTML / CSS Position 4 §6: ::backdrop full viewport coverage *)

Record BackdropRect := {
  rx : Z;
  ry : Z;
  rw : Z;
  rh : Z
}.

Definition resolve_backdrop_bounds (vpw vph : Z) : BackdropRect :=
  {| rx := 0;
     ry := 0;
     rw := Z.max 0 vpw;
     rh := Z.max 0 vph |}.

Theorem backdrop_covers_viewport : forall w h,
  0 <= w ->
  0 <= h ->
  rw (resolve_backdrop_bounds w h) = w /\
  rh (resolve_backdrop_bounds w h) = h.
Proof.
  intros w h Hw Hh.
  unfold resolve_backdrop_bounds; simpl; lia.
Qed.
