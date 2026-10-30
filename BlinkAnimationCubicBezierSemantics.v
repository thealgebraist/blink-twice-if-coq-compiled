Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Cubic Bézier Timing Function Semantics *)
(** CSS Easing 1 §3.1: cubic-bezier endpoints at t=0 and t=1000 *)

Definition eval_cubic_bezier_endpoints (t : Z) : Z :=
  Z.max 0 (Z.min 1000 t).

Theorem bezier_endpoint_start :
  eval_cubic_bezier_endpoints 0 = 0.
Proof.
  unfold eval_cubic_bezier_endpoints; reflexivity.
Qed.

Theorem bezier_endpoint_end :
  eval_cubic_bezier_endpoints 1000 = 1000.
Proof.
  unfold eval_cubic_bezier_endpoints; reflexivity.
Qed.

Theorem bezier_endpoints_bounded : forall t,
  0 <= eval_cubic_bezier_endpoints t <= 1000.
Proof.
  intros t.
  unfold eval_cubic_bezier_endpoints.
  lia.
Qed.
