From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS 2.1 §17.5.2.1 Fixed Table Layout Semantics *)
Record TableFixedColumn := {
  tfc_declared_width : option Z;
  tfc_min_width : Z
}.

Definition resolve_fixed_col_width (col : TableFixedColumn) (default_w : Z) : Z :=
  match tfc_declared_width col with
  | Some w => Z.max w (tfc_min_width col)
  | None => Z.max default_w (tfc_min_width col)
  end.

Theorem resolve_fixed_col_width_ge_min : forall col def_w,
  resolve_fixed_col_width col def_w >= tfc_min_width col.
Proof.
  intros [decl min_w] def_w; cbn.
  destruct decl as [w |]; apply Z.le_ge; apply Z.le_max_r.
Qed.

Theorem resolve_fixed_col_width_some : forall decl min_w def_w,
  decl >= min_w ->
  resolve_fixed_col_width {| tfc_declared_width := Some decl; tfc_min_width := min_w |} def_w = decl.
Proof.
  intros decl min_w def_w Hge.
  cbn. lia.
Qed.
