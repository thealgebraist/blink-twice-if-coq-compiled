Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Scroll Offset Clamping Semantics *)
(** CSSOM View §4: scroll offset bounds *)

Definition clamp_scroll_offset (offset scroll_size client_size : Z) : Z :=
  let max_offset := Z.max 0 (scroll_size - client_size) in
  Z.max 0 (Z.min max_offset offset).

Theorem scroll_offset_bounded : forall offset scroll_size client_size,
  0 <= clamp_scroll_offset offset scroll_size client_size <= Z.max 0 (scroll_size - client_size).
Proof.
  intros offset scroll_size client_size.
  unfold clamp_scroll_offset.
  lia.
Qed.
