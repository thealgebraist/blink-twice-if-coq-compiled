Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink WebAuthn Timeout Clamping Semantics *)
(** WebAuthn Level 3 §5.1.3: timeout clamped within [1000, 600000] ms *)

Definition clamp_webauthn_timeout (t : Z) : Z :=
  Z.min 600000 (Z.max 1000 t).

Theorem timeout_clamped_in_bounds : forall t,
  1000 <= clamp_webauthn_timeout t <= 600000.
Proof.
  intros t.
  unfold clamp_webauthn_timeout.
  split.
  - apply Z.min_glb_iff. split; [lia | apply Z.le_max_l].
  - apply Z.le_min_l.
Qed.
