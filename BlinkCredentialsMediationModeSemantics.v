Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Credential Management Mediation Mode Semantics *)
(** Credential Management Level 1 §4: mediation requirement states *)

Definition MEDIATION_SILENT      : Z := 0.
Definition MEDIATION_OPTIONAL    : Z := 1.
Definition MEDIATION_REQUIRED    : Z := 2.
Definition MEDIATION_CONDITIONAL : Z := 3.

Theorem mediation_modes_distinct :
  MEDIATION_SILENT < MEDIATION_OPTIONAL /\
  MEDIATION_OPTIONAL < MEDIATION_REQUIRED /\
  MEDIATION_REQUIRED < MEDIATION_CONDITIONAL.
Proof.
  unfold MEDIATION_SILENT, MEDIATION_OPTIONAL, MEDIATION_REQUIRED, MEDIATION_CONDITIONAL.
  lia.
Qed.
