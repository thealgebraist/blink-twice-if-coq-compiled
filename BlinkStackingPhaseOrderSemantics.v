From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 Appendix E 7-Phase Painting Order *)
Inductive StackingPaintPhase :=
  | PhaseBackground
  | PhaseNegZ
  | PhaseBlockChildren
  | PhaseFloats
  | PhaseInlines
  | PhaseAutoZ
  | PhasePosZ.

Definition phase_index (p : StackingPaintPhase) : Z :=
  match p with
  | PhaseBackground    => 0
  | PhaseNegZ          => 1
  | PhaseBlockChildren => 2
  | PhaseFloats        => 3
  | PhaseInlines       => 4
  | PhaseAutoZ         => 5
  | PhasePosZ          => 6
  end.

Definition phase_painted_before (p1 p2 : StackingPaintPhase) : Prop :=
  phase_index p1 <= phase_index p2.

Theorem background_painted_first : forall p,
  phase_painted_before PhaseBackground p.
Proof.
  intros p. unfold phase_painted_before. cbn.
  destruct p; cbn; lia.
Qed.

Theorem pos_z_painted_last : forall p,
  phase_painted_before p PhasePosZ.
Proof.
  intros p. unfold phase_painted_before. cbn.
  destruct p; cbn; lia.
Qed.

Theorem phase_order_transitive : forall p1 p2 p3,
  phase_painted_before p1 p2 ->
  phase_painted_before p2 p3 ->
  phase_painted_before p1 p3.
Proof.
  intros p1 p2 p3. unfold phase_painted_before. lia.
Qed.
