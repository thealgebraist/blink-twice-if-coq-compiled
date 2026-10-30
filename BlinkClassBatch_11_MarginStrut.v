(* Blink2Coq Synthesis for MarginStrut *)
(* Source: third_party/blink/renderer/core/layout/geometry/margin_strut.h *)

Require Import ZArith Lia. Open Scope Z_scope.
Theorem margin_strut_pos_nonneg : forall p v,
  0 <= p -> 0 <= v -> 0 <= Z.max v p.
Proof. intros. apply Z.max_le_iff. left. lia. Qed.
