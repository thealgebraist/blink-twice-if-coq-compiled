Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Record PhysicalRect := mkPhysicalRect {
  pr_x : Z;
  pr_y : Z;
  pr_w : Z;
  pr_h : Z
}.

Definition physical_rect_unite (a b : PhysicalRect) : PhysicalRect :=
  let nx := Z.min (pr_x a) (pr_x b) in
  let ny := Z.min (pr_y a) (pr_y b) in
  let nr := Z.max (pr_x a + pr_w a) (pr_x b + pr_w b) in
  let nb := Z.max (pr_y a + pr_h a) (pr_y b + pr_h b) in
  mkPhysicalRect nx ny (nr - nx) (nb - ny).

Theorem physical_rect_unite_idempotent :
  forall (r : PhysicalRect),
    0 <= pr_w r ->
    0 <= pr_h r ->
    physical_rect_unite r r = r.
Proof.
  intros [x y w h] Hw Hh.
  unfold physical_rect_unite. simpl.
  rewrite !Z.min_id.
  rewrite !Z.max_id.
  assert (Hw_sub: x + w - x = w) by ring.
  assert (Hh_sub: y + h - y = h) by ring.
  rewrite Hw_sub, Hh_sub.
  reflexivity.
Qed.
