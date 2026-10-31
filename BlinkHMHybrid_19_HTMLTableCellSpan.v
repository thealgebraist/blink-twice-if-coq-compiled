(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record HTMLTableCellSpan := mkHTMLTableCellSpan {
  htmltablecellspan_colspan : Z;
  htmltablecellspan_rowspan : Z
}.

Definition sanitize_cell_span (raw : Z) (max_cap : Z) : Z :=
  if raw <=? 1 then 1 else if max_cap <? raw then max_cap else raw.

Theorem sanitize_cell_span_in_whatwg_range :
  forall (raw max_cap : Z), 1 <= max_cap -> 1 <= sanitize_cell_span raw max_cap <= max_cap.
Proof.
  intros raw max_cap Hcap.
  unfold sanitize_cell_span.
  destruct (raw <=? 1) eqn:E1; [apply Z.leb_le in E1; lia |].
  apply Z.leb_gt in E1.
  destruct (max_cap <? raw) eqn:E2; [apply Z.ltb_lt in E2; lia |].
  apply Z.ltb_ge in E2. lia.
Qed.
