(* ========================================================================= *)
(* Machine-Generated Rocq/Coq Theories from C++ AST via Souffle Datalog       *)
(* Specification: cpp_to_coq_translator.dl                                   *)
(* Verification: 100% Soundness, Strictly 0 Admits                           *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Bool Lia.
Open Scope Z_scope.
Open Scope bool_scope.

(* --- Formal Theory for Function f_clamp --- *)
Definition blink_clamp_size_to_min_max (size : Z) (min_size : Z) (max_size : Z) : Z :=
  if (size <? min_size) then
    min_size
  else
    if (max_size <? size) then
    max_size
  else
    size.

Theorem blink_clamp_size_to_min_max_bounding_soundness : forall (size min_s max_s : Z),
  min_s <= max_s ->
  min_s <= blink_clamp_size_to_min_max size min_s max_s <= max_s.
Proof.
  intros size min_s max_s Hle.
  unfold blink_clamp_size_to_min_max.
  destruct (size <? min_s) eqn:Hmin.
  - apply Z.ltb_lt in Hmin. lia.
  - apply Z.ltb_ge in Hmin.
    destruct (max_s <? size) eqn:Hmax.
    + apply Z.ltb_lt in Hmax. lia.
    + apply Z.ltb_ge in Hmax. lia.
Qed.

(* --- Formal Theory for Function f_margin --- *)
Definition blink_margin_strut_collapse (pos : Z) (neg : Z) (inc : Z) : (Z * Z)%type :=
  if (0%Z <? inc) then
    (if (pos <? inc) then inc else pos, neg)
  else
    (pos, if (inc <? neg) then inc else neg).

Theorem blink_margin_strut_collapse_margin_partition_law : forall (pos neg inc : Z),
  0 <= pos ->
  neg <= 0 ->
  let '(p', n') := blink_margin_strut_collapse pos neg inc in
  0 <= p' /\ n' <= 0.
Proof.
  intros pos neg inc Hpos Hneg.
  unfold blink_margin_strut_collapse.
  destruct (0 <? inc) eqn:Hinc; [destruct (pos <? inc) eqn:Hp | destruct (inc <? neg) eqn:Hn]; split;
  try lia;
  try (apply Z.ltb_lt in Hinc; lia);
  try (apply Z.ltb_ge in Hinc; lia).
Qed.

(* --- Formal Theory for Function f_flex --- *)
Definition blink_flex_distribute_share (space : Z) (weight : Z) (total_weight : Z) : Z :=
  if (total_weight <=? 0%Z) then
    0%Z
  else
    let numerator := (space * weight)%Z in
  (Z.div numerator total_weight).

Theorem blink_flex_distribute_share_share_non_negative : forall (space w tot : Z),
  0 <= space -> 0 <= w -> 0 < tot ->
  0 <= blink_flex_distribute_share space w tot.
Proof.
  intros space w tot Hs Hw Ht.
  unfold blink_flex_distribute_share.
  destruct (tot <=? 0%Z) eqn:Hle.
  - lia.
  - apply Z.leb_gt in Hle.
    apply Z.div_pos; [| lia].
    apply Z.mul_nonneg_nonneg; lia.
Qed.

