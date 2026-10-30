(* ========================================================================= *)
(*               BlinkTextIndentHangingSemantics.v                           *)
(* ========================================================================= *)
(* Formal semantics of Chromium Blink text-indent and hanging-punctuation   *)
(* per W3C CSS Text Module Level 3 §9.                                       *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool.Bool Lia.
Open Scope Z_scope.

Inductive LineKind :=
  | FirstFormattedLine
  | SubsequentLine.

Inductive TextIndentMode :=
  | StandardIndent
  | EachLineIndent.

Record TextIndentSpec := {
  indent_value : Z;
  indent_is_percent : bool;
  indent_mode : TextIndentMode
}.

Definition resolve_indent (spec : TextIndentSpec) (kind : LineKind) (cb_width : Z) : Z :=
  match kind, indent_mode spec with
  | FirstFormattedLine, _
  | SubsequentLine, EachLineIndent =>
      if indent_is_percent spec then
        (cb_width * indent_value spec) / 100
      else
        indent_value spec
  | SubsequentLine, StandardIndent => 0
  end.

Inductive HangingPunctuation :=
  | HangNone
  | HangStart (w : Z)
  | HangEnd (w : Z)
  | HangBoth (w_start w_end : Z).

Definition hanging_start_width (hp : HangingPunctuation) : Z :=
  match hp with
  | HangStart w => Z.max 0 w
  | HangBoth w _ => Z.max 0 w
  | _ => 0
  end.

Definition hanging_end_width (hp : HangingPunctuation) : Z :=
  match hp with
  | HangEnd w => Z.max 0 w
  | HangBoth _ w => Z.max 0 w
  | _ => 0
  end.

Definition available_line_inline_size (container_width : Z) (resolved_indent : Z) : Z :=
  container_width - resolved_indent.

Definition effective_content_space (avail_width : Z) (hp : HangingPunctuation) : Z :=
  avail_width + hanging_start_width hp + hanging_end_width hp.

Theorem subsequent_standard_indent_zero : forall spec cb_w,
  indent_mode spec = StandardIndent ->
  resolve_indent spec SubsequentLine cb_w = 0.
Proof.
  intros spec cb_w Hmode.
  unfold resolve_indent.
  rewrite Hmode.
  reflexivity.
Qed.

Theorem first_line_length_indent_identity : forall val mode cb_w,
  resolve_indent {| indent_value := val; indent_is_percent := false; indent_mode := mode |} FirstFormattedLine cb_w = val.
Proof.
  intros val mode cb_w.
  unfold resolve_indent; cbn.
  destruct mode; reflexivity.
Qed.

Theorem available_inline_size_conservation : forall container_w indent,
  available_line_inline_size container_w indent + indent = container_w.
Proof.
  intros container_w indent.
  unfold available_line_inline_size.
  lia.
Qed.

Theorem available_inline_size_monotonic_in_indent : forall container_w i1 i2,
  i1 <= i2 ->
  available_line_inline_size container_w i2 <= available_line_inline_size container_w i1.
Proof.
  intros container_w i1 i2 Hle.
  unfold available_line_inline_size.
  lia.
Qed.

Theorem hanging_widths_nonneg : forall hp,
  hanging_start_width hp >= 0 /\ hanging_end_width hp >= 0.
Proof.
  intros hp.
  destruct hp; cbn; split; try lia;
  apply Z.le_ge; apply Z.le_max_l.
Qed.

Theorem hanging_expands_content_space : forall avail hp,
  effective_content_space avail hp >= avail.
Proof.
  intros avail hp.
  unfold effective_content_space.
  pose proof (hanging_widths_nonneg hp) as [Hs He].
  lia.
Qed.

Theorem percent_indent_monotonic_in_cb : forall pct mode cb1 cb2,
  pct >= 0 ->
  cb1 <= cb2 ->
  resolve_indent {| indent_value := pct; indent_is_percent := true; indent_mode := mode |} FirstFormattedLine cb1 <=
  resolve_indent {| indent_value := pct; indent_is_percent := true; indent_mode := mode |} FirstFormattedLine cb2.
Proof.
  intros pct mode cb1 cb2 Hpct Hcb.
  unfold resolve_indent; cbn.
  destruct mode; apply Z.div_le_mono; try lia;
  apply Z.mul_le_mono_nonneg_r; lia.
Qed.

