(* Blink2Coq Synthesis for FloatsUtils *)
(* Source: third_party/blink/renderer/core/layout/floats_utils.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition compute_clearance (clear_y margin_y : Z) : Z :=
  Z.max 0 (clear_y - margin_y).
Theorem clearance_nonneg : forall cy my,
  0 <= compute_clearance cy my.
Proof. intros. unfold compute_clearance. apply Z.le_max_l. Qed.
