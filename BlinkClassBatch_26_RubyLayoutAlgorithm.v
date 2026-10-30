(* Blink2Coq Synthesis for RubyLayoutAlgorithm *)
(* Source: third_party/blink/renderer/core/layout/inline/ruby_layout_algorithm.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition ruby_centering_offset (col_w text_w : Z) : Z := (col_w - text_w) / 2.
Theorem ruby_offset_nonneg : forall cw tw,
  tw <= cw -> 0 <= ruby_centering_offset cw tw.
Proof. intros. unfold ruby_centering_offset. apply Z.div_pos; lia. Qed.
