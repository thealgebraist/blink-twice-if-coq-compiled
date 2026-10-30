Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebSocket Frame Masking XOR Symmetry Semantics *)
(** RFC 6455 §5.3: XOR masking involution unmask(mask(p, k), k) = p *)

Definition websocket_mask_byte (payload_byte key_byte : Z) : Z :=
  Z.lxor payload_byte key_byte.

Theorem websocket_masking_involutive : forall p k,
  websocket_mask_byte (websocket_mask_byte p k) k = p.
Proof.
  intros p k.
  unfold websocket_mask_byte.
  rewrite Z.lxor_assoc.
  rewrite Z.lxor_nilpotent.
  rewrite Z.lxor_0_r.
  reflexivity.
Qed.
