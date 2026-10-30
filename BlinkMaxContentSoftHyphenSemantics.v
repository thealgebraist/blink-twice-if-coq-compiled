From Stdlib Require Import ZArith Lia.
Open Scope Z_scope.

(* CSS Sizing 3 §4 Max-Content of Soft-Hyphenated Word *)
Record HyphenatedWordMetrics := {
  hwm_prefix_w : Z;
  hwm_suffix_w : Z;
  hwm_hyphen_w : Z
}.

Definition word_max_content (m : HyphenatedWordMetrics) : Z :=
  hwm_prefix_w m + hwm_suffix_w m.

Definition word_min_content (m : HyphenatedWordMetrics) : Z :=
  Z.max (hwm_prefix_w m + hwm_hyphen_w m) (hwm_suffix_w m).

Theorem max_content_ge_prefix : forall m,
  hwm_suffix_w m >= 0 ->
  word_max_content m >= hwm_prefix_w m.
Proof.
  intros m Hsuff. unfold word_max_content. lia.
Qed.

Theorem max_content_ge_suffix : forall m,
  hwm_prefix_w m >= 0 ->
  word_max_content m >= hwm_suffix_w m.
Proof.
  intros m Hpref. unfold word_max_content. lia.
Qed.
