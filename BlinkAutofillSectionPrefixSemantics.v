Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Autofill Section Prefix Scoping Semantics *)
(** HTML Spec §4.10.18.7: section-* prefix scoping *)

Inductive section_scope : Type :=
| DefaultSection
| CustomSection (id : Z).

Definition parse_section (has_prefix : bool) (sec_id : Z) : section_scope :=
  if has_prefix then CustomSection sec_id else DefaultSection.

Theorem section_prefix_isolation : forall id,
  parse_section true id <> DefaultSection.
Proof.
  intros id H.
  unfold parse_section in H.
  discriminate.
Qed.
