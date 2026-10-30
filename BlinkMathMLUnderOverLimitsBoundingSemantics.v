Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink MathML Munderover Height Bounding Semantics *)
(** MathML Core §3.5: total height accumulation *)

Definition compute_munderover_total_height (under_h base_h over_h gap1 gap2 : Z) : Z :=
  Z.max 0 under_h + Z.max 0 base_h + Z.max 0 over_h + Z.max 0 gap1 + Z.max 0 gap2.

Theorem munderover_height_ge_base : forall uh bh oh g1 g2,
  0 <= bh ->
  bh <= compute_munderover_total_height uh bh oh g1 g2.
Proof.
  intros uh bh oh g1 g2 Hbh.
  unfold compute_munderover_total_height; lia.
Qed.
