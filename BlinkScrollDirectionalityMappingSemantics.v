Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Scroll Directionality Mapping Semantics *)
(** CSS Writing Modes 4 §6: coordinate mapping across modes *)

Inductive WritingDirection :=
  | DirectionHorizontalTB
  | DirectionVerticalRL.

Definition map_scroll_x (dir : WritingDirection) (offset max_scroll : Z) : Z :=
  match dir with
  | DirectionHorizontalTB => offset
  | DirectionVerticalRL => max_scroll - offset
  end.

Theorem horizontal_mapping_identity : forall offset max_scroll,
  map_scroll_x DirectionHorizontalTB offset max_scroll = offset.
Proof.
  intros offset max_scroll.
  reflexivity.
Qed.

Theorem vertical_rl_mapping_inversion : forall offset max_scroll,
  map_scroll_x DirectionVerticalRL (map_scroll_x DirectionVerticalRL offset max_scroll) max_scroll = offset.
Proof.
  intros offset max_scroll.
  unfold map_scroll_x.
  lia.
Qed.
