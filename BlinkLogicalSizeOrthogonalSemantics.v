(* ========================================================================= *)
(*               BlinkLogicalSizeOrthogonalSemantics.v                      *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Orthogonal Writing Modes Size       *)
(* Transposition against CSS Writing Modes 3 §7.3. Fully constructive.       *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Record LogicalSize := mkLSize {
  ls_inline : Z;
  ls_block  : Z
}.

Record PhysicalSize := mkPSize {
  ps_width  : Z;
  ps_height : Z
}.

Definition transpose_orthogonal (ls : LogicalSize) : PhysicalSize :=
  {| ps_width  := ls_block ls;
     ps_height := ls_inline ls |}.

Definition transpose_to_logical (ps : PhysicalSize) : LogicalSize :=
  {| ls_inline := ps_height ps;
     ls_block  := ps_width ps |}.

Theorem orthogonal_size_involution : forall ls,
  transpose_to_logical (transpose_orthogonal ls) = ls.
Proof.
  intros ls. destruct ls. reflexivity.
Qed.

Theorem orthogonal_area_conserved : forall ls,
  ps_width (transpose_orthogonal ls) * ps_height (transpose_orthogonal ls) =
  ls_inline ls * ls_block ls.
Proof.
  intros ls. destruct ls; cbn. ring.
Qed.
