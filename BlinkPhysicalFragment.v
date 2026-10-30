(******************************************************************************)
(* BlinkPhysicalFragment.v                                                    *)
(* Core Physical Fragment Representation for Chromium Blink LayoutNG          *)
(******************************************************************************)

From Stdlib Require Import ZArith List.
Import ListNotations.
Open Scope Z_scope.

Inductive PhysicalFragment : Type :=
  | mkPhysicalFragment (pf_offset_x pf_offset_y pf_width pf_height : Z)
                       (pf_children : list PhysicalFragment).

Definition pf_w (pf : PhysicalFragment) : Z :=
  match pf with
  | mkPhysicalFragment _ _ w _ _ => w
  end.

Definition pf_h (pf : PhysicalFragment) : Z :=
  match pf with
  | mkPhysicalFragment _ _ _ h _ => h
  end.

Definition pf_x (pf : PhysicalFragment) : Z :=
  match pf with
  | mkPhysicalFragment x _ _ _ _ => x
  end.

Definition pf_y (pf : PhysicalFragment) : Z :=
  match pf with
  | mkPhysicalFragment _ y _ _ _ => y
  end.

Definition pf_children (pf : PhysicalFragment) : list PhysicalFragment :=
  match pf with
  | mkPhysicalFragment _ _ _ _ ch => ch
  end.

Definition get_fragment_children (pf : PhysicalFragment) : list PhysicalFragment :=
  pf_children pf.
