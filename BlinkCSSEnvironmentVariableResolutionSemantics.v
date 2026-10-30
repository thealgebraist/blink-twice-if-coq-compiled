Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink CSS Environment Variables Semantics *)
(** CSS Environment Variables 1 §2: env() safe-area inset non-negativity *)

Definition resolve_safe_area_inset (inset : Z) : Z :=
  Z.max 0 inset.

Theorem safe_area_inset_nonneg : forall i,
  0 <= resolve_safe_area_inset i.
Proof.
  intros i.
  unfold resolve_safe_area_inset; lia.
Qed.

Theorem safe_area_inset_idempotent : forall i,
  resolve_safe_area_inset (resolve_safe_area_inset i) = resolve_safe_area_inset i.
Proof.
  intros i.
  unfold resolve_safe_area_inset; lia.
Qed.
