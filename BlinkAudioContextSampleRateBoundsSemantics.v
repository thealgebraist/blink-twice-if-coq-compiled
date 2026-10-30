Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink AudioContext Sample Rate Validity Bounds Semantics *)
(** Web Audio API §1.2: sampleRate in [22050, 96000] Hz *)

Definition is_valid_sample_rate (sr : Z) : bool :=
  (22050 <=? sr) && (sr <=? 96000).

Theorem standard_44100_valid :
  is_valid_sample_rate 44100 = true.
Proof.
  reflexivity.
Qed.

Theorem standard_48000_valid :
  is_valid_sample_rate 48000 = true.
Proof.
  reflexivity.
Qed.

Theorem low_sample_rate_invalid :
  is_valid_sample_rate 8000 = false.
Proof.
  reflexivity.
Qed.
