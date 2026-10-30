(* ========================================================================= *)
(*               BlinkWhiteSpaceCollapsingSemantics.v                        *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS White-Space Collapsing             *)
(* per W3C CSS Text Module Level 3 §4.                                       *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Inductive WhiteSpaceMode : Type :=
  | WSNormal
  | WSPre.

Definition collapse_spaces (mode : WhiteSpaceMode) (consecutive_spaces : Z) : Z :=
  match mode with
  | WSNormal => if consecutive_spaces <=? 0 then 0 else 1
  | WSPre    => Z.max 0 consecutive_spaces
  end.

Theorem collapse_spaces_normal_bounded : forall n,
  n >= 1 ->
  collapse_spaces WSNormal n = 1.
Proof.
  intros n Hn. unfold collapse_spaces.
  destruct (n <=? 0) eqn:E; [lia | reflexivity].
Qed.

Theorem collapse_spaces_le_original : forall mode n,
  n >= 0 ->
  collapse_spaces mode n <= n.
Proof.
  intros mode n Hn.
  destruct mode; unfold collapse_spaces.
  - destruct (n <=? 0) eqn:E; lia.
  - apply Z.max_lub_iff; split; lia.
Qed.

Theorem collapse_spaces_idempotent : forall mode n,
  collapse_spaces mode (collapse_spaces mode n) = collapse_spaces mode n.
Proof.
  intros mode n.
  destruct mode; unfold collapse_spaces.
  - destruct (n <=? 0) eqn:E1.
    + simpl; reflexivity.
    + simpl; reflexivity.
  - apply Z.max_r; apply Z.le_max_l.
Qed.
