(* Blink2Coq Synthesis for PhysicalRect *)
(* Source: third_party/blink/renderer/core/layout/geometry/physical_rect.h *)

Require Import ZArith Lia. Open Scope Z_scope.
Record PhysicalRect := mkPhysicalRect { pr_x: Z; pr_w: Z }.
Definition physical_rect_unite_1d (a b: PhysicalRect) : PhysicalRect :=
  let nx := Z.min (pr_x a) (pr_x b) in
  let nr := Z.max (pr_x a + pr_w a) (pr_x b + pr_w b) in
  mkPhysicalRect nx (nr - nx).
Theorem physical_rect_unite_1d_idempotent : forall r,
  0 <= pr_w r -> physical_rect_unite_1d r r = r.
Proof.
  intros [x w] Hw. unfold physical_rect_unite_1d. simpl.
  rewrite Z.min_id, Z.max_id.
  assert (E: x + w - x = w) by ring. rewrite E. reflexivity.
Qed.
