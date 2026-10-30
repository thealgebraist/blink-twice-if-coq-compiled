Require Import Bool.

(** * Blink MediaStreamTrack Active State Semantics *)
(** Media Capture and Streams §4.3.1: track active iff enabled, unmuted, and live *)

Definition is_track_active (enabled muted is_live : bool) : bool :=
  enabled && negb muted && is_live.

Theorem track_active_requires_all_three : forall e m l,
  is_track_active e m l = true ->
  e = true /\ m = false /\ l = true.
Proof.
  intros e m l H.
  unfold is_track_active in H.
  repeat (apply andb_prop in H; destruct H as [H ?]).
  destruct m; try discriminate.
  split; [exact H | split; reflexivity || exact H0].
Qed.
