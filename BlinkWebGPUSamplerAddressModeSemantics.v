Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebGPU Sampler Address Mode Semantics *)
(** WebGPU §7.3: address modes discrimination *)

Definition SAMPLER_CLAMP_TO_EDGE : Z := 0.
Definition SAMPLER_REPEAT        : Z := 1.
Definition SAMPLER_MIRROR_REPEAT : Z := 2.

Theorem sampler_modes_distinct :
  SAMPLER_CLAMP_TO_EDGE <> SAMPLER_REPEAT /\
  SAMPLER_REPEAT <> SAMPLER_MIRROR_REPEAT.
Proof.
  unfold SAMPLER_CLAMP_TO_EDGE, SAMPLER_REPEAT, SAMPLER_MIRROR_REPEAT.
  lia.
Qed.
