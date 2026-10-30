From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS 2.1 §10.5 Indefinite Percentage Height Resolution *)
Definition resolve_percent_height_with_indefinite (cb_height : option Z) (pct : Z) (content_h : Z) : Z :=
  match cb_height with
  | Some h => (h * pct) / 100
  | None => content_h
  end.

Theorem indefinite_resolves_to_content : forall pct content_h,
  resolve_percent_height_with_indefinite None pct content_h = content_h.
Proof.
  intros. unfold resolve_percent_height_with_indefinite. reflexivity.
Qed.

Theorem definite_nonneg : forall h pct content_h,
  h >= 0 ->
  pct >= 0 ->
  resolve_percent_height_with_indefinite (Some h) pct content_h >= 0.
Proof.
  intros h pct content_h Hh Hpct.
  unfold resolve_percent_height_with_indefinite.
  assert (0 <= (h * pct) / 100).
  { apply Z.div_le_lower_bound; lia. }
  lia.
Qed.
