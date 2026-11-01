(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record LinearGradientStopLerp := mkLinearGradientStopLerp {
  lineargradientstoplerp_stop0_chan : Z;
  lineargradientstoplerp_stop1_chan : Z;
  lineargradientstoplerp_t_q8 : Z
}.

Definition gradient_lerp_u8 (c0 : Z) (c1 : Z) (t_q8 : Z) : Z :=
  let t := Z.max 0 (Z.min 256 t_q8) in (c0 * (256 - t) + c1 * t) / 256.

Theorem gradient_lerp_u8_in_byte_range :
  forall (c0 c1 t_q8 : Z), 0 <= c0 <= 255 -> 0 <= c1 <= 255 -> 0 <= gradient_lerp_u8 c0 c1 t_q8 <= 255.
Proof.
  intros c0 c1 t_q8 H0 H1. unfold gradient_lerp_u8.
  set (t := Z.max 0 (Z.min 256 t_q8)).
  assert (Ht : 0 <= t <= 256) by (unfold t; lia).
  split.
  - apply Z.div_pos; [nia | lia].
  - apply Z.div_le_upper_bound; [lia | nia].
Qed.
