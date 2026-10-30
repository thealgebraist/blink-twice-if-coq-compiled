(* Blink2Coq HTML/CSS Synthesis for IntersectionObserver *)
(* Source: renderer/core/intersection_observer/intersection_observer.cc *)

From Stdlib Require Import ZArith Lia. Open Scope Z_scope.
Definition intersection_ratio_pct (ai at_area : Z) : Z :=
  if at_area <=? 0 then 0 else (ai * 100) / at_area.
Theorem intersection_ratio_bounded : forall ai at_area,
  0 <= ai <= at_area -> 0 < at_area ->
  0 <= intersection_ratio_pct ai at_area <= 100.
Proof.
  intros ai at_area [H1 H2] Hpos. unfold intersection_ratio_pct.
  assert (E: (at_area <=? 0) = false) by (apply Z.leb_gt; lia).
  rewrite E.
  split.
  - apply Z.div_pos; lia.
  - apply Z.div_le_upper_bound; [lia |].
    assert (ai * 100 <= at_area * 100) by lia.
    exact H.
Qed.
