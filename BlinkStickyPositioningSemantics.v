(******************************************************************************)
(* BlinkStickyPositioningSemantics.v                                          *)
(* Sound Formal Specification for CSS Sticky Positioning Constraints         *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Positioned Layout Module Level 3 (§2.4 Sticky Positioning)      *)
(* 2. Blink StickyPositionScrollingConstraints & StickyConstraintsMap         *)
(*    (`sticky_position_scrolling_constraints.cc`)                            *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Open Scope Z_scope.

Record StickyConstraints1D := mkStickyConstraints1D {
  sc_static_position : Z;
  sc_min_offset : Z;
  sc_max_offset : Z
}.

Definition compute_sticky_offset_1d (sc : StickyConstraints1D) (scroll_offset : Z) : Z :=
  let raw := scroll_offset - sc_static_position sc in
  let mn := sc_min_offset sc in
  let mx := sc_max_offset sc in
  if mx <? mn then mn
  else Z.max mn (Z.min mx raw).

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Theorem sticky_offset_bounded :
  forall sc scroll_offset,
    sc_min_offset sc <= sc_max_offset sc ->
    sc_min_offset sc <= compute_sticky_offset_1d sc scroll_offset <= sc_max_offset sc.
Proof.
  intros sc scroll_offset Hle.
  unfold compute_sticky_offset_1d.
  destruct (sc_max_offset sc <? sc_min_offset sc) eqn:Elt.
  - apply Z.ltb_lt in Elt. lia.
  - split; [apply Z.le_max_l |].
    apply Z.max_lub_iff. split; [lia | apply Z.le_min_l].
Qed.

Theorem sticky_offset_deterministic :
  forall sc scroll_offset r1 r2,
    r1 = compute_sticky_offset_1d sc scroll_offset ->
    r2 = compute_sticky_offset_1d sc scroll_offset ->
    r1 = r2.
Proof.
  intros sc scroll_offset r1 r2 H1 H2. subst. reflexivity.
Qed.
