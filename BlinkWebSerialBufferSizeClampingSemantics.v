Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Web Serial Buffer Size Clamping Semantics *)
(** Web Serial API §3.2 bufferSize default 255 and clamped > 0 *)

Definition clamp_serial_buffer (opt : Z) : Z :=
  if opt <=? 0 then 255
  else if 16777216 <? opt then 16777216
  else opt.

Theorem clamp_serial_buffer_bounds : forall opt,
  1 <= clamp_serial_buffer opt <= 16777216.
Proof.
  intros opt.
  unfold clamp_serial_buffer.
  destruct (opt <=? 0) eqn:E0.
  - lia.
  - apply Z.leb_gt in E0.
    destruct (16777216 <? opt) eqn:E1.
    + lia.
    + apply Z.ltb_ge in E1.
      lia.
Qed.
