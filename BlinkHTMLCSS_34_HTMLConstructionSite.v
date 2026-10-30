(* Blink2Coq HTML/CSS Synthesis for HTMLConstructionSite *)
(* Source: renderer/core/html/parser/html_construction_site.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition foster_parent_target_index (tbl_idx : Z) : Z := tbl_idx - 1.
Theorem foster_parent_precedes_table : forall tbl_idx,
  0 < tbl_idx -> foster_parent_target_index tbl_idx < tbl_idx.
Proof. intros. unfold foster_parent_target_index. lia. Qed.
