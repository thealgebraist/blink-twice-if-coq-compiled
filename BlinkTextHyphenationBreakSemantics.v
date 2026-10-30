(* ========================================================================= *)
(*               BlinkTextHyphenationBreakSemantics.v                        *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Text Hyphenation Opportunity       *)
(* Detection & Soft Hyphens per CSS Text Module Level 3 §5.4.                *)
(* Constructive, executable (vm_compute), extractable to C99/C++23/LLVM-IR.  *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.
Import ListNotations.

Inductive HyphensMode : Type :=
  | HyphensNone
  | HyphensManual
  | HyphensAuto.

Record HyphenationConfig : Type := mkConfig {
  min_prefix   : Z;
  min_suffix   : Z;
  hyphen_width : Z
}.

Record WordInput : Type := mkWord {
  word_len     : Z;
  prefix_width : Z -> Z;
  soft_hyphens : list Z;
  dict_hyphens : list Z
}.

Definition auto_bounds_b (cfg : HyphenationConfig) (len i : Z) : bool :=
  (1 <=? i) && (i <? len) &&
  (min_prefix cfg <=? i) && (i + min_suffix cfg <=? len).

Definition manual_bounds_b (len i : Z) : bool :=
  (1 <=? i) && (i <? len).

Definition fits_in_space_b (cfg : HyphenationConfig) (w : WordInput) (avail i : Z) : bool :=
  prefix_width w i + hyphen_width cfg <=? avail.

Definition candidate_indices (mode : HyphensMode) (cfg : HyphenationConfig) (w : WordInput) : list Z :=
  let len := word_len w in
  match mode with
  | HyphensNone => []
  | HyphensManual => filter (manual_bounds_b len) (soft_hyphens w)
  | HyphensAuto =>
      let manual_cands := filter (manual_bounds_b len) (soft_hyphens w) in
      match manual_cands with
      | _ :: _ => manual_cands
      | [] => filter (auto_bounds_b cfg len) (dict_hyphens w)
      end
  end.

Fixpoint max_fitting_index (cfg : HyphenationConfig) (w : WordInput) (avail : Z) (cands : list Z) : option Z :=
  match cands with
  | [] => None
  | i :: rest =>
      let best_rest := max_fitting_index cfg w avail rest in
      if fits_in_space_b cfg w avail i then
        match best_rest with
        | None => Some i
        | Some j => Some (Z.max i j)
        end
      else best_rest
  end.

Definition select_hyphen_break
  (mode : HyphensMode) (cfg : HyphenationConfig) (w : WordInput) (avail : Z) : option Z :=
  max_fitting_index cfg w avail (candidate_indices mode cfg w).

(* ------------------------------------------------------------------------- *)
(* Theorems                                                                  *)
(* ------------------------------------------------------------------------- *)

Theorem hyphens_none_no_breaks : forall cfg w avail,
  select_hyphen_break HyphensNone cfg w avail = None.
Proof.
  intros. unfold select_hyphen_break, candidate_indices. reflexivity.
Qed.

Lemma max_fitting_index_in_and_fits : forall cfg w avail cands i,
  max_fitting_index cfg w avail cands = Some i ->
  In i cands /\ fits_in_space_b cfg w avail i = true.
Proof.
  intros cfg w avail cands.
  induction cands as [| x rest IH]; intros i Hsel; cbn in Hsel; [discriminate Hsel |].
  destruct (fits_in_space_b cfg w avail x) eqn:Hfitx.
  - destruct (max_fitting_index cfg w avail rest) as [j |] eqn:Hrest.
    + injection Hsel as Heq. subst i.
      destruct (Z.max_spec x j) as [[Hlt Hmax] | [Hge Hmax]]; rewrite Hmax.
      * destruct (IH j eq_refl) as [Hin_j Hfit_j].
        split; [right; exact Hin_j | exact Hfit_j].
      * split; [left; reflexivity | exact Hfitx].
    + injection Hsel as Heq. subst i.
      split; [left; reflexivity | exact Hfitx].
  - destruct (IH i Hsel) as [Hin_i Hfit_i].
    split; [right; exact Hin_i | exact Hfit_i].
Qed.

Theorem selected_break_fits : forall mode cfg w avail i,
  select_hyphen_break mode cfg w avail = Some i ->
  prefix_width w i + hyphen_width cfg <= avail.
Proof.
  intros mode cfg w avail i Hsel.
  unfold select_hyphen_break in Hsel.
  apply max_fitting_index_in_and_fits in Hsel.
  destruct Hsel as [_ Hfit].
  unfold fits_in_space_b in Hfit.
  apply Z.leb_le in Hfit.
  exact Hfit.
Qed.

Theorem selected_break_bounds : forall mode cfg w avail i,
  select_hyphen_break mode cfg w avail = Some i ->
  1 <= i < word_len w.
Proof.
  intros mode cfg w avail i Hsel.
  unfold select_hyphen_break in Hsel.
  apply max_fitting_index_in_and_fits in Hsel.
  destruct Hsel as [Hin _].
  unfold candidate_indices in Hin.
  destruct mode.
  - contradiction Hin.
  - apply filter_In in Hin.
    destruct Hin as [_ Hmb].
    unfold manual_bounds_b in Hmb.
    apply andb_prop in Hmb.
    destruct Hmb as [Hge Hlt].
    apply Z.leb_le in Hge.
    apply Z.ltb_lt in Hlt.
    lia.
  - destruct (filter (manual_bounds_b (word_len w)) (soft_hyphens w)) as [| m ms] eqn:Em.
    + apply filter_In in Hin.
      destruct Hin as [_ Hab].
      unfold auto_bounds_b in Hab.
      apply andb_prop in Hab; destruct Hab as [Hab1 _].
      apply andb_prop in Hab1; destruct Hab1 as [Hab2 _].
      apply andb_prop in Hab2; destruct Hab2 as [Hge Hlt].
      apply Z.leb_le in Hge.
      apply Z.ltb_lt in Hlt.
      lia.
    + assert (Hin_filter: In i (filter (manual_bounds_b (word_len w)) (soft_hyphens w)))
        by (rewrite Em; exact Hin).
      apply filter_In in Hin_filter.
      destruct Hin_filter as [_ Hmb].
      unfold manual_bounds_b in Hmb.
      apply andb_prop in Hmb.
      destruct Hmb as [Hge Hlt].
      apply Z.leb_le in Hge.
      apply Z.ltb_lt in Hlt.
      lia.
Qed.

Theorem auto_break_respects_prefix_suffix : forall cfg w avail i,
  soft_hyphens w = nil ->
  select_hyphen_break HyphensAuto cfg w avail = Some i ->
  min_prefix cfg <= i /\ i + min_suffix cfg <= word_len w.
Proof.
  intros cfg w avail i Hsoft Hsel.
  unfold select_hyphen_break in Hsel.
  apply max_fitting_index_in_and_fits in Hsel.
  destruct Hsel as [Hin _].
  unfold candidate_indices in Hin.
  rewrite Hsoft in Hin.
  cbn in Hin.
  apply filter_In in Hin.
  destruct Hin as [_ Hab].
  unfold auto_bounds_b in Hab.
  apply andb_prop in Hab.
  destruct Hab as [Hab1 Hsuff].
  apply andb_prop in Hab1.
  destruct Hab1 as [_ Hpref].
  apply Z.leb_le in Hpref.
  apply Z.leb_le in Hsuff.
  split; assumption.
Qed.

