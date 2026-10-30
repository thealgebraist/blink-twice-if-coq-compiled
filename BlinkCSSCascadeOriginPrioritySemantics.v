Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink Cascade Origin Priority Ordering Semantics *)
(** CSS Cascading 4 §3: UA < User < Author < Author!important < User!important < UA!important *)

Inductive CascadeOrigin :=
  | OriginUA
  | OriginUser
  | OriginAuthor
  | OriginAuthorImportant
  | OriginUserImportant
  | OriginUAImportant.

Definition origin_rank (o : CascadeOrigin) : Z :=
  match o with
  | OriginUA => 1
  | OriginUser => 2
  | OriginAuthor => 3
  | OriginAuthorImportant => 4
  | OriginUserImportant => 5
  | OriginUAImportant => 6
  end.

Theorem author_overrides_user_normal :
  origin_rank OriginUser < origin_rank OriginAuthor.
Proof.
  unfold origin_rank; lia.
Qed.

Theorem important_overrides_normal :
  origin_rank OriginAuthor < origin_rank OriginAuthorImportant.
Proof.
  unfold origin_rank; lia.
Qed.
