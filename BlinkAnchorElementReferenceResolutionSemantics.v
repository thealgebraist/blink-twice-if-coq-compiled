Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Anchor Element Reference Resolution Semantics *)
(** CSS Anchor Positioning §2: anchor lookup by id or fallback *)

Definition resolve_anchor_id (explicit_id default_id : Z) : Z :=
  if explicit_id =? 0 then default_id else explicit_id.

Theorem explicit_anchor_takes_precedence : forall eid did,
  eid <> 0 ->
  resolve_anchor_id eid did = eid.
Proof.
  intros eid did H.
  unfold resolve_anchor_id.
  destruct (eid =? 0) eqn:Heq.
  - apply Z.eqb_eq in Heq; contradiction.
  - reflexivity.
Qed.

Theorem default_anchor_used_when_zero : forall did,
  resolve_anchor_id 0 did = did.
Proof.
  intros did.
  unfold resolve_anchor_id; reflexivity.
Qed.
