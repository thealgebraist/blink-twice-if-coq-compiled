Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Cache Storage Request Matching Semantics *)
(** Service Workers §5.4: exact URL matching with option to ignore query *)

Definition cache_match_url (req_url cached_url : Z)
                           (ignore_search : bool)
                           (req_base cached_base : Z) : bool :=
  if ignore_search then req_base =? cached_base
  else req_url =? cached_url.

Theorem cache_match_exact_refl : forall u b,
  cache_match_url u u false b b = true.
Proof.
  intros u b.
  unfold cache_match_url.
  rewrite Z.eqb_refl.
  reflexivity.
Qed.

Theorem cache_match_ignore_search_sound : forall u1 u2 b,
  cache_match_url u1 u2 true b b = true.
Proof.
  intros u1 u2 b.
  unfold cache_match_url.
  rewrite Z.eqb_refl.
  reflexivity.
Qed.
