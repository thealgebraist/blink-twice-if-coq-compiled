Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Porter-Duff Normal Blending Semantics *)
(** Compositing and Blending 1 §3: source-over normal blending *)

Definition blend_source_over (src dst sa : Z) : Z :=
  (src * sa + dst * (255 - sa)) / 255.

Theorem blend_source_over_full_source : forall s d,
  blend_source_over s d 255 = s.
Proof.
  intros s d.
  unfold blend_source_over.
  replace (s * 255 + d * (255 - 255)) with (s * 255) by ring.
  rewrite Z.div_mul by lia.
  reflexivity.
Qed.

Theorem blend_source_over_zero_source : forall s d,
  blend_source_over s d 0 = d.
Proof.
  intros s d.
  unfold blend_source_over.
  replace (s * 0 + d * (255 - 0)) with (d * 255) by ring.
  rewrite Z.div_mul by lia.
  reflexivity.
Qed.
