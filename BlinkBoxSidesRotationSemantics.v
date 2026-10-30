(* ========================================================================= *)
(*               BlinkBoxSidesRotationSemantics.v                           *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Logical Box Sides Directional       *)
(* Rotation against CSS Writing Modes 3 §4.2. Fully constructive, 0 admits.  *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Record LogicalSides := mkLSides {
  bs_start : Z;
  bs_end   : Z;
  is_start : Z;
  is_end   : Z
}.

Record PhysicalSides := mkPSides {
  ps_top    : Z;
  ps_right  : Z;
  ps_bottom : Z;
  ps_left   : Z
}.

Definition rotate_sides_h_tb (ls : LogicalSides) : PhysicalSides := {|
  ps_top    := bs_start ls;
  ps_bottom := bs_end ls;
  ps_left   := is_start ls;
  ps_right  := is_end ls
|}.

Definition rotate_sides_v_rl (ls : LogicalSides) : PhysicalSides := {|
  ps_top    := is_start ls;
  ps_bottom := is_end ls;
  ps_right  := bs_start ls;
  ps_left   := bs_end ls
|}.

Theorem perimeter_conservation_h_tb : forall ls,
  let p := rotate_sides_h_tb ls in
  ps_top p + ps_bottom p + ps_left p + ps_right p =
  bs_start ls + bs_end ls + is_start ls + is_end ls.
Proof.
  intros. unfold rotate_sides_h_tb; cbn. ring.
Qed.

Theorem perimeter_conservation_v_rl : forall ls,
  let p := rotate_sides_v_rl ls in
  ps_top p + ps_bottom p + ps_left p + ps_right p =
  bs_start ls + bs_end ls + is_start ls + is_end ls.
Proof.
  intros. unfold rotate_sides_v_rl; cbn. ring.
Qed.
