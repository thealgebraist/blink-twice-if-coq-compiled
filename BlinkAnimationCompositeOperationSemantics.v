Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Composite Operation Semantics *)
(** Web Animations §5.4: composite operations *)

Inductive CompositeOp :=
  | CompositeReplace
  | CompositeAdd
  | CompositeAccumulate.

Definition apply_composite_op (op : CompositeOp) (base anim : Z) : Z :=
  match op with
  | CompositeReplace => anim
  | CompositeAdd => base + anim
  | CompositeAccumulate => base + anim
  end.

Theorem replace_ignores_base : forall base anim,
  apply_composite_op CompositeReplace base anim = anim.
Proof.
  intros base anim.
  reflexivity.
Qed.

Theorem add_is_additive : forall base anim,
  apply_composite_op CompositeAdd base anim = base + anim.
Proof.
  intros base anim.
  reflexivity.
Qed.
