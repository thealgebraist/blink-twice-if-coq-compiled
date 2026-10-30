From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Font Loading 3 §3 Font Loading Lifecycle State Machine *)
Inductive FontLoadState :=
  | FontUnloaded
  | FontLoading
  | FontLoaded
  | FontError.

Definition is_font_terminal (s : FontLoadState) : bool :=
  match s with
  | FontLoaded => true
  | FontError  => true
  | _          => false
  end.

Theorem terminal_states_are_stable : forall s,
  is_font_terminal s = true <-> s = FontLoaded \/ s = FontError.
Proof.
  intros s; unfold is_font_terminal.
  destruct s; split; intros H; try discriminate; try (destruct H as [H1 | H2]; discriminate); auto.
Qed.
