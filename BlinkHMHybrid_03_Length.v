(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record Length := mkLength {
  length_value : Z;
  length_type : Z
}.

Definition resolve_length (val : Z) (ltype : Z) (max_extent : Z) : Z :=
  if ltype =? 1 then val else if ltype =? 2 then (if val <=? 0 then 0 else (max_extent * val) / 100) else max_extent.

Theorem resolve_length_nonneg :
  forall (val ltype max_extent : Z), 0 <= val -> 0 <= max_extent -> 0 <= resolve_length val ltype max_extent.
Proof.
  intros val ltype max_ext Hval Hmax.
  unfold resolve_length.
  destruct (ltype =? 1) eqn:E1; [lia |].
  destruct (ltype =? 2) eqn:E2; [| lia].
  destruct (val <=? 0) eqn:Ev; [lia |].
  apply Z.leb_gt in Ev.
  apply Z.div_pos; [| lia].
  apply Z.mul_nonneg_nonneg; lia.
Qed.
