(* Blink2Coq HTML/CSS Synthesis for StyleCascade *)
(* Source: renderer/core/css/resolver/style_cascade.cc *)

Require Import ZArith Lia. Open Scope Z_scope.
Definition cascade_origin_priority (origin : Z) : Z :=
  (* 1 = UserAgentNormal, 2 = UserNormal, 3 = AuthorNormal, 4 = Animation, 5 = AuthorImportant *)
  origin.
Theorem author_important_beats_normal :
  cascade_origin_priority 3 < cascade_origin_priority 5.
Proof. unfold cascade_origin_priority. lia. Qed.
