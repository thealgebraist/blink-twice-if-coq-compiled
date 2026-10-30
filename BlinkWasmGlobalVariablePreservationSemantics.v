Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebAssembly Mutable Global Variable Preservation Semantics *)
(** WebAssembly Core Spec §5.4: global value type bounds preservation *)

Definition TYPE_I32 : Z := 1.
Definition TYPE_I64 : Z := 2.

Definition global_value_valid (val_type val : Z) : bool :=
  if val_type =? TYPE_I32 then
    (-2147483648 <=? val) && (val <=? 2147483647)
  else true.

Theorem i32_in_bounds_valid : forall v,
  -2147483648 <= v <= 2147483647 ->
  global_value_valid TYPE_I32 v = true.
Proof.
  intros v Hv.
  unfold global_value_valid, TYPE_I32.
  rewrite Z.eqb_refl.
  apply andb_true_intro.
  split; apply Z.leb_le; lia.
Qed.
