Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebGPU Depth/Stencil Format Semantics *)
(** WebGPU §10.2: format aspect capability determination *)

Definition FORMAT_DEPTH24_STENCIL8 : Z := 1.
Definition FORMAT_DEPTH32_FLOAT    : Z := 2.
Definition FORMAT_STENCIL8         : Z := 3.

Definition format_has_depth (f : Z) : bool :=
  (f =? FORMAT_DEPTH24_STENCIL8) || (f =? FORMAT_DEPTH32_FLOAT).

Definition format_has_stencil (f : Z) : bool :=
  (f =? FORMAT_DEPTH24_STENCIL8) || (f =? FORMAT_STENCIL8).

Theorem depth24_stencil8_has_both :
  format_has_depth FORMAT_DEPTH24_STENCIL8 = true /\
  format_has_stencil FORMAT_DEPTH24_STENCIL8 = true.
Proof.
  split; reflexivity.
Qed.
