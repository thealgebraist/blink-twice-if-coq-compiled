From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.

Definition resolve_grid_span (start_line span : Z) : Z :=
  start_line + span.

Definition clamp_grid_line (line : Z) : Z :=
  Z.max 1 (Z.min 10000 line).

Theorem span_strictly_advances : forall start span,
  span > 0 ->
  resolve_grid_span start span > start.
Proof.
  intros. unfold resolve_grid_span. lia.
Qed.

Theorem clamped_grid_line_in_bounds : forall line,
  1 <= clamp_grid_line line <= 10000.
Proof.
  intros. unfold clamp_grid_line. lia.
Qed.

Theorem span_length_preserved_within_bounds : forall start span,
  1 <= start ->
  0 <= span ->
  start + span <= 10000 ->
  clamp_grid_line (resolve_grid_span start span) - clamp_grid_line start = span.
Proof.
  intros start span H1 Hspan H2.
  unfold resolve_grid_span, clamp_grid_line.
  assert (Hmin1: Z.min 10000 (start + span) = start + span) by lia.
  assert (Hmin2: Z.min 10000 start = start) by lia.
  rewrite Hmin1, Hmin2.
  assert (Hmax1: Z.max 1 (start + span) = start + span) by lia.
  assert (Hmax2: Z.max 1 start = start) by lia.
  rewrite Hmax1, Hmax2.
  lia.
Qed.
