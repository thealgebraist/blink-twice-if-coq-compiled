(* ========================================================================= *)
(*               BlinkTableColspanRowspanSemantics.v                         *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink Colspan and Rowspan Expansion          *)
(* per HTML Living Standard §4.9.11 and CSS 2.1 §17.5.1.                    *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

Definition kMinTableSpan : Z := 1.
Definition kMaxTableSpan : Z := 65534.

Definition clamp_span (raw : Z) : Z :=
  Z.max kMinTableSpan (Z.min kMaxTableSpan raw).

Theorem clamp_span_bounds : forall raw,
  kMinTableSpan <= clamp_span raw <= kMaxTableSpan.
Proof.
  intros raw.
  unfold clamp_span, kMinTableSpan, kMaxTableSpan.
  split; [apply Z.le_max_l |].
  apply Z.max_lub_iff.
  split; [lia | apply Z.le_min_l].
Qed.

Theorem clamp_span_idempotent : forall raw,
  clamp_span (clamp_span raw) = clamp_span raw.
Proof.
  intros raw.
  pose proof (clamp_span_bounds raw) as [Hl Hr].
  unfold clamp_span.
  lia.
Qed.

Definition compute_spanned_dimension (track_sz span spacing : Z) : Z :=
  span * track_sz + (span - 1) * spacing.

Theorem spanned_dimension_at_1 : forall track_sz spacing,
  compute_spanned_dimension track_sz 1 spacing = track_sz.
Proof.
  intros track_sz spacing.
  unfold compute_spanned_dimension.
  ring.
Qed.

Theorem spanned_dimension_ge_track : forall track_sz span spacing,
  span >= 1 ->
  track_sz >= 0 ->
  spacing >= 0 ->
  compute_spanned_dimension track_sz span spacing >= track_sz.
Proof.
  intros track_sz span spacing Hspan Hsz Hsp.
  unfold compute_spanned_dimension.
  assert (H1: span * track_sz >= 1 * track_sz) by nia.
  assert (H2: (span - 1) * spacing >= 0) by nia.
  lia.
Qed.

Theorem spanned_dimension_monotonic : forall track_sz s1 s2 spacing,
  1 <= s1 ->
  s1 <= s2 ->
  track_sz >= 0 ->
  spacing >= 0 ->
  compute_spanned_dimension track_sz s1 spacing <= compute_spanned_dimension track_sz s2 spacing.
Proof.
  intros track_sz s1 s2 spacing Hs1 Hle Hsz Hsp.
  unfold compute_spanned_dimension.
  assert (Hterm1: s1 * track_sz <= s2 * track_sz) by nia.
  assert (Hterm2: (s1 - 1) * spacing <= (s2 - 1) * spacing) by nia.
  lia.
Qed.

Definition intervals_disjoint (x1 w1 x2 w2 : Z) : Prop :=
  x1 + w1 <= x2 \/ x2 + w2 <= x1.

Definition cells_disjoint_2d (r1 c1 rs1 cs1 r2 c2 rs2 cs2 : Z) : Prop :=
  intervals_disjoint r1 rs1 r2 rs2 \/ intervals_disjoint c1 cs1 c2 cs2.

Theorem col_separation_implies_2d_disjoint : forall r1 c1 rs1 cs1 r2 c2 rs2 cs2,
  intervals_disjoint c1 cs1 c2 cs2 ->
  cells_disjoint_2d r1 c1 rs1 cs1 r2 c2 rs2 cs2.
Proof.
  intros. unfold cells_disjoint_2d. right. assumption.
Qed.

Theorem row_separation_implies_2d_disjoint : forall r1 c1 rs1 cs1 r2 c2 rs2 cs2,
  intervals_disjoint r1 rs1 r2 rs2 ->
  cells_disjoint_2d r1 c1 rs1 cs1 r2 c2 rs2 cs2.
Proof.
  intros. unfold cells_disjoint_2d. left. assumption.
Qed.
