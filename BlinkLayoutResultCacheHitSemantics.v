From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* Blink LayoutNG Layout Result Cache Hit Invariance *)
Record PhysicalFragmentGeometry := {
  pfg_width : Z;
  pfg_height : Z;
  pfg_offset_x : Z;
  pfg_offset_y : Z
}.

Definition geometry_matches (g1 g2 : PhysicalFragmentGeometry) : Prop :=
  pfg_width g1 = pfg_width g2 /\
  pfg_height g1 = pfg_height g2 /\
  pfg_offset_x g1 = pfg_offset_x g2 /\
  pfg_offset_y g1 = pfg_offset_y g2.

Theorem cache_hit_preserves_dimensions : forall g1 g2,
  geometry_matches g1 g2 ->
  pfg_width g1 = pfg_width g2 /\ pfg_height g1 = pfg_height g2.
Proof.
  intros g1 g2 [Hw [Hh [Hx Hy]]].
  split; assumption.
Qed.
