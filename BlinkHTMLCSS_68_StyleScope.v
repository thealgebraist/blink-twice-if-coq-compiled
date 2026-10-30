(* Blink2Coq HTML/CSS Synthesis for StyleScope *)
(* Source: renderer/core/css/style_scope.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition scope_depth (root_depth limit_depth : Z) : Z :=
  Z.max 0 (limit_depth - root_depth).
Theorem scope_depth_nonnegative : forall r l,
  0 <= scope_depth r l.
Proof. intros. unfold scope_depth. apply Z.le_max_l. Qed.
