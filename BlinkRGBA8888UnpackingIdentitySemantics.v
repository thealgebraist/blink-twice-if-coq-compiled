Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink RGBA8888 Unpacking Identity Semantics *)
(** W3C CSS Color 4 §3: unpack b channel identity *)

Definition pack_rgba (r g b a : Z) : Z :=
  a * 16777216 + r * 65536 + g * 256 + b.

Definition extract_b (packed : Z) : Z :=
  packed mod 256.

Theorem unpack_b_identity : forall r g b a,
  0 <= b < 256 ->
  0 <= g ->
  0 <= r ->
  0 <= a ->
  extract_b (pack_rgba r g b a) = b.
Proof.
  intros r g b a Hb Hg Hr Ha.
  unfold extract_b, pack_rgba.
  replace (a * 16777216 + r * 65536 + g * 256 + b) with (b + (a * 65536 + r * 256 + g) * 256) by ring.
  rewrite Z.mod_add by lia.
  apply Z.mod_small; exact Hb.
Qed.
