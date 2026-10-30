Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Unicode Bidi Levels Resolution Semantics *)
(** Unicode Standard Annex #9 / CSS Writing Modes 3 §3: UBA levels *)

Definition is_rtl_level (level : Z) : bool :=
  Z.odd level.

Definition is_valid_uba_level (level : Z) : bool :=
  (0 <=? level) && (level <=? 125).

Theorem uba_level_bounds : forall level,
  is_valid_uba_level level = true ->
  0 <= level <= 125.
Proof.
  intros level H.
  unfold is_valid_uba_level in H.
  apply andb_prop in H.
  destruct H as [H0 H125].
  apply Z.leb_le in H0.
  apply Z.leb_le in H125.
  split; assumption.
Qed.
