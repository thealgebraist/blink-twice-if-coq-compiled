Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Record Outsets := mkOutsets {
  out_top : Z;
  out_right : Z;
  out_bottom : Z;
  out_left : Z
}.

Definition union_outsets (a b : Outsets) : Outsets :=
  mkOutsets
    (Z.max (out_top a) (out_top b))
    (Z.max (out_right a) (out_right b))
    (Z.max (out_bottom a) (out_bottom b))
    (Z.max (out_left a) (out_left b)).

Theorem union_outsets_idempotent :
  forall (o : Outsets),
    union_outsets o o = o.
Proof.
  intros [t r b l].
  unfold union_outsets. simpl.
  rewrite !Z.max_id.
  reflexivity.
Qed.
