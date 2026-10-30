Require Import Bool.

(** * Blink WebGPU Shader Compilation Status Semantics *)
(** WebGPU §12.1: shader module valid iff no compilation errors *)

Definition is_shader_module_valid (has_errors : bool) : bool :=
  negb has_errors.

Theorem shader_valid_iff_no_errors : forall err,
  is_shader_module_valid err = true <-> err = false.
Proof.
  intros err.
  unfold is_shader_module_valid.
  destruct err; split; auto; discriminate.
Qed.
