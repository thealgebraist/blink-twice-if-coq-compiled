Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink WebGPU Vertex Stride Alignment Semantics *)
(** WebGPU §10.3: vertex stride 4-byte aligned and bounded by 2048 *)

Definition is_valid_vertex_stride (stride : Z) : bool :=
  (stride mod 4 =? 0) && (0 <=? stride) && (stride <=? 2048).

Theorem stride_32_is_valid :
  is_valid_vertex_stride 32 = true.
Proof.
  reflexivity.
Qed.

Theorem unaligned_stride_is_invalid :
  is_valid_vertex_stride 33 = false.
Proof.
  reflexivity.
Qed.
