Require Import ZArith.
Require Import Lia.
Open Scope Z_scope.

(** * Blink @page Size Resolution Semantics *)
(** CSS Paged Media 3 §3.1: standard page dimensions *)

Inductive PageSizePreset :=
  | PageSizeA4
  | PageSizeLetter
  | PageSizeCustom (w h : Z).

Record PageDimensions := {
  page_width : Z;
  page_height : Z
}.

Definition resolve_page_size (preset : PageSizePreset) : PageDimensions :=
  match preset with
  | PageSizeA4 => {| page_width := 794; page_height := 1123 |}
  | PageSizeLetter => {| page_width := 816; page_height := 1056 |}
  | PageSizeCustom w h => {| page_width := Z.max 1 w; page_height := Z.max 1 h |}
  end.

Theorem page_dimensions_positive : forall preset,
  0 < page_width (resolve_page_size preset) /\
  0 < page_height (resolve_page_size preset).
Proof.
  intros preset.
  destruct preset; simpl; split; lia.
Qed.
