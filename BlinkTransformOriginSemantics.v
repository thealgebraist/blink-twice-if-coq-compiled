(******************************************************************************)
(* BlinkTransformOriginSemantics.v                                            *)
(* Sound Formal Specification for CSS 2D Affine Transforms & Transform Origin*)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Transforms Module Level 1 (§2 2D Matrix, §5 Transform Origin)    *)
(* 2. Blink TransformState (`transform_state.cc`) & TransformationMatrix       *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Open Scope Z_scope.

Record Matrix2D := mkMatrix2D {
  m_a : Z; (* scale x *)
  m_b : Z; (* skew y *)
  m_c : Z; (* skew x *)
  m_d : Z; (* scale y *)
  m_e : Z; (* translate x *)
  m_f : Z  (* translate y *)
}.

Definition identity_matrix2d : Matrix2D :=
  mkMatrix2D 1 0 0 1 0 0.

Definition apply_point2d (m : Matrix2D) (x y : Z) : (Z * Z) :=
  let px := sat_clamp (m_a m * x + m_c m * y + m_e m) in
  let py := sat_clamp (m_b m * x + m_d m * y + m_f m) in
  (px, py).

Definition apply_transform_with_origin (m : Matrix2D) (ox oy : Z) (x y : Z) : (Z * Z) :=
  let (tx, ty) := apply_point2d m (x - ox) (y - oy) in
  (sat_clamp (tx + ox), sat_clamp (ty + oy)).

(******************************************************************************)
(* SOUNDNESS THEOREMS (0 admits)                                              *)
(******************************************************************************)

Lemma sat_clamp_id : forall x : Z,
  kInt32Min <= x <= kInt32Max -> sat_clamp x = x.
Proof.
  intros x [H1 H2]. unfold sat_clamp, kInt32Min, kInt32Max in *.
  destruct (Z.gtb_spec x 2147483647); [lia |].
  destruct (Z.ltb_spec x (-2147483648)); [lia | reflexivity].
Qed.

Theorem identity_transform_is_neutral :
  forall (x y : Z),
    kInt32Min <= x <= kInt32Max ->
    kInt32Min <= y <= kInt32Max ->
    apply_point2d identity_matrix2d x y = (x, y).
Proof.
  intros x y Hx Hy.
  unfold apply_point2d.
  change (m_a identity_matrix2d) with 1.
  change (m_c identity_matrix2d) with 0.
  change (m_e identity_matrix2d) with 0.
  change (m_b identity_matrix2d) with 0.
  change (m_d identity_matrix2d) with 1.
  change (m_f identity_matrix2d) with 0.
  assert (H1 : 1 * x + 0 * y + 0 = x) by lia.
  assert (H2 : 0 * x + 1 * y + 0 = y) by lia.
  rewrite H1, H2.
  rewrite sat_clamp_id by exact Hx.
  rewrite sat_clamp_id by exact Hy.
  reflexivity.
Qed.

Theorem transform_deterministic :
  forall m ox oy x y r1 r2,
    r1 = apply_transform_with_origin m ox oy x y ->
    r2 = apply_transform_with_origin m ox oy x y ->
    r1 = r2.
Proof.
  intros m ox oy x y r1 r2 H1 H2. subst. reflexivity.
Qed.
