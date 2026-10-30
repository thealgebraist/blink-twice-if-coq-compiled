From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Box Sizing 3 §3 Border-Box Subtraction *)
Definition compute_content_size (border_box_size : Z) (padding_border : Z) : Z :=
  Z.max 0 (border_box_size - padding_border).

Theorem content_size_nonneg : forall bb pb,
  compute_content_size bb pb >= 0.
Proof.
  intros bb pb.
  unfold compute_content_size.
  apply Z.le_ge. apply Z.le_max_l.
Qed.

Theorem content_size_exact_when_fits : forall bb pb,
  bb >= pb ->
  pb >= 0 ->
  compute_content_size bb pb + pb = bb.
Proof.
  intros bb pb Hge Hpb.
  unfold compute_content_size.
  assert (bb - pb >= 0) by lia.
  destruct (Z.max_dec 0 (bb - pb)) as [H0 | Hsub]; lia.
Qed.
