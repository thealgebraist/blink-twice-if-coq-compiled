Require Import Bool.

(** * Blink Cross-Origin-Opener-Policy (COOP) Semantics *)
(** HTML Standard §7.4: COOP same-origin forces browsing context group switch if opener cross-origin *)

Record COOPContext := {
  target_coop_same_origin : bool;
  opener_is_same_origin   : bool
}.

Definition coop_requires_group_switch (ctx : COOPContext) : bool :=
  target_coop_same_origin ctx && negb (opener_is_same_origin ctx).

Theorem coop_switches_for_cross_origin_opener :
  coop_requires_group_switch {| target_coop_same_origin := true;
                                opener_is_same_origin := false |} = true.
Proof.
  reflexivity.
Qed.

Theorem coop_preserves_group_for_same_origin_opener :
  coop_requires_group_switch {| target_coop_same_origin := true;
                                opener_is_same_origin := true |} = false.
Proof.
  reflexivity.
Qed.
