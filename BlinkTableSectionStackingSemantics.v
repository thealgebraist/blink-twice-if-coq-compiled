(* ========================================================================= *)
(*               BlinkTableSectionStackingSemantics.v                        *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Table Section Stacking (thead, tbody,  *)
(* tfoot) per HTML Living Standard §4.9.5-4.9.7 & CSS 2.1 §17.5.            *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

Inductive TableSectionKind : Type :=
  | SectionThead
  | SectionTbody
  | SectionTfoot.

Definition section_rank (kind : TableSectionKind) : Z :=
  match kind with
  | SectionThead => 0
  | SectionTbody => 1
  | SectionTfoot => 2
  end.

Theorem section_ordering_monotonic :
  section_rank SectionThead < section_rank SectionTbody /\
  section_rank SectionTbody < section_rank SectionTfoot.
Proof.
  unfold section_rank; split; lia.
Qed.

Fixpoint compute_section_offsets (heights : list Z) (cursor : Z) (spacing : Z) : list Z :=
  match heights with
  | nil => nil
  | h :: rest => cursor :: compute_section_offsets rest (cursor + Z.max 0 h + spacing) spacing
  end.

Lemma compute_section_offsets_length : forall heights cursor spacing,
  length (compute_section_offsets heights cursor spacing) = length heights.
Proof.
  induction heights; intros cursor spacing; simpl; [reflexivity |].
  rewrite (IHheights (cursor + Z.max 0 a + spacing) spacing).
  reflexivity.
Qed.

Lemma compute_section_offsets_in_ge : forall heights cursor spacing next,
  spacing >= 0 ->
  In next (compute_section_offsets heights cursor spacing) ->
  cursor <= next.
Proof.
  induction heights as [| a heights' IH]; intros cursor spacing next Hsp Hin; simpl in Hin; [contradiction |].
  destruct Hin as [Heq | Hin].
  - subst next; lia.
  - specialize (IH (cursor + Z.max 0 a + spacing) spacing next Hsp Hin).
    pose proof (Z.le_max_l 0 a).
    lia.
Qed.

Theorem section_offsets_monotonic : forall h heights cursor spacing next,
  h > 0 ->
  spacing >= 0 ->
  In next (compute_section_offsets heights (cursor + h + spacing) spacing) ->
  cursor < next.
Proof.
  intros h heights cursor spacing next Hh Hsp Hin.
  pose proof (compute_section_offsets_in_ge heights (cursor + h + spacing) spacing next Hsp Hin).
  lia.
Qed.
