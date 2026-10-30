From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* W3C CSSOM View §12 Scroll Hit-Test Mapping *)
Definition viewport_to_content (vx vy sx sy : Z) : Z * Z :=
  (vx + sx, vy + sy).

Definition content_to_viewport (cx cy sx sy : Z) : Z * Z :=
  (cx - sx, cy - sy).

Theorem scroll_hit_test_roundtrip : forall vx vy sx sy,
  let '(cx, cy) := viewport_to_content vx vy sx sy in
  content_to_viewport cx cy sx sy = (vx, vy).
Proof.
  intros vx vy sx sy.
  unfold viewport_to_content, content_to_viewport.
  f_equal; lia.
Qed.
