Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink File System Name Validation Semantics *)
(** File System Access API §4: Name validation without separators or dot-dot *)

Definition is_valid_file_name (non_empty has_slash has_backslash is_dot is_dotdot : bool) : bool :=
  non_empty && negb (has_slash || has_backslash || is_dot || is_dotdot).

Theorem valid_file_name_sound : forall ne s bs d dd,
  is_valid_file_name ne s bs d dd = true ->
  ne = true /\ s = false /\ bs = false /\ d = false /\ dd = false.
Proof.
  intros ne s bs d dd H.
  unfold is_valid_file_name in H.
  apply andb_prop in H.
  destruct H as [Hne Hsafe].
  apply negb_true_iff in Hsafe.
  destruct s; destruct bs; destruct d; destruct dd; simpl in Hsafe; try discriminate; auto.
Qed.
