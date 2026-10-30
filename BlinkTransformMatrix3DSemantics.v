From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Record Vector3D := mkV3 { v_x : Z; v_y : Z; v_z : Z }.
Record Transform3D := mkT3D { t_scale : Vector3D; t_trans : Vector3D }.

Definition identity_3d : Transform3D :=
  {| t_scale := {| v_x := 1; v_y := 1; v_z := 1 |};
     t_trans := {| v_x := 0; v_y := 0; v_z := 0 |} |}.

Definition compose_3d (t1 t2 : Transform3D) : Transform3D :=
  {| t_scale := {| v_x := v_x (t_scale t1) * v_x (t_scale t2);
                   v_y := v_y (t_scale t1) * v_y (t_scale t2);
                   v_z := v_z (t_scale t1) * v_z (t_scale t2) |};
     t_trans := {| v_x := v_x (t_scale t1) * v_x (t_trans t2) + v_x (t_trans t1);
                   v_y := v_y (t_scale t1) * v_y (t_trans t2) + v_y (t_trans t1);
                   v_z := v_z (t_scale t1) * v_z (t_trans t2) + v_z (t_trans t1) |} |}.

Theorem compose_3d_id_left : forall t,
  compose_3d identity_3d t = t.
Proof.
  intros [[sx sy sz] [tx ty tz]].
  unfold compose_3d, identity_3d.
  f_equal; f_equal; cbv [v_x v_y v_z t_scale t_trans]; ring.
Qed.

Theorem compose_3d_id_right : forall t,
  compose_3d t identity_3d = t.
Proof.
  intros [[sx sy sz] [tx ty tz]].
  unfold compose_3d, identity_3d.
  f_equal; f_equal; cbv [v_x v_y v_z t_scale t_trans]; ring.
Qed.

Theorem compose_3d_associative : forall t1 t2 t3,
  compose_3d (compose_3d t1 t2) t3 = compose_3d t1 (compose_3d t2 t3).
Proof.
  intros [[sx1 sy1 sz1] [tx1 ty1 tz1]]
         [[sx2 sy2 sz2] [tx2 ty2 tz2]]
         [[sx3 sy3 sz3] [tx3 ty3 tz3]].
  unfold compose_3d.
  f_equal; f_equal; cbv [v_x v_y v_z t_scale t_trans]; ring.
Qed.
