(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record SkiaRRectCornerClamp := mkSkiaRRectCornerClamp {
  skiarrectcornerclamp_box_w : Z;
  skiarrectcornerclamp_box_h : Z;
  skiarrectcornerclamp_raw_radius : Z
}.

Definition clamp_rrect_radius (w : Z) (h : Z) (r : Z) : Z :=
  Z.min (Z.max 0 r) (Z.min (w / 2) (h / 2)).

Theorem clamp_rrect_radius_non_overlapping :
  forall (w h r : Z), 0 <= w -> 0 <= h -> 0 <= clamp_rrect_radius w h r /\ 2 * clamp_rrect_radius w h r <= w /\ 2 * clamp_rrect_radius w h r <= h.
Proof.
  intros w h r Hw Hh. unfold clamp_rrect_radius.
  assert (Hdw : 0 <= w / 2 /\ 2 * (w / 2) <= w) by (split; [apply Z.div_pos; lia | apply Z.mul_div_le; lia]).
  assert (Hdh : 0 <= h / 2 /\ 2 * (h / 2) <= h) by (split; [apply Z.div_pos; lia | apply Z.mul_div_le; lia]).
  lia.
Qed.
