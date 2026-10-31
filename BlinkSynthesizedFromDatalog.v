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

(* --- Formal Theory for Function f_html_lower --- *)
Definition blink_html_ascii_to_lower (c : Z) : Z :=
  if ((65%Z <=? c) && (c <=? 90%Z))%bool then
    (c + 32%Z)%Z
  else
    c.

Theorem blink_html_ascii_to_lower_idempotent : forall (c : Z),
  blink_html_ascii_to_lower (blink_html_ascii_to_lower c) = blink_html_ascii_to_lower c.
Proof.
  intro c. unfold blink_html_ascii_to_lower.
  destruct ((65%Z <=? c) && (c <=? 90%Z))%bool eqn:Hu.
  - apply andb_true_iff in Hu. destruct Hu as [H1 H2].
    apply Z.leb_le in H1. apply Z.leb_le in H2.
    assert (Hhi: ((c + 32%Z)%Z <=? 90%Z) = false) by (apply Z.leb_gt; lia).
    rewrite Hhi, andb_false_r. reflexivity.
  - rewrite Hu. reflexivity.
Qed.

(* --- Formal Theory for Function f_html_colspan --- *)
Definition blink_html_clamp_colspan (span : Z) : Z :=
  (Z.max 1%Z (Z.min 1000%Z span)).

Theorem blink_html_clamp_colspan_range_bounds : forall (span : Z),
  1 <= blink_html_clamp_colspan span <= 1000.
Proof.
  intro span. unfold blink_html_clamp_colspan. lia.
Qed.

(* --- Formal Theory for Function f_html_rowspan --- *)
Definition blink_html_clamp_rowspan (span : Z) : Z :=
  (Z.max 0%Z (Z.min 65534%Z span)).

Theorem blink_html_clamp_rowspan_range_bounds : forall (span : Z),
  0 <= blink_html_clamp_rowspan span <= 65534.
Proof.
  intro span. unfold blink_html_clamp_rowspan. lia.
Qed.

(* --- Formal Theory for Function f_css_spec --- *)
Definition blink_css_pack_specificity (ids : Z) (classes : Z) (tags : Z) : Z :=
  ((((Z.max 0%Z (Z.min 255%Z ids)) * 65536%Z)%Z + ((Z.max 0%Z (Z.min 255%Z classes)) * 256%Z)%Z)%Z + (Z.max 0%Z (Z.min 255%Z tags)))%Z.

Theorem blink_css_pack_specificity_id_strict_dominance : forall (i1 c1 t1 i2 c2 t2 : Z),
  0 <= i1 -> i1 < i2 -> i2 <= 255 ->
  0 <= c1 <= 255 -> 0 <= t1 <= 255 ->
  0 <= c2 <= 255 -> 0 <= t2 <= 255 ->
  blink_css_pack_specificity i1 c1 t1 < blink_css_pack_specificity i2 c2 t2.
Proof.
  intros. unfold blink_css_pack_specificity. lia.
Qed.

(* --- Formal Theory for Function f_css_layer --- *)
Definition blink_css_effective_layer_priority (layer_order : Z) (is_important : bool) (max_layers : Z) : Z :=
  if is_important then
    (max_layers - layer_order)%Z
  else
    layer_order.

Theorem blink_css_effective_layer_priority_important_inversion : forall (l1 l2 max_l : Z),
  l1 < l2 ->
  blink_css_effective_layer_priority l1 false max_l < blink_css_effective_layer_priority l2 false max_l /\
  blink_css_effective_layer_priority l2 true max_l < blink_css_effective_layer_priority l1 true max_l.
Proof.
  intros l1 l2 max_l Hlt. unfold blink_css_effective_layer_priority. simpl. lia.
Qed.

(* --- Formal Theory for Function f_css_vw --- *)
Definition blink_css_resolve_viewport_vw (vw_units : Z) (viewport_w : Z) : Z :=
  (Z.div (viewport_w * vw_units)%Z 100%Z).

Theorem blink_css_resolve_viewport_vw_100vw_identity : forall (vw_px : Z),
  0 <= vw_px ->
  blink_css_resolve_viewport_vw 100 vw_px = vw_px.
Proof.
  intros vw_px Hvw. unfold blink_css_resolve_viewport_vw. simpl.
  apply Z.div_mul. lia.
Qed.

(* --- Formal Theory for Function f_css_premul --- *)
Definition blink_css_premultiply_channel (ch : Z) (alpha : Z) : Z :=
  (Z.div (ch * alpha)%Z 255%Z).

Theorem blink_css_premultiply_channel_channel_bounds : forall (ch alpha : Z),
  0 <= ch <= 255 -> 0 <= alpha <= 255 ->
  0 <= blink_css_premultiply_channel ch alpha <= ch.
Proof.
  intros ch alpha Hch Ha. unfold blink_css_premultiply_channel.
  split.
  - apply Z.div_pos; [apply Z.mul_nonneg_nonneg; lia | lia].
  - apply Z.div_le_upper_bound; [lia | nia].
Qed.

(* --- Formal Theory for Function f_css_bbox --- *)
Definition blink_css_border_box_to_content_size (bb_w : Z) (pad_s : Z) (bdr_s : Z) : Z :=
  (Z.max 0%Z ((bb_w - pad_s)%Z - bdr_s)%Z).

Theorem blink_css_border_box_to_content_size_conservation : forall (bb_w pad_s bdr_s : Z),
  0 <= blink_css_border_box_to_content_size bb_w pad_s bdr_s /\
  (pad_s + bdr_s <= bb_w -> blink_css_border_box_to_content_size bb_w pad_s bdr_s + pad_s + bdr_s = bb_w).
Proof.
  intros bb_w pad_s bdr_s. unfold blink_css_border_box_to_content_size. lia.
Qed.

(* --- Formal Theory for Function f_css_sh2 --- *)
Definition blink_css_shorthand_2_outsets (vert : Z) (horiz : Z) : (Z * Z)%type :=
  ((vert + vert)%Z, (horiz + horiz)%Z).

Theorem blink_css_shorthand_2_outsets_nonneg_symmetry : forall (vert horiz : Z),
  0 <= vert -> 0 <= horiz ->
  let '(bv, bh) := blink_css_shorthand_2_outsets vert horiz in
  0 <= bv /\ 0 <= bh /\ bv + bh = 2 * (vert + horiz).
Proof.
  intros vert horiz Hv Hh. unfold blink_css_shorthand_2_outsets. lia.
Qed.

