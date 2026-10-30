(* ========================================================================= *)
(*               BlinkAbsoluteCenteringSemantics.v                           *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Absolute Centering via Inset & Auto   *)
(* Margins per W3C CSS Positioned Layout Module Level 3 §5.                  *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Inductive MarginValue :=
  | MarginAuto
  | MarginLength (v : Z).

Record Absolute1DParams := {
  cb_size : Z;
  inset_start : Z;
  inset_end : Z;
  box_size : Z;
  margin_spec_start : MarginValue;
  margin_spec_end : MarginValue
}.

Definition compute_free_space (p : Absolute1DParams) : Z :=
  cb_size p - (inset_start p + inset_end p + box_size p).

Definition resolve_margins (p : Absolute1DParams) : Z * Z :=
  let free := compute_free_space p in
  match margin_spec_start p, margin_spec_end p with
  | MarginAuto, MarginAuto =>
      if free <? 0 then
        (0, free)
      else
        (free / 2, free - free / 2)
  | MarginAuto, MarginLength me =>
      (free - me, me)
  | MarginLength ms, MarginAuto =>
      (ms, free - ms)
  | MarginLength ms, MarginLength me =>
      (ms, me)
  end.

Theorem absolute_space_conservation_both_auto : forall p,
  margin_spec_start p = MarginAuto ->
  margin_spec_end p = MarginAuto ->
  let (ms, me) := resolve_margins p in
  inset_start p + ms + box_size p + me + inset_end p = cb_size p.
Proof.
  intros p Hauto_s Hauto_e.
  unfold resolve_margins, compute_free_space.
  rewrite Hauto_s, Hauto_e.
  destruct (cb_size p - (inset_start p + inset_end p + box_size p) <? 0) eqn:Hfree; cbn; lia.
Qed.

Theorem absolute_space_conservation_start_auto : forall p me,
  margin_spec_start p = MarginAuto ->
  margin_spec_end p = MarginLength me ->
  let (ms, me_res) := resolve_margins p in
  inset_start p + ms + box_size p + me_res + inset_end p = cb_size p.
Proof.
  intros p me Hauto_s Hlen_e.
  unfold resolve_margins, compute_free_space.
  rewrite Hauto_s, Hlen_e; cbn.
  lia.
Qed.

Theorem absolute_space_conservation_end_auto : forall p ms,
  margin_spec_start p = MarginLength ms ->
  margin_spec_end p = MarginAuto ->
  let (ms_res, me) := resolve_margins p in
  inset_start p + ms_res + box_size p + me + inset_end p = cb_size p.
Proof.
  intros p ms Hlen_s Hauto_e.
  unfold resolve_margins, compute_free_space.
  rewrite Hlen_s, Hauto_e; cbn.
  lia.
Qed.

Theorem absolute_centering_symmetry : forall p,
  margin_spec_start p = MarginAuto ->
  margin_spec_end p = MarginAuto ->
  compute_free_space p >= 0 ->
  let (ms, me) := resolve_margins p in
  Z.abs (ms - me) <= 1.
Proof.
  intros p Hauto_s Hauto_e Hfree_nonneg.
  unfold resolve_margins.
  rewrite Hauto_s, Hauto_e.
  assert (Hlt: compute_free_space p <? 0 = false) by (apply Z.ltb_ge; lia).
  rewrite Hlt.
  pose proof (Z.div_mod (compute_free_space p) 2) as Hdiv.
  assert (Htwo: 2 <> 0) by lia.
  specialize (Hdiv Htwo).
  pose proof (Z.mod_pos_bound (compute_free_space p) 2) as Hbound.
  assert (Hpos: 0 < 2) by lia.
  specialize (Hbound Hpos).
  assert (Hrem_cases: compute_free_space p mod 2 = 0 \/ compute_free_space p mod 2 = 1) by lia.
  destruct Hrem_cases as [H0 | H1]; lia.
Qed.

Theorem absolute_centering_nonneg : forall p,
  margin_spec_start p = MarginAuto ->
  margin_spec_end p = MarginAuto ->
  compute_free_space p >= 0 ->
  let (ms, me) := resolve_margins p in
  ms >= 0 /\ me >= 0.
Proof.
  intros p Hauto_s Hauto_e Hfree_nonneg.
  unfold resolve_margins.
  rewrite Hauto_s, Hauto_e.
  assert (Hlt: compute_free_space p <? 0 = false) by (apply Z.ltb_ge; lia).
  rewrite Hlt; cbn.
  assert (Hdiv: compute_free_space p / 2 >= 0) by (apply Z.le_ge; apply Z.div_pos; lia).
  pose proof (Z.div_le_upper_bound (compute_free_space p) 2 (compute_free_space p)) as Hup.
  assert (compute_free_space p / 2 <= compute_free_space p) by (apply Hup; lia).
  split; lia.
Qed.

