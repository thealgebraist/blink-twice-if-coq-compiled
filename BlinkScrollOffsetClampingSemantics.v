Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Scroll Offset Clamping Semantics *)
(** CSSOM View §4: scroll offset clamped within [0, max_scroll_offset] *)

Definition clamp_scroll_offset (offset max_scroll : Z) : Z :=
  Z.max 0 (Z.min max_scroll offset).

Theorem scroll_offset_clamped_bounds : forall o m,
  0 <= m ->
  0 <= clamp_scroll_offset o m <= m.
Proof.
  intros o m Hm.
  unfold clamp_scroll_offset; lia.
Qed.

Theorem scroll_offset_clamped_idempotent : forall o m,
  clamp_scroll_offset (clamp_scroll_offset o m) m = clamp_scroll_offset o m.
Proof.
  intros o m.
  unfold clamp_scroll_offset; lia.
Qed.
