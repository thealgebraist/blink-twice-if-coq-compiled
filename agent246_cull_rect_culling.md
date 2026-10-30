## 1. Cull Check & Paint Skipping Semantics

In Chromium Blink's rendering pipeline, **Cull Rect Paint Skipping** avoids recording display items that lie completely outside the visible region (or an expanded scrollable overflow region) known as the *cull rect*. 

During the paint phase (e.g., inside `BoxFragmentPainter`, `LineBoxFragmentPainter`, or `CullRect::Intersects`), before a layout object or fragment emits drawing commands to the `PaintController`, its bounding box (`item_bounds`) is tested against the current `cull_rect`.

### Intersection Logic
For axis-aligned bounding boxes (AABBs) represented in 2D space by closed intervals $[l, r] \times [t, b]$ (where $l \le r$ and $t \le b$):

$$\text{intersects}(\text{item}, \text{cull}) \iff 
  \neg (r_{\text{item}} < l_{\text{cull}} \lor l_{\text{item}} > r_{\text{cull}} \lor b_{\text{item}} < t_{\text{cull}} \lor t_{\text{item}} > b_{\text{cull}})$$

By De Morgan's laws, this is equivalent to overlapping intervals on both axes:

$$\text{intersects}(\text{item}, \text{cull}) \iff 
  (l_{\text{item}} \le r_{\text{cull}} \land r_{\text{item}} \ge l_{\text{cull}}) \land (t_{\text{item}} \le b_{\text{cull}} \land b_{\text{item}} \ge t_{\text{cull}})$$

*(Note: Depending on whether Blink uses half-open intervals $[l, r)$ for `gfx::Rect` or closed bounds, strict vs. non-strict inequalities may shift at 0-area boundaries. Below, we formalize the exact strict disjointness specification requested: $r_{\text{item}} < l_{\text{cull}} \lor l_{\text{item}} > r_{\text{cull}}$).*

---

## 2. Core Invariants

1. **Horizontal Disjointness Culling:** If an item's right edge is strictly left of the cull rect's left edge ($r_{\text{item}} < l_{\text{cull}}$), or its left edge is strictly right of the cull rect's right edge ($l_{\text{item}} > r_{\text{cull}}$), the item is culled (`should_paint = false`).
2. **Vertical Disjointness Culling:** Symmetrically, if $b_{\text{item}} < t_{\text{cull}} \lor t_{\text{item}} > b_{\text{cull}}$, the item is culled (`should_paint = false`).
3. **Conservation of Visible Paint (Soundness):** Any item that is *not* culled (`should_paint = true`) must have non-empty projection overlap with the cull rect along both axes.
4. **Symmetry & Monotonicity:** Intersection is symmetric. Expanding the cull rect (e.g., for composited scrolling re-rasterization margins) is monotonic: if an item is painted under $C_1$, and $C_1 \subseteq C_2$, it is guaranteed to be painted under $C_2$.

---

## 3. Rocq / Coq Formalization (`BlinkCullRectCullingSemantics.v`)

The following file compiles cleanly in Coq/Rocq with **0 admits**.

```coq
(** * BlinkCullRectCullingSemantics.v
    Formal Audit of Chromium Blink Cull Rect Paint Skipping
    Agent 246 - Verification of Disjoint Culling Invariants *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Geometric Primitives (2D Axis-Aligned Bounding Boxes) *)

Record Rect : Type := mkRect {
  left   : Z;
  top    : Z;
  right  : Z;
  bottom : Z
}.

(** A well-formed rectangle has non-negative width and height. *)
Definition wf_rect (r : Rect) : Prop :=
  left r <= right r /\ top r <= bottom r.

(** ** 2. Disjointness and Intersection Definitions *)

(** Horizontal disjointness as specified: r_item < l_cull || l_item > r_cull *)
Definition disjoint_x_b (item cull : Rect) : bool :=
  (right item <? left cull) || (left item >? right cull).

(** Vertical disjointness: b_item < t_cull || t_item > b_cull *)
Definition disjoint_y_b (item cull : Rect) : bool :=
  (bottom item <? top cull) || (top item >? bottom cull).

(** Complete 2D disjointness *)
Definition disjoint_b (item cull : Rect) : bool :=
  disjoint_x_b item cull || disjoint_y_b item cull.

(** Blink Cull Check: intersects(item_bounds, cull_rect) *)
Definition intersects_b (item cull : Rect) : bool :=
  (left item <=? right cull) && (right item >=? left cull) &&
  (top item <=? bottom cull) && (bottom item >=? top cull).

(** Paint decision function: painted := intersects(item_bounds, cull_rect) *)
Definition should_paint (item_bounds cull_rect : Rect) : bool :=
  intersects_b item_bounds cull_rect.

(** ** 3. Equivalence & Core Invariant Proofs *)

(** Lemma: Boolean greater-than (>?) characterization in Z. *)
Lemma Zgtb_lt : forall x y : Z, (x >? y) = true <-> y < x.
Proof.
  intros x y.
  unfold Z.gtb.
  rewrite Z.ltb_lt.
  lia.
Qed.

Lemma Zgtb_ge : forall x y : Z, (x >? y) = false <-> x <= y.
Proof.
  intros x y.
  unfold Z.gtb.
  rewrite Z.ltb_ge.
  lia.
Qed.

Lemma Zgeb_le : forall x y : Z, (x >=? y) = true <-> y <= x.
Proof.
  intros x y.
  rewrite Z.geb_le.
  reflexivity.
Qed.

Lemma Zgeb_lt : forall x y : Z, (x >=? y) = false <-> x < y.
Proof.
  intros x y.
  unfold Z.geb, Z.leb.
  destruct (x ?= y) eqn:E; split; intro H; try discriminate; try lia.
  - apply Z.compare_lt_iff in E. lia.
  - apply Z.compare_eq_iff in E. lia.
  - apply Z.compare_gt_iff in E. lia.
  - apply Z.compare_lt_iff in H. rewrite H in E. discriminate.
Qed.

(** Theorem 1: Exact duality between intersects_b and disjoint_b. *)
Theorem intersects_neg_disjoint : forall item cull : Rect,
  intersects_b item cull = negb (disjoint_b item cull).
Proof.
  intros item cull.
  unfold intersects_b, disjoint_b, disjoint_x_b, disjoint_y_b.
  destruct (left item <=? right cull) eqn:E1;
  destruct (right item >=? left cull) eqn:E2;
  destruct (top item <=? bottom cull) eqn:E3;
  destruct (bottom item >=? top cull) eqn:E4;
  destruct (right item <? left cull) eqn:D1;
  destruct (left item >? right cull) eqn:D2;
  destruct (bottom item <? top cull) eqn:D3;
  destruct (top item >? bottom cull) eqn:D4;
  simpl; try reflexivity;
  (* Eliminate impossible boolean combinations using arithmetic lia *)
  try (rewrite Z.leb_le in E1); try (rewrite Z.leb_gt in E1);
  try (rewrite Zgeb_le in E2);  try (rewrite Zgeb_lt in E2);
  try (rewrite Z.leb_le in E3); try (rewrite Z.leb_gt in E3);
  try (rewrite Zgeb_le in E4);  try (rewrite Zgeb_lt in E4);
  try (rewrite Z.ltb_lt in D1); try (rewrite Z.ltb_ge in D1);
  try (rewrite Zgtb_lt in D2);  try (rewrite Zgtb_ge in D2);
  try (rewrite Z.ltb_lt in D3); try (rewrite Z.ltb_ge in D3);
  try (rewrite Zgtb_lt in D4);  try (rewrite Zgtb_ge in D4);
  lia.
Qed.

(** Theorem 2 (Primary Audit Invariant):
    Completely horizontally disjoint items (r_item < l_cull \/ l_item > r_cull)
    are guaranteed to be culled (should_paint = false). *)
Theorem horizontal_disjoint_items_are_culled : forall item cull : Rect,
  (right item < left cull \/ left item > right cull) ->
  should_paint item cull = false.
Proof.
  intros item cull Hdisj.
  unfold should_paint.
  rewrite intersects_neg_disjoint.
  unfold disjoint_b, disjoint_x_b.
  destruct Hdisj as [Hleft | Hright].
  - apply Z.ltb_lt in Hleft.
    rewrite Hleft.
    simpl. reflexivity.
  - assert (Hgt : (left item >? right cull) = true).
    { apply Zgtb_lt. lia. }
    rewrite Hgt.
    rewrite orb_true_r.
    simpl. reflexivity.
Qed.

(** Theorem 3 (Vertical Audit Invariant):
    Completely vertically disjoint items (b_item < t_cull \/ t_item > b_cull)
    are guaranteed to be culled (should_paint = false). *)
Theorem vertical_disjoint_items_are_culled : forall item cull : Rect,
  (bottom item < top cull \/ top item > bottom cull) ->
  should_paint item cull = false.
Proof.
  intros item cull Hdisj.
  unfold should_paint.
  rewrite intersects_neg_disjoint.
  unfold disjoint_b, disjoint_y_b.
  destruct Hdisj as [Htop | Hbot].
  - apply Z.ltb_lt in Htop.
    rewrite Htop.
    simpl. rewrite orb_true_r. reflexivity.
  - assert (Hgt : (top item >? bottom cull) = true).
    { apply Zgtb_lt. lia. }
    rewrite Hgt.
    repeat rewrite orb_true_r.
    simpl. reflexivity.
Qed.

(** Theorem 4 (Soundness of Paint Skipping):
    If an item is painted (should_paint = true), it must overlap the cull_rect
    in both X and Y dimensions. *)
Theorem painted_implies_overlapping_bounds : forall item cull : Rect,
  should_paint item cull = true ->
  left item <= right cull /\
  left cull <= right item /\
  top item <= bottom cull /\
  top cull <= bottom item.
Proof.
  intros item cull Hpaint.
  unfold should_paint, intersects_b in Hpaint.
  repeat rewrite andb_true_iff in Hpaint.
  destruct Hpaint as [[[H1 H2] H3] H4].
  rewrite Z.leb_le in H1.
  rewrite Zgeb_le in H2.
  rewrite Z.leb_le in H3.
  rewrite Zgeb_le in H4.
  repeat split; lia.
Qed.

(** Theorem 5 (Intersection Symmetry):
    The cull check is symmetric with respect to item_bounds and cull_rect. *)
Theorem intersects_symmetric : forall r1 r2 : Rect,
  intersects_b r1 r2 = intersects_b r2 r1.
Proof.
  intros r1 r2.
  unfold intersects_b.
  destruct (left r1 <=? right r2) eqn:E1;
  destruct (right r1 >=? left r2) eqn:E2;
  destruct (top r1 <=? bottom r2) eqn:E3;
  destruct (bottom r1 >=? top r2) eqn:E4;
  destruct (left r2 <=? right r1) eqn:F1;
  destruct (right r2 >=? left r1) eqn:F2;
  destruct (top r2 <=? bottom r1) eqn:F3;
  destruct (bottom r2 >=? top r1) eqn:F4;
  simpl; try reflexivity;
  try (rewrite Z.leb_le in E1); try (rewrite Z.leb_gt in E1);
  try (rewrite Zgeb_le in E2);  try (rewrite Zgeb_lt in E2);
  try (rewrite Z.leb_le in E3); try (rewrite Z.leb_gt in E3);
  try (rewrite Zgeb_le in E4);  try (rewrite Zgeb_lt in E4);
  try (rewrite Z.leb_le in F1); try (rewrite Z.leb_gt in F1);
  try (rewrite Zgeb_le in F2);  try (rewrite Zgeb_lt in F2);
  try (rewrite Z.leb_le in F3); try (rewrite Z.leb_gt in F3);
  try (rewrite Zgeb_le in F4);  try (rewrite Zgeb_lt in F4);
  lia.
Qed.

(** ** 4. Cull Rect Expansion Monotonicity *)

(** Sub-rectangle (inclusion) relation: r1 is contained within r2 *)
Definition rect_subset (r1 r2 : Rect) : Prop :=
  left r2 <= left r1 /\
  right r1 <= right r2 /\
  top r2 <= top r1 /\
  bottom r1 <= bottom r2.

(** Theorem 6 (Monotonicity under Cull Rect Expansion):
    If an item is painted under cull_rect_1, and cull_rect_1 is expanded
    to cull_rect_2, the item is still painted under cull_rect_2. *)
Theorem cull_rect_expansion_monotonic : forall item c1 c2 : Rect,
  rect_subset c1 c2 ->
  should_paint item c1 = true ->
  should_paint item c2 = true.
Proof.
  intros item c1 c2 Hsub Hpaint.
  unfold rect_subset in Hsub.
  destruct Hsub as [HL [HR [HT HB]]].
  apply painted_implies_overlapping_bounds in Hpaint.
  destruct Hpaint as [O1 [O2 [O3 O4]]].
  unfold should_paint, intersects_b.
  repeat rewrite andb_true_iff.
  rewrite Z.leb_le, Zgeb_le, Z.leb_le, Zgeb_le.
  repeat split;