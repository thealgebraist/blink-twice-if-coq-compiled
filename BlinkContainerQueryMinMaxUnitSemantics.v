Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Container Query Min/Max Units cqmin and cqmax Semantics *)
(** CSS Containment 3 §3: cqmin = min(cqi, cqb); cqmax = max(cqi, cqb) *)

Definition resolve_cqmin (cqi cqb : Z) : Z :=
  Z.min cqi cqb.

Definition resolve_cqmax (cqi cqb : Z) : Z :=
  Z.max cqi cqb.

Theorem cqmin_le_cqmax : forall i b,
  resolve_cqmin i b <= resolve_cqmax i b.
Proof.
  intros i b.
  unfold resolve_cqmin, resolve_cqmax; lia.
Qed.
