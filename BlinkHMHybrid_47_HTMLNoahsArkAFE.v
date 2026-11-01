(* Formalization generated via HM Hybrid Architecture *)
(* De-imperativized SSA AST + Robinson MGU Row Typing + WP Assertion Mining + Dale Miller Presburger LIA *)
Require Import ZArith.
Require Import Bool.
Require Import Lia.
Open Scope Z_scope.

Record HTMLNoahsArkAFE := mkHTMLNoahsArkAFE {
  htmlnoahsarkafe_matching_sig_count : Z
}.

Definition noahs_ark_next_count (dup_cnt : Z) : Z :=
  (if 3 <=? dup_cnt then 2 else dup_cnt) + 1.

Theorem noahs_ark_next_count_capped_at_3 :
  forall (dup_cnt : Z), 0 <= dup_cnt <= 3 -> 1 <= noahs_ark_next_count dup_cnt <= 3.
Proof.
  intros dup_cnt H. unfold noahs_ark_next_count.
  destruct (3 <=? dup_cnt) eqn:E3.
  - lia.
  - apply Z.leb_gt in E3. lia.
Qed.
