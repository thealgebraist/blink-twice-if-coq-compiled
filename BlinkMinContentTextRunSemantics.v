From Stdlib Require Import ZArith Lists.List Lia.
Import ListNotations.
Open Scope Z_scope.

(* CSS Sizing 3 §4 Min-Content of Unbroken Text Run *)
Fixpoint sum_glyphs (run : list Z) : Z :=
  match run with
  | nil => 0
  | g :: rest => g + sum_glyphs rest
  end.

Definition min_content_text_run (run : list Z) : Z :=
  sum_glyphs run.

Theorem min_content_text_run_nonneg : forall run,
  (forall g, In g run -> g >= 0) ->
  min_content_text_run run >= 0.
Proof.
  induction run as [| g rest IH]; intros Hpos; cbn; [lia |].
  assert (Hg: g >= 0) by (apply Hpos; left; reflexivity).
  assert (Hrest: sum_glyphs rest >= 0).
  { apply IH. intros x Hx; apply Hpos; right; exact Hx. }
  lia.
Qed.

Theorem min_content_text_run_app : forall r1 r2,
  min_content_text_run (r1 ++ r2) = min_content_text_run r1 + min_content_text_run r2.
Proof.
  induction r1 as [| g rest IH]; intros r2; cbn; [reflexivity |].
  unfold min_content_text_run in *. cbn.
  rewrite IH. lia.
Qed.
