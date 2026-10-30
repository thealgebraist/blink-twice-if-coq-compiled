(* Blink2Coq Synthesis for LayoutUnit *)
(* Source: third_party/blink/renderer/platform/geometry/layout_unit.h *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition sat_add_pos (a b : Z) : Z :=
  if 2147483647 <? a + b then 2147483647 else a + b.
Theorem sat_add_pos_nonneg : forall a b,
  0 <= a -> 0 <= b -> 0 <= sat_add_pos a b.
Proof.
  intros a b Ha Hb. unfold sat_add_pos.
  destruct (2147483647 <? a + b); lia.
Qed.
