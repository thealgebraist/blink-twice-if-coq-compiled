From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Compositing and Blending 1 §3.1 Blend Mode Isolation *)
Inductive BlendMode :=
  | BM_Normal
  | BM_Multiply
  | BM_Screen
  | BM_Overlay.

Definition requires_stacking_context_isolation (bm : BlendMode) : bool :=
  match bm with
  | BM_Normal => false
  | _ => true
  end.

Theorem non_normal_blend_mode_creates_isolation : forall bm,
  bm <> BM_Normal ->
  requires_stacking_context_isolation bm = true.
Proof.
  intros bm Hneq.
  unfold requires_stacking_context_isolation.
  destruct bm; [contradiction Hneq; reflexivity | reflexivity | reflexivity | reflexivity].
Qed.
