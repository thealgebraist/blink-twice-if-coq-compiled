(* ========================================================================= *)
(*               BlinkLayoutContainmentSemantics.v                           *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink CSS Size & Layout Containment per      *)
(* W3C CSS Containment Module Level 2 §2 & §3.                               *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Record BoxIntrinsicSizes := {
  min_content : Z;
  max_content : Z
}.

Definition valid_intrinsic_sizes (s : BoxIntrinsicSizes) : Prop :=
  0 <= min_content s /\ min_content s <= max_content s.

Definition resolve_intrinsic_sizes (contain_size : bool) (content_sizes : BoxIntrinsicSizes) : BoxIntrinsicSizes :=
  if contain_size then
    {| min_content := 0; max_content := 0 |}
  else
    content_sizes.

Definition resolve_child_margin_leakage (contain_layout : bool) (child_margin : Z) : Z :=
  if contain_layout then 0
  else child_margin.

Theorem size_containment_isolation : forall c1 c2,
  resolve_intrinsic_sizes true c1 = resolve_intrinsic_sizes true c2.
Proof.
  intros c1 c2.
  unfold resolve_intrinsic_sizes.
  reflexivity.
Qed.

Theorem size_containment_valid : forall c,
  valid_intrinsic_sizes (resolve_intrinsic_sizes true c).
Proof.
  intros c.
  unfold valid_intrinsic_sizes, resolve_intrinsic_sizes; cbn.
  lia.
Qed.

Theorem no_size_containment_preserves_validity : forall c,
  valid_intrinsic_sizes c ->
  valid_intrinsic_sizes (resolve_intrinsic_sizes false c).
Proof.
  intros c Hval.
  unfold resolve_intrinsic_sizes.
  exact Hval.
Qed.

Theorem layout_containment_suppresses_margin_leakage : forall m,
  resolve_child_margin_leakage true m = 0.
Proof.
  intros m.
  unfold resolve_child_margin_leakage.
  reflexivity.
Qed.

Theorem no_layout_containment_preserves_margin : forall m,
  resolve_child_margin_leakage false m = m.
Proof.
  intros m.
  unfold resolve_child_margin_leakage.
  reflexivity.
Qed.

Theorem size_containment_idempotent : forall contain_size c,
  resolve_intrinsic_sizes contain_size (resolve_intrinsic_sizes contain_size c) =
  resolve_intrinsic_sizes contain_size c.
Proof.
  intros contain_size c.
  unfold resolve_intrinsic_sizes.
  destruct contain_size; reflexivity.
Qed.

