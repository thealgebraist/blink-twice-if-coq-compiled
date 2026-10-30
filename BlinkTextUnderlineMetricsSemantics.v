Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Text Underline Metrics Semantics *)
(** CSS Text Decoration 4 §2: underline offset and thickness bounds *)

Record UnderlineMetrics := {
  ul_offset : Z;
  ul_thickness : Z
}.

Definition resolve_underline_metrics (raw_offset raw_thickness : Z) : UnderlineMetrics :=
  {| ul_offset := raw_offset;
     ul_thickness := Z.max 1 raw_thickness |}.

Theorem underline_thickness_strictly_positive : forall off thick,
  0 < ul_thickness (resolve_underline_metrics off thick).
Proof.
  intros off thick.
  unfold resolve_underline_metrics; simpl.
  lia.
Qed.
