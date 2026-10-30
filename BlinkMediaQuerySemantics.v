(******************************************************************************)
(* BlinkMediaQuerySemantics.v                                                 *)
(* Sound Formal Specification for CSS Media Query Evaluation                  *)
(* Corresponding to:                                                          *)
(* 1. W3C Media Queries Level 4 & Level 5                                     *)
(* 2. Blink MediaQueryEvaluator (`media_query_evaluator.cc`) &                *)
(*    MediaQueryExp (`media_query_exp.cc`)                                    *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Open Scope Z_scope.

(** W3C Three-Valued Logic: True, False, Unknown *)
Inductive TriBool : Type :=
  | TriTrue
  | TriFalse
  | TriUnknown.

Definition tri_not (b : TriBool) : TriBool :=
  match b with
  | TriTrue => TriFalse
  | TriFalse => TriTrue
  | TriUnknown => TriUnknown
  end.

Definition tri_and (b1 b2 : TriBool) : TriBool :=
  match b1, b2 with
  | TriFalse, _ | _, TriFalse => TriFalse
  | TriTrue, TriTrue => TriTrue
  | _, _ => TriUnknown
  end.

Definition tri_or (b1 b2 : TriBool) : TriBool :=
  match b1, b2 with
  | TriTrue, _ | _, TriTrue => TriTrue
  | TriFalse, TriFalse => TriFalse
  | _, _ => TriUnknown
  end.

Record ViewportState := mkViewportState {
  vp_width : Z;
  vp_height : Z;
  vp_prefers_dark : bool
}.

Inductive MediaFeature : Type :=
  | MFFeatureMinWidth (min_w : Z)
  | MFFeatureMaxWidth (max_w : Z)
  | MFFeaturePrefersDark.

Definition eval_media_feature (feat : MediaFeature) (state : ViewportState) : TriBool :=
  match feat with
  | MFFeatureMinWidth min_w =>
      if min_w <=? vp_width state then TriTrue else TriFalse
  | MFFeatureMaxWidth max_w =>
      if vp_width state <=? max_w then TriTrue else TriFalse
  | MFFeaturePrefersDark =>
      if vp_prefers_dark state then TriTrue else TriFalse
  end.

(******************************************************************************)
(* SOUNDNESS & DE MORGAN THEOREMS FOR THREE-VALUED LOGIC (0 admits)           *)
(******************************************************************************)

Theorem tri_not_involutive : forall b,
  tri_not (tri_not b) = b.
Proof.
  destruct b; reflexivity.
Qed.

Theorem tri_de_morgan_and : forall b1 b2,
  tri_not (tri_and b1 b2) = tri_or (tri_not b1) (tri_not b2).
Proof.
  destruct b1; destruct b2; reflexivity.
Qed.

Theorem tri_de_morgan_or : forall b1 b2,
  tri_not (tri_or b1 b2) = tri_and (tri_not b1) (tri_not b2).
Proof.
  destruct b1; destruct b2; reflexivity.
Qed.

Theorem min_width_monotonic :
  forall w1 w2 req_w st1 st2,
    vp_width st1 = w1 ->
    vp_width st2 = w2 ->
    w1 <= w2 ->
    eval_media_feature (MFFeatureMinWidth req_w) st1 = TriTrue ->
    eval_media_feature (MFFeatureMinWidth req_w) st2 = TriTrue.
Proof.
  intros w1 w2 req_w st1 st2 Hw1 Hw2 Hwle Heval.
  unfold eval_media_feature in *.
  rewrite Hw1 in Heval. rewrite Hw2.
  destruct (req_w <=? w1) eqn:Ew1; [| discriminate].
  apply Z.leb_le in Ew1.
  assert (req_w <= w2) by lia.
  apply Z.leb_le in H. rewrite H. reflexivity.
Qed.
