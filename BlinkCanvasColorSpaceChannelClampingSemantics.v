Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Canvas Color Space Component Clamping Semantics *)
(** HTML Canvas 2D §11: color component byte clamping to [0, 255] *)

Definition clamp_color_channel (c : Z) : Z :=
  Z.max 0 (Z.min 255 c).

Theorem color_channel_bounded : forall c,
  0 <= clamp_color_channel c <= 255.
Proof.
  intros c.
  unfold clamp_color_channel; lia.
Qed.
