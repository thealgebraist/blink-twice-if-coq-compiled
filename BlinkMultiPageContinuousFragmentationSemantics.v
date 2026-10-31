(* BlinkMultiPageContinuousFragmentationSemantics.v *)
(* Formal semantics of Blink Continuous Multi-Page Layout Fragmentation *)
(* Modeled after Chromium third_party/blink/renderer/core/layout/ng/ng_fragmentation_algorithm.cc *)

Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Definition viewport_height : Z := 600.
Definition full_article_height : Z := 1800.

Definition continuous_to_page_index (y : Z) : Z :=
  y / viewport_height.

Definition continuous_to_page_local_y (y : Z) : Z :=
  y mod viewport_height.

Definition page_local_to_continuous (page_idx local_y : Z) : Z :=
  page_idx * viewport_height + local_y.

Theorem multi_page_fragmentation_exact_invertibility :
  forall (y : Z),
    0 <= y < full_article_height ->
    page_local_to_continuous (continuous_to_page_index y) (continuous_to_page_local_y y) = y.
Proof.
  intros y Hy.
  unfold page_local_to_continuous, continuous_to_page_index, continuous_to_page_local_y.
  rewrite Z.mul_comm.
  symmetry.
  apply Z.div_mod.
  unfold viewport_height.
  lia.
Qed.

Theorem multi_page_three_page_partition :
  forall (y : Z),
    0 <= y < full_article_height ->
    (0 <= y < 600 /\ continuous_to_page_index y = 0) \/
    (600 <= y < 1200 /\ continuous_to_page_index y = 1) \/
    (1200 <= y < 1800 /\ continuous_to_page_index y = 2).
Proof.
  intros y Hy.
  unfold continuous_to_page_index, viewport_height, full_article_height in *.
  destruct (y <? 600) eqn:Ey1.
  - apply Z.ltb_lt in Ey1.
    left. split; [lia |].
    symmetry. apply Z.div_unique with (r := y); lia.
  - apply Z.ltb_ge in Ey1.
    destruct (y <? 1200) eqn:Ey2.
    + apply Z.ltb_lt in Ey2.
      right; left. split; [lia |].
      symmetry. apply Z.div_unique with (r := y - 600); lia.
    + apply Z.ltb_ge in Ey2.
      right; right. split; [lia |].
      symmetry. apply Z.div_unique with (r := y - 1200); lia.
Qed.

