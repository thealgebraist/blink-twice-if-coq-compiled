Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Text Strikethrough Metrics Semantics *)
(** CSS Text Decoration 4 §2: strikethrough offset and thickness *)

Record StrikethroughMetrics := {
  st_y_offset : Z;
  st_thickness : Z
}.

Definition resolve_strikethrough_metrics (y_strikeout_pos raw_thick : Z) : StrikethroughMetrics :=
  {| st_y_offset := y_strikeout_pos;
     st_thickness := Z.max 1 raw_thick |}.

Theorem strikethrough_thickness_strictly_positive : forall pos thick,
  0 < st_thickness (resolve_strikethrough_metrics pos thick).
Proof.
  intros pos thick.
  unfold resolve_strikethrough_metrics; simpl.
  lia.
Qed.
