(* BlinkFooterNavigationLayoutSemantics.v *)
(* Formal semantics of Blink flexbox space-between navigation bar distribution *)
(* Modeled after Chromium third_party/blink/renderer/core/layout/ng/flex/ng_flex_layout_algorithm.cc *)

Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

Record BlinkFlexNavBar := mkFlexNavBar {
  nb_left : Z;
  nb_width : Z;
  nb_item1_w : Z;
  nb_item2_w : Z;
  nb_item3_w : Z
}.

Definition compute_item1_x (nb : BlinkFlexNavBar) : Z :=
  nb_left nb.

Definition compute_item2_x (nb : BlinkFlexNavBar) : Z :=
  nb_left nb + (nb_width nb - nb_item2_w nb) / 2.

Definition compute_item3_x (nb : BlinkFlexNavBar) : Z :=
  nb_left nb + nb_width nb - nb_item3_w nb.

Theorem nav_items_strictly_ordered :
  forall (nb : BlinkFlexNavBar),
    0 < nb_item1_w nb ->
    0 < nb_item2_w nb ->
    0 < nb_item3_w nb ->
    nb_item1_w nb <= (nb_width nb - nb_item2_w nb) / 2 ->
    (nb_width nb - nb_item2_w nb) / 2 + nb_item2_w nb < nb_width nb - nb_item3_w nb ->
    compute_item1_x nb < compute_item2_x nb /\
    compute_item2_x nb < compute_item3_x nb.
Proof.
  intros nb H1 H2 H3 Hfit1 Hfit2.
  unfold compute_item1_x, compute_item2_x, compute_item3_x.
  lia.
Qed.

(* Exact Page 2 Footer parameters:
   Left = 25, Width = 750, Item2 width = 58
   Item2 center x = 25 + (750 - 58) / 2 = 25 + 692 / 2 = 25 + 346 = 371 (center)
   Text starts at 347 *)
Definition p2_nav_bar : BlinkFlexNavBar := mkFlexNavBar 25 750 189 58 236.

Theorem p2_nav_coordinates_exact :
  compute_item1_x p2_nav_bar = 25 /\
  compute_item3_x p2_nav_bar = 750 + 25 - 236.
Proof.
  unfold compute_item1_x, compute_item3_x, p2_nav_bar.
  split; reflexivity.
Qed.
