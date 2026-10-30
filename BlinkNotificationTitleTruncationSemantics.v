Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Notification Title Truncation Semantics *)
(** Notifications API §4.1: Title bounding within [0, 1024] *)

Definition clamp_title_len (len : Z) : Z :=
  if len <=? 0 then 0
  else if 1024 <? len then 1024
  else len.

Theorem clamp_title_bounds : forall len,
  0 <= clamp_title_len len <= 1024.
Proof.
  intros len.
  unfold clamp_title_len.
  destruct (len <=? 0) eqn:E0.
  - lia.
  - apply Z.leb_gt in E0.
    destruct (1024 <? len) eqn:E1.
    + lia.
    + apply Z.ltb_ge in E1.
      lia.
Qed.
