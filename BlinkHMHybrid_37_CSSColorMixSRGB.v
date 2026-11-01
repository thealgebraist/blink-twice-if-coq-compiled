(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record CSSColorMixSRGB := mkCSSColorMixSRGB {
  csscolormixsrgb_chan1 : Z;
  csscolormixsrgb_chan2 : Z;
  csscolormixsrgb_weight_pct : Z
}.

Definition mix_srgb_byte (c1 : Z) (c2 : Z) (p : Z) : Z :=
  (c1 * p + c2 * (100 - p)) / 100.

Theorem mix_srgb_byte_in_u8_range :
  forall (c1 c2 p : Z), 0 <= c1 <= 255 -> 0 <= c2 <= 255 -> 0 <= p <= 100 -> 0 <= mix_srgb_byte c1 c2 p <= 255.
Proof.
  intros c1 c2 p Hc1 Hc2 Hp. unfold mix_srgb_byte. split.
  - apply Z.div_pos; [nia | lia].
  - apply Z.div_le_upper_bound; [lia | nia].
Qed.
