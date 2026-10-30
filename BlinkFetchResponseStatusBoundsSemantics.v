Require Import ZArith.
Require Import Lia.
Require Import Bool.
Open Scope Z_scope.

(** * Blink Fetch Response Status Bounds & Null Body Semantics *)
(** Fetch Standard §5.5: status in [100, 599]; null body statuses {101, 204, 205, 304} *)

Definition is_valid_http_status (s : Z) : bool :=
  (100 <=? s) && (s <=? 599).

Definition is_null_body_status (s : Z) : bool :=
  (s =? 101) || (s =? 204) || (s =? 205) || (s =? 304).

Theorem null_body_statuses_are_valid : forall s,
  is_null_body_status s = true ->
  is_valid_http_status s = true.
Proof.
  intros s Hnull.
  unfold is_null_body_status in Hnull.
  unfold is_valid_http_status.
  apply orb_prop in Hnull.
  destruct Hnull as [H | H].
  - apply orb_prop in H. destruct H as [H | H].
    + apply orb_prop in H. destruct H as [H | H]; apply Z.eqb_eq in H; subst; reflexivity.
    + apply Z.eqb_eq in H; subst; reflexivity.
  - apply Z.eqb_eq in H; subst; reflexivity.
Qed.

Theorem standard_ok_has_body :
  is_null_body_status 200 = false.
Proof.
  reflexivity.
Qed.
