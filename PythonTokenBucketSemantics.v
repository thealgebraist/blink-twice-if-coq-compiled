From Stdlib Require Import Bool ZArith Lia.
Open Scope Z_scope.
Open Scope bool_scope.

(** * Synthesized Rocq/Coq Theory for Non-Trivial Python: Token Bucket Rate Limiter
    Synthesized autonomously from Python AST by PythonToCoqTranspiler.
*)

Definition token_bucket_consume (capacity fill_rate tokens delta_time requested : Z) : (bool * Z) :=
  let dt := Z.max 0 delta_time in
  let replenished := Z.min capacity (tokens + dt * fill_rate) in
  if (requested <=? replenished) && (0 <? requested) then
    (true, replenished - requested)
  else
    (false, replenished).

(** THEOREM 1: Capacity Upper-Bound Invariant
    Tokens after consumption or rejection never exceed bucket capacity.
*)
Theorem token_bucket_capacity_bound :
  forall capacity fill_rate tokens delta_time requested : Z,
    capacity >= 0 ->
    let '(_, remaining) := token_bucket_consume capacity fill_rate tokens delta_time requested in
    remaining <= capacity.
Proof.
  intros capacity fill_rate tokens delta_time requested Hcap.
  unfold token_bucket_consume.
  set (dt := Z.max 0 delta_time).
  set (rep := Z.min capacity (tokens + dt * fill_rate)).
  assert (Hrep_cap: rep <= capacity) by (apply Z.le_min_l).
  destruct ((requested <=? rep) && (0 <? requested)) eqn:Hcond.
  - apply andb_prop in Hcond as [Hle Hgt].
    apply Z.leb_le in Hle.
    apply Z.ltb_lt in Hgt.
    lia.
  - lia.
Qed.

(** THEOREM 2: Non-Negative Tokens Invariant
    If capacity >= 0 and initial tokens >= 0, remaining tokens are always >= 0.
*)
Theorem token_bucket_non_negative :
  forall capacity fill_rate tokens delta_time requested : Z,
    capacity >= 0 ->
    fill_rate >= 0 ->
    tokens >= 0 ->
    let '(_, remaining) := token_bucket_consume capacity fill_rate tokens delta_time requested in
    remaining >= 0.
Proof.
  intros capacity fill_rate tokens delta_time requested Hcap Hrate Htok.
  unfold token_bucket_consume.
  set (dt := Z.max 0 delta_time).
  assert (Hdt: dt >= 0) by lia.
  set (rep := Z.min capacity (tokens + dt * fill_rate)).
  assert (Hrep_pos: 0 <= rep).
  {
    unfold rep.
    apply Z.min_glb; [lia |].
    assert (0 <= dt * fill_rate) by (apply Z.mul_nonneg_nonneg; lia).
    lia.
  }
  destruct ((requested <=? rep) && (0 <? requested)) eqn:Hcond.
  - apply andb_prop in Hcond as [Hle Hgt].
    apply Z.leb_le in Hle.
    lia.
  - lia.
Qed.

(** THEOREM 3: Conservation on Rejection
    If a request is rejected (success = false), no tokens are consumed.
*)
Theorem token_bucket_rejection_conservation :
  forall capacity fill_rate tokens delta_time requested : Z,
    let '(success, remaining) := token_bucket_consume capacity fill_rate tokens delta_time requested in
    success = false ->
    remaining = Z.min capacity (tokens + (Z.max 0 delta_time) * fill_rate).
Proof.
  intros capacity fill_rate tokens delta_time requested.
  unfold token_bucket_consume.
  destruct ((requested <=? Z.min capacity (tokens + Z.max 0 delta_time * fill_rate)) && (0 <? requested)) eqn:Hcond.
  - intros Hsucc. discriminate.
  - intros Hsucc. reflexivity.
Qed.
