(* Blink2Coq Synthesis for WritingModeConverter *)
(* Source: third_party/blink/renderer/core/layout/geometry/writing_mode_converter.h *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition logical_to_physical_vr (cw x : Z) : Z := cw - x.
Definition physical_to_logical_vr (cw px : Z) : Z := cw - px.
Theorem writing_mode_vr_involution : forall cw x,
  physical_to_logical_vr cw (logical_to_physical_vr cw x) = x.
Proof. intros. unfold logical_to_physical_vr, physical_to_logical_vr. ring. Qed.
