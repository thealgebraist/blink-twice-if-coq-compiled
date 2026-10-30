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
