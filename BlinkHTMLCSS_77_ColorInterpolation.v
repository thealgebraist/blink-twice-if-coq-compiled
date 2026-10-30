(* Blink2Coq HTML/CSS Synthesis for ColorInterpolation *)
(* Source: renderer/core/css/color_interpolation.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition lerp_pct (v1 v2 t : Z) : Z :=
  (v1 * (100 - t) + v2 * t) / 100.
Theorem lerp_endpoints : forall v1 v2,
  lerp_pct v1 v2 0 = v1 /\ lerp_pct v1 v2 100 = v2.
Proof.
  intros v1 v2. unfold lerp_pct. split.
  - assert (H: v1 * (100 - 0) + v2 * 0 = v1 * 100) by ring.
    rewrite H. apply (Z.div_mul v1 100). lia.
  - assert (H: v1 * (100 - 100) + v2 * 100 = v2 * 100) by ring.
    rewrite H. apply (Z.div_mul v2 100). lia.
Qed.
