(* ========================================================================= *)
(*               BlinkClipPathPolygonSemantics.v                             *)
(* ========================================================================= *)
(* Formal verification of Chromium Blink Clip Path Polygon Geometry and      *)
(* Axis-Aligned Bounding Box Containment per CSS Masking Module Level 1 §5.  *)
(* Constructive, executable (vm_compute), extractable to C99/C++23/LLVM-IR.  *)
(* Strictly verified with 0 admits.                                          *)
(* ========================================================================= *)

From Stdlib Require Import ZArith Lists.List Bool Lia.
Open Scope Z_scope.
Import ListNotations.

Record Point2D := mkPoint2D {
  pt_x : Z;
  pt_y : Z
}.

Record Rect2D := mkRect2D {
  rect_x : Z;
  rect_y : Z;
  rect_w : Z;
  rect_h : Z
}.

Definition point_in_rect (p : Point2D) (r : Rect2D) : bool :=
  (rect_x r <=? pt_x p) && (pt_x p <=? rect_x r + rect_w r) &&
  (rect_y r <=? pt_y p) && (pt_y p <=? rect_y r + rect_h r).

Fixpoint polygon_min_x (pts : list Point2D) (acc : Z) : Z :=
  match pts with
  | [] => acc
  | p :: rest => polygon_min_x rest (Z.min acc (pt_x p))
  end.

Fixpoint polygon_max_x (pts : list Point2D) (acc : Z) : Z :=
  match pts with
  | [] => acc
  | p :: rest => polygon_max_x rest (Z.max acc (pt_x p))
  end.

Fixpoint polygon_min_y (pts : list Point2D) (acc : Z) : Z :=
  match pts with
  | [] => acc
  | p :: rest => polygon_min_y rest (Z.min acc (pt_y p))
  end.

Fixpoint polygon_max_y (pts : list Point2D) (acc : Z) : Z :=
  match pts with
  | [] => acc
  | p :: rest => polygon_max_y rest (Z.max acc (pt_y p))
  end.

Definition compute_polygon_bbox (pts : list Point2D) : option Rect2D :=
  match pts with
  | [] => None
  | p0 :: rest =>
      let min_x := polygon_min_x rest (pt_x p0) in
      let max_x := polygon_max_x rest (pt_x p0) in
      let min_y := polygon_min_y rest (pt_y p0) in
      let max_y := polygon_max_y rest (pt_y p0) in
      Some (mkRect2D min_x min_y (max_x - min_x) (max_y - min_y))
  end.

(* ------------------------------------------------------------------------- *)
(* Theorems                                                                  *)
(* ------------------------------------------------------------------------- *)

Lemma polygon_min_x_acc : forall pts acc,
  polygon_min_x pts acc <= acc.
Proof.
  induction pts as [| p rest IH]; intros acc; cbn; [lia |].
  specialize (IH (Z.min acc (pt_x p))).
  lia.
Qed.

Lemma polygon_min_x_le : forall pts acc p,
  In p pts -> polygon_min_x pts acc <= pt_x p.
Proof.
  induction pts as [| p0 rest IH]; intros acc p Hin; [contradiction Hin |].
  cbn.
  destruct Hin as [-> | Hin_rest].
  - pose proof (polygon_min_x_acc rest (Z.min acc (pt_x p))).
    lia.
  - apply (IH (Z.min acc (pt_x p0)) p Hin_rest).
Qed.

Lemma polygon_max_x_acc : forall pts acc,
  polygon_max_x pts acc >= acc.
Proof.
  induction pts as [| p rest IH]; intros acc; cbn; [lia |].
  specialize (IH (Z.max acc (pt_x p))).
  lia.
Qed.

Lemma polygon_max_x_ge : forall pts acc p,
  In p pts -> polygon_max_x pts acc >= pt_x p.
Proof.
  induction pts as [| p0 rest IH]; intros acc p Hin; [contradiction Hin |].
  cbn.
  destruct Hin as [-> | Hin_rest].
  - pose proof (polygon_max_x_acc rest (Z.max acc (pt_x p))).
    lia.
  - apply (IH (Z.max acc (pt_x p0)) p Hin_rest).
Qed.

Lemma polygon_min_y_acc : forall pts acc,
  polygon_min_y pts acc <= acc.
Proof.
  induction pts as [| p rest IH]; intros acc; cbn; [lia |].
  specialize (IH (Z.min acc (pt_y p))).
  lia.
Qed.

Lemma polygon_min_y_le : forall pts acc p,
  In p pts -> polygon_min_y pts acc <= pt_y p.
Proof.
  induction pts as [| p0 rest IH]; intros acc p Hin; [contradiction Hin |].
  cbn.
  destruct Hin as [-> | Hin_rest].
  - pose proof (polygon_min_y_acc rest (Z.min acc (pt_y p))).
    lia.
  - apply (IH (Z.min acc (pt_y p0)) p Hin_rest).
Qed.

Lemma polygon_max_y_acc : forall pts acc,
  polygon_max_y pts acc >= acc.
Proof.
  induction pts as [| p rest IH]; intros acc; cbn; [lia |].
  specialize (IH (Z.max acc (pt_y p))).
  lia.
Qed.

Lemma polygon_max_y_ge : forall pts acc p,
  In p pts -> polygon_max_y pts acc >= pt_y p.
Proof.
  induction pts as [| p0 rest IH]; intros acc p Hin; [contradiction Hin |].
  cbn.
  destruct Hin as [-> | Hin_rest].
  - pose proof (polygon_max_y_acc rest (Z.max acc (pt_y p))).
    lia.
  - apply (IH (Z.max acc (pt_y p0)) p Hin_rest).
Qed.

Theorem bbox_dimensions_nonneg : forall pts bbox,
  compute_polygon_bbox pts = Some bbox ->
  rect_w bbox >= 0 /\ rect_h bbox >= 0.
Proof.
  intros [| p0 rest] bbox Hbox; [discriminate Hbox |].
  cbn in Hbox.
  injection Hbox as <-.
  cbn.
  pose proof (polygon_min_x_acc rest (pt_x p0)).
  pose proof (polygon_max_x_acc rest (pt_x p0)).
  pose proof (polygon_min_y_acc rest (pt_y p0)).
  pose proof (polygon_max_y_acc rest (pt_y p0)).
  lia.
Qed.

Theorem bbox_contains_all_vertices : forall pts bbox p,
  compute_polygon_bbox pts = Some bbox ->
  In p pts ->
  point_in_rect p bbox = true.
Proof.
  intros [| p0 rest] bbox p Hbox Hin; [contradiction Hin |].
  cbn in Hbox.
  injection Hbox as <-.
  unfold point_in_rect; cbn.
  destruct Hin as [-> | Hin_rest].
  - pose proof (polygon_min_x_acc rest (pt_x p)).
    pose proof (polygon_max_x_acc rest (pt_x p)).
    pose proof (polygon_min_y_acc rest (pt_y p)).
    pose proof (polygon_max_y_acc rest (pt_y p)).
    repeat (apply andb_true_intro; split); apply Z.leb_le; lia.
  - pose proof (polygon_min_x_le rest (pt_x p0) p Hin_rest).
    pose proof (polygon_max_x_ge rest (pt_x p0) p Hin_rest).
    pose proof (polygon_min_y_le rest (pt_y p0) p Hin_rest).
    pose proof (polygon_max_y_ge rest (pt_y p0) p Hin_rest).
    repeat (apply andb_true_intro; split); apply Z.leb_le; lia.
Qed.
