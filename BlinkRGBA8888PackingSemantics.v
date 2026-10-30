Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink RGBA8888 Color Packing Semantics *)
(** W3C CSS Color 4 §3: pack r, g, b, a into 32-bit integer *)

Definition pack_rgba (r g b a : Z) : Z :=
  a * 16777216 + r * 65536 + g * 256 + b.

Theorem pack_rgba_zero :
  pack_rgba 0 0 0 0 = 0.
Proof.
  unfold pack_rgba; reflexivity.
Qed.

Theorem pack_rgba_monotonic_alpha : forall r g b a1 a2,
  0 <= r ->
  0 <= g ->
  0 <= b ->
  a1 <= a2 ->
  pack_rgba r g b a1 <= pack_rgba r g b a2.
Proof.
  intros r g b a1 a2 Hr Hg Hb Ha.
  unfold pack_rgba; lia.
Qed.
