Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Font Optical Sizing Derivation Semantics *)
(** CSS Fonts 4 §6.12: auto opsz axis derivation *)

Definition derive_optical_size (font_size_pt : Z) : Z :=
  Z.max 0 font_size_pt.

Theorem optical_size_nonneg : forall pt,
  0 <= derive_optical_size pt.
Proof.
  intros pt.
  unfold derive_optical_size; lia.
Qed.
