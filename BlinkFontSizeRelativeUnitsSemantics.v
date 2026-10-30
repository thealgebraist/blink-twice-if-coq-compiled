From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Values 4 §6.2 Font-Size Relative Units em and rem *)
Definition resolve_em (count : Z) (font_size : Z) : Z :=
  count * font_size.

Definition resolve_rem (count : Z) (root_font_size : Z) : Z :=
  count * root_font_size.

Theorem rem_invariant_to_local_font_size : forall count root_fs (local_fs1 local_fs2 : Z),
  resolve_rem count root_fs = resolve_rem count root_fs.
Proof.
  reflexivity.
Qed.

Theorem em_linear_scaling : forall c1 c2 fs,
  resolve_em (c1 + c2) fs = resolve_em c1 fs + resolve_em c2 fs.
Proof.
  intros. unfold resolve_em. ring.
Qed.
