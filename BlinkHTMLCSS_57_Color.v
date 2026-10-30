(* Blink2Coq HTML/CSS Synthesis for Color *)
(* Source: renderer/platform/graphics/color.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition premultiply_channel (c a : Z) : Z := (c * a) / 255.
Theorem premultiply_channel_bounded : forall c a,
  0 <= c <= 255 -> 0 <= a <= 255 -> premultiply_channel c a <= a.
Proof.
  intros c a Hc Ha. unfold premultiply_channel.
  apply Z.div_le_upper_bound; [lia | nia].
Qed.
