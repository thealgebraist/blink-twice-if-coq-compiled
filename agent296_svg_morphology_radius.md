### Agent 296 Audit Report: Chromium Blink `feMorphology` Dilate and Erode

In Chromium Blink (`third_party/blink/renderer/platform/graphics/filters/fe_morphology.cc` and Skia's `SkMorphologyImageFilter`), the `feMorphology` SVG filter effect computes the morphological dilation (maximum) or erosion (minimum) of the input image channels over a rectangular structuring element defined by radii $(r_x, r_y)$.

#### 1. Dilate Monotonicity
For a 1D slice (easily generalized to 2D via separability, which Blink/Skia utilizes), the `dilate` operator over an input signal $f : \mathbb{N} \to \mathbb{N}$ at position $x$ with radius $r \in \mathbb{N}$ is defined as:
$$\text{dilate}(f, x, r) = \max_{\max(0, x-r) \le i \le x+r} f(i)$$

* **Zero Radius Identity:** When $r = 0$, the window of evaluation collapses to the single point $[x, x]$. The maximum over the singleton $\{f(x)\}$ is $f(x)$. Thus, $\text{dilate}(f, x, 0) = f(x)$.
* **Center Inclusion Bound:** For any $r \ge 0$, the center coordinate $x$ is always included in the sampling window $[\max(0, x-r), x+r]$. Since the supremum of a set is always greater than or equal to any element within that set, $\text{dilate}(f, x, r) \ge f(x)$.
* **Radius Monotonicity:** If $r_1 \le r_2$, the window $[\max(0, x-r_1), x+r_1]$ is a subset of $[\max(0, x-r_2), x+r_2]$, yielding $\text{dilate}(f, x, r_1) \le \text{dilate}(f, x, r_2)$.

#### 2. Erode Monotonicity
Similarly, the `erode` operator is defined as the minimum over the structuring window:
$$\text{erode}(f, x, r) = \min_{\max(0, x-r) \le i \le x+r} f(i)$$

* **Zero Radius Identity:** When $r = 0$, the window collapses to $\{f(x)\}$, so $\text{erode}(f, x, 0) = f(x)$.
* **Center Inclusion Bound:** Because $x$ is always in the sampling window for any $r \ge 0$, the minimum over the window cannot exceed the value at $x$ itself. Thus, $\text{erode}(f, x, r) \le f(x)$.
* **Radius Monotonicity:** Expanding the radius $r_1 \le r_2$ introduces more elements into the minimum accumulator, ensuring $\text{erode}(f, x, r_2) \le \text{erode}(f, x, r_1)$.

---

#### 3. Rocq / Coq Formalization (`BlinkSVGMorphologyRadiusSemantics.v`)

Below is the complete, self-contained Rocq/Coq formalization proving the zero-radius identities, center bounds, and general radius monotonicity for both `dilate` and `erode` with **0 admits**.

```coq
(** * BlinkSVGMorphologyRadiusSemantics.v
    Formal audit of Chromium Blink feMorphology (Dilate / Erode) radius semantics.
    Agent 296. *)

From Coq Require Import Arith PeanoNat List Lia.
Import ListNotations.

Section MorphologySemantics.

  (** We model a 1D image channel (or separable pass) as a function from
      pixel coordinate (nat) to channel intensity (nat). *)
   Variable img : nat -> nat.

  (** Window indices around coordinate [x] with radius [r].
      Clamped at 0 on the left, matching boundary-clamped index generation. *)
  Definition window (x r : nat) : list nat :=
    seq (x - r) (r + 1 + (x - (x - r))).

  Lemma in_window_iff : forall x r i,
    In i (window x r) <-> (x - r <= i <= x + r).
  Proof.
    intros x r i.
    unfold window.
    rewrite in_seq.
    lia.
  Qed.

  Lemma center_in_window : forall x r,
    In x (window x r).
  Proof.
    intros x r.
     rewrite in_window_iff.
    lia.
  Qed.

  Lemma window_zero : forall x,
    window x 0 = [x].
  Proof.
    intros x.
    unfold window.
    replace (x - 0) with x by lia.
    replace (0 + 1 + (x - x)) with 1 by lia.
    simpl. reflexivity.
  Qed.

  (** ** Dilate Definition & Lemmas *)

  (** Fold-based maximum over a list of indices, seeded with the center pixel [img x]. *)
  Definition max_list (default : nat) (l : list nat) : nat :=
    fold_right (fun i acc => Nat.max (img i) acc) default l.

  Definition dilate (x r : nat) : nat :=
    max_list (img x) (window x r).

  Lemma max_list_ge_default : forall d l,
    d <= max_list d l.
  Proof.
    intros d l.
    induction l as [|h t IH]; simpl.
    - lia.
    - lia.
  Qed.

  Lemma max_list_in_ge : forall d l i,
    In i l -> img i <= max_list d l.
  Proof.
    intros d l i HIn.
    induction l as [|h t IH]; simpl in *.
    - contradiction.
    - destruct HIn as [Heq | HIn].
      + subst h. lia.
      + specialize (IH HIn). lia.
  Qed.

  Lemma max_list_lub : forall d l bound,
    d <= bound ->
    (forall i, In i l -> img i <= bound) ->
    max_list d l <= bound.
  Proof.
    intros d l bound Hd HIn.
    induction l as [|h t IH]; simpl.
    - exact Hd.
    - apply Nat.max_lub.
      + apply HIn. simpl. left. reflexivity.
      + apply IH. intros i Hi. apply HIn. simpl. right. exact Hi.
  Qed.

  (** Theorem 1a: dilate(val, 0) = val *)
  Theorem dilate_radius_0 : forall x,
    dilate x 0 = img x.
  Proof.
    intros x.
    unfold dilate.
    rewrite window_zero.
    simpl.
     apply Nat.max_id.
  Qed.

  (** Theorem 1b: dilate(val, r) >= val *)
  Theorem dilate_ge_val : forall x r,
    img x <= dilate x r.
  Proof.
    intros x r.
    unfold dilate.
    apply max_list_ge_default.
  Qed.

  (** Theorem 1c: General Dilate Radius Monotonicity *)
  Theorem dilate_monotonic_radius : forall x r1 r2,
    r1 <= r2 -> dilate x r1 <= dilate x r2.
  Proof.
    intros x r1 r2 Hr.
    unfold dilate.
    apply max_list_lub.
    - apply max_list_ge_default.
    - intros i Hi.
      apply max_list_in_ge.
      rewrite in_window_iff in *.
      lia.
  Qed.

  (** ** Erode Definition & Lemmas *)

  (** Fold-based minimum over a list of indices, seeded with the center pixel [img x]. *)
  Definition min_list (default : nat) (l : list nat) : nat :=
    fold_right (fun i acc => Nat.min (img i) acc) default l.

  Definition erode (x r : nat) : nat :=
    min_list (img x) (window x r).

  Lemma min_list_le_default : forall d l,
    min_list d l <= d.
  Proof.
    intros d l.
    induction l as [|h t IH]; simpl.
    - lia.
    - lia.
  Qed.

  Lemma min_list_in_le : forall d l i,
    In i l -> min_list d l <= img i.
  Proof.
    intros d l i HIn.
    induction l as [|h t IH]; simpl in *.
    - contradiction.
    - destruct HIn as [Heq | HIn].
      + subst h. lia.
      + specialize (IH HIn). lia.
  Qed.

  Lemma min_list_glb : forall d l bound,
    bound <= d ->
    (forall i, In i l -> bound <= img i) ->
    bound <= min_list d l.
  Proof.
    intros d l bound Hd HIn.
    induction l as [|h t IH]; simpl.
    - exact Hd.
    - apply Nat.min_glb.
      + apply HIn. simpl. left. reflexivity.
      + apply IH. intros i Hi. apply HIn. simpl. right. exact Hi.
  Qed.

  (** Theorem 2a: erode(val, 0) = val *)
  Theorem erode_radius_0 : forall x,
    erode x 0 = img x.
  Proof.
    intros x.
    unfold erode.
    rewrite window_zero.
    simpl.
    apply Nat.min_id.
  Qed.

  (** Theorem 2b: erode(val, r) <= val *)
  Theorem erode_le_val : forall x r,
    erode x r <= img x.
  Proof.
    intros x r.
    unfold erode.
    apply min_list_le_default.
  Qed.

  (** Theorem 2c: General Erode Radius Monotonicity *)
  Theorem erode_monotonic_radius : forall x r1 r2,
    r1 <= r2 -> erode x r2 <= erode x r1.
  Proof.
    intros x r1 r2 Hr.
    unfold erode.
    apply min_list_glb.
    - apply min_list_in_le.
      apply center_in_window.
    - intros i Hi.
      apply min_list_in_le.
      rewrite in_window_iff in *.
      lia.
  Qed.

  (** Corollary: Ordering between Erode, Identity, and Dilate *)
  Corollary erode_le_dilate : forall x r,
    erode x r <= dilate x r.
  Proof.
    intros x r.
    pose proof (erode_le_val x r).
    pose proof (dilate_ge_val x r).
    lia.
  Qed.

End MorphologySemantics.
```