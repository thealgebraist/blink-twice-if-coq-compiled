(******************************************************************************)
(* BlinkCSSContainmentSemantics.v                                             *)
(* Sound Formal Big-Step Operational Semantics for CSS Containment            *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Containment Module Level 2 (§2 Containment Types)               *)
(* 2. Blink LayoutBox (`layout_box.cc`), ShouldApplySizeContainment, &        *)
(*    ShouldApplyInlineSizeContainment                                        *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Open Scope Z_scope.

Record ContainmentFlags := mkContainmentFlags {
  cf_size : bool;
  cf_inline_size : bool;
  cf_layout : bool;
  cf_paint : bool
}.

Definition default_containment : ContainmentFlags :=
  mkContainmentFlags false false false false.

(** Under size containment, intrinsic sizing treats box as having no contents *)
Definition resolve_contained_intrinsic_size (flags : ContainmentFlags)
                                           (normal_intrinsic_w normal_intrinsic_h : Z) : (Z * Z) :=
  let w := if cf_size flags || cf_inline_size flags then 0 else normal_intrinsic_w in
  let h := if cf_size flags then 0 else normal_intrinsic_h in
  (sat_clamp w, sat_clamp h).

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Theorem size_containment_zeroes_intrinsic :
  forall flags nw nh,
    cf_size flags = true ->
    resolve_contained_intrinsic_size flags nw nh = (0, 0).
Proof.
  intros flags nw nh Hsize.
  unfold resolve_contained_intrinsic_size.
  rewrite Hsize. simpl. reflexivity.
Qed.

Theorem inline_size_containment_zeroes_width :
  forall flags nw nh,
    cf_inline_size flags = true ->
    fst (resolve_contained_intrinsic_size flags nw nh) = 0.
Proof.
  intros flags nw nh Hinline.
  unfold resolve_contained_intrinsic_size.
  rewrite Hinline.
  destruct (cf_size flags); simpl; reflexivity.
Qed.

Theorem contained_intrinsic_deterministic :
  forall flags nw nh r1 r2,
    r1 = resolve_contained_intrinsic_size flags nw nh ->
    r2 = resolve_contained_intrinsic_size flags nw nh ->
    r1 = r2.
Proof.
  intros flags nw nh r1 r2 H1 H2. subst. reflexivity.
Qed.
