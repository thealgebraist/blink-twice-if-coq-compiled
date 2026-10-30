(* =========================================================================
   BlinkGridPlacementSemantics.v
   Formalization of Chromium Blink Grid Line Resolution & Placement Constraints
   Source: third_party/blink/renderer/core/layout/grid/grid_placement.cc
           third_party/blink/renderer/core/layout/grid/grid_line_resolver.cc
   Specification: W3C CSS Grid Layout Module Level 1 §8.3 & §8.5
   ========================================================================= *)

From Coq Require Import ZArith.ZArith.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Open Scope Z_scope.

Definition resolve_grid_line (line_idx : Z) (explicit_tracks : Z) : Z :=
  if line_idx >? 0 then
    line_idx - 1
  else if line_idx <? 0 then
    (explicit_tracks + 1) + line_idx
  else
    0.

Record ResolvedGridSpan : Type := mkResolvedGridSpan {
  span_start : Z;
  span_end : Z
}.

Definition resolve_grid_span (s : Z) (d : Z) : ResolvedGridSpan :=
  if s <? d then
    mkResolvedGridSpan s d
  else if s >? d then
    mkResolvedGridSpan d s
  else
    mkResolvedGridSpan s (s + 1).

Theorem resolve_grid_line_deterministic :
  forall line_idx explicit_tracks l1 l2,
    l1 = resolve_grid_line line_idx explicit_tracks ->
    l2 = resolve_grid_line line_idx explicit_tracks ->
    l1 = l2.
Proof.
  intros line_idx explicit_tracks l1 l2 H1 H2.
  subst. reflexivity.
Qed.

Theorem negative_one_resolves_to_explicit_end :
  forall explicit_tracks,
    0 <= explicit_tracks ->
    resolve_grid_line (-1) explicit_tracks = explicit_tracks.
Proof.
  intros explicit_tracks Hexp.
  unfold resolve_grid_line.
  assert (Hgt : (-1 >? 0) = false) by reflexivity.
  assert (Hlt : (-1 <? 0) = true) by reflexivity.
  rewrite Hgt. rewrite Hlt.
  lia.
Qed.

Theorem resolve_grid_span_strict_order :
  forall s d,
    (resolve_grid_span s d).(span_start) < (resolve_grid_span s d).(span_end).
Proof.
  intros s d.
  unfold resolve_grid_span.
  destruct (s <? d) eqn:Elt.
  - apply Z.ltb_lt in Elt. simpl. exact Elt.
  - destruct (s >? d) eqn:Egt.
    + apply Z.gtb_lt in Egt. simpl. exact Egt.
    + simpl. lia.
Qed.

Theorem resolve_grid_span_positive_span :
  forall s d,
    1 <= (resolve_grid_span s d).(span_end) - (resolve_grid_span s d).(span_start).
Proof.
  intros s d.
  pose proof (resolve_grid_span_strict_order s d) as Hlt.
  lia.
Qed.

