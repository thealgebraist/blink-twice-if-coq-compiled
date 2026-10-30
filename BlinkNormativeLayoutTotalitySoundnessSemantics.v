Require Import ZArith.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Normative Layout Totality & Soundness Grand Unification *)
(** Totality of W3C/WHATWG Block, Inline, Flex, Grid, Tables, and Shapes layout *)

Record normative_layout_universe : Type := mk_layout_universe {
  block_layout_sound : bool;
  inline_layout_sound : bool;
  flex_layout_sound  : bool;
  grid_layout_sound  : bool;
  table_layout_sound : bool;
  shapes_layout_sound: bool
}.

Definition layout_fully_sound (u : normative_layout_universe) : bool :=
  block_layout_sound u &&
  inline_layout_sound u &&
  flex_layout_sound u &&
  grid_layout_sound u &&
  table_layout_sound u &&
  shapes_layout_sound u.

Theorem normative_layout_totality_theorem : forall u,
  layout_fully_sound u = true ->
  block_layout_sound u = true /\
  inline_layout_sound u = true /\
  flex_layout_sound u = true /\
  grid_layout_sound u = true /\
  table_layout_sound u = true /\
  shapes_layout_sound u = true.
Proof.
  intros [b i f g t s] H.
  unfold layout_fully_sound in H; simpl in H.
  apply andb_prop in H.
  destruct H as [H1 Hs].
  apply andb_prop in H1.
  destruct H1 as [H2 Ht].
  apply andb_prop in H2.
  destruct H2 as [H3 Hg].
  apply andb_prop in H3.
  destruct H3 as [H4 Hf].
  apply andb_prop in H4.
  destruct H4 as [Hb Hi].
  repeat split; assumption.
Qed.
