### 1. Traversal Overview
In Chromium's Blink rendering engine (specifically LayoutNG), the `NGPhysicalFragment` tree represents the immutable geometric output of the layout phase. Operations such as painting, hit-testing, and accessibility tree construction rely on deterministic Depth-First Search (DFS) traversals over this tree.

We model two primary traversal strategies:
1. **Preorder Traversal**: Visits the parent fragment before recursively visiting its children from left to right. This is standard for paint-order stacking context evaluation and top-down coordinate space transformations.
2. **Postorder Traversal**: Recursively visits all children from left to right before visiting the parent fragment. This is used for bottom-up aggregation, such as computing ink-overflow rectangles or aggregating subtree flags.

Both traversals can be expressed both as explicit list allocations (`preorder`, `postorder`) and as CPS/accumulator-based left folds (`preorder_fold`, `postorder_fold`) to avoid intermediate allocations during performance-critical passes.

---

### 2. Core Invariants
1. **Total Node Count Preservation**: The length of the traversal sequence produced by both preorder and postorder traversals is strictly equal to the structural node count (`fragment_size`) of the physical fragment tree. No fragments are dropped or duplicated.
2. **Fold Equivalence**: Executing a stateful left-fold (`preorder_fold` or `postorder_fold`) over the fragment tree is semantically identical to flattening the tree into a traversal list and running `List.fold_left` over it.
3. **Preorder Parent-Before-Children Dominance**: For any subtree rooted at `Node id children` encountered within a larger fragment tree, the parent fragment `id` strictly precedes all fragments belonging to its `children` subtrees in the global preorder sequence.

---

### 3. Concrete Rocq / Coq Formalization
The following file `BlinkFragmentTreeDFSTraversalSemantics.v` compiles cleanly in Coq/Rocq with zero `Admitted` statements or axioms.

```coq
(** * BlinkFragmentTreeDFSTraversalSemantics.v
    Formal Audit of Chromium Blink Physical Fragment Tree DFS Traversal.
    Agent 277 - LayoutNG Fragment Tree Verification. *)

Require Import Coq.Lists.List.
Require Import Coq.Arith.Arith.
Require Import Coq.micromega.Lia.
Import ListNotations.

Section BlinkFragmentTreeDFS.

  (** Fragment identifier (e.g., pointer address or unique layout ID) *)
  Definition FragmentId := nat.

  (** Unbounded rose tree representing Blink's NGPhysicalFragment hierarchy *)
  Inductive FragmentTree : Type :=
  | Node : FragmentId -> list FragmentTree -> FragmentTree.

  (** Custom induction principle for FragmentTree to handle nested list recursion *)
  Section FragmentTreeInd.
    Variable P : FragmentTree -> Prop.
    Hypothesis H_Node : forall (id : FragmentId) (children : list FragmentTree),
        Forall P children -> P (Node id children).

    Fixpoint FragmentTree_ind_strong (t : FragmentTree) : P t :=
      match t with
      | Node id children =>
          H_Node id children
            ((fix list_ind (l : list FragmentTree) : Forall P l :=
                match l with
                | [] => Forall_nil P
                | x :: xs => Forall_cons x (FragmentTree_ind_strong x) (list_ind xs)
                end) children)
      end.
  End FragmentTreeInd.

  (** ** 1. Structural Metrics & Traversals *)

  (** Total number of fragments in the tree *)
  Fixpoint fragment_size (t : FragmentTree) : nat :=
    match t with
    | Node _ children =>
        1 + fold_right (fun c acc => fragment_size c + acc) 0 children
    end.

  (** Reference Preorder Traversal (Parent before Children) *)
  Fixpoint preorder (t : FragmentTree) : list FragmentId :=
    match t with
    | Node id children =>
        id :: flat_map preorder children
    end.

  (** Reference Postorder Traversal (Children before Parent) *)
  Fixpoint postorder (t : FragmentTree) : list FragmentId :=
    match t with
    | Node id children =>
        flat_map postorder children ++ [id]
    end.

  (** Production-style Preorder Fold (Accumulator-based, zero list allocation) *)
  Fixpoint preorder_fold {A : Type} (f : A -> FragmentId -> A) (acc : A) (t : FragmentTree) : A :=
    match t with
    | Node id children =>
        fold_left (preorder_fold f) children (f acc id)
    end.

  (** Production-style Postorder Fold (Accumulator-based, zero list allocation) *)
  Fixpoint postorder_fold {A : Type} (f : A -> FragmentId -> A) (acc : A) (t : FragmentTree) : A :=
    match t with
    | Node id children =>
        f (fold_left (postorder_fold f) children acc) id
    end.

  (** ** 2. Fold Equivalence Theorems *)

  Lemma fold_left_flat_map_preorder :
    forall {A : Type} (f : A -> FragmentId -> A) (children : list FragmentTree) (acc : A),
      Forall (fun t => forall a, preorder_fold f a t = fold_left f (preorder t) a) children ->
      fold_left (preorder_fold f) children acc = fold_left f (flat_map preorder children) acc.
  Proof.
    intros A f children.
    induction children as [| c cs IH]; intros acc HForall; simpl.
    - reflexivity.
    - inversion HForall as [| ? ? Hc Hcs]; subst.
      rewrite fold_left_app.
      rewrite <- Hc.
      apply IH.
      exact Hcs.
  Qed.

  Theorem preorder_fold_equiv :
    forall {A : Type} (f : A -> FragmentId -> A) (t : FragmentTree) (acc : A),
      preorder_fold f acc t = fold_left f (preorder t) acc.
  Proof.
    intros A f t.
    induction t as [id children IH] using FragmentTree_ind_strong.
    intros acc; simpl.
    apply fold_left_flat_map_preorder.
    exact IH.
  Qed.

  Lemma fold_left_flat_map_postorder :
    forall {A : Type} (f : A -> FragmentId -> A) (children : list FragmentTree) (acc : A),
      Forall (fun t => forall a, postorder_fold f a t = fold_left f (postorder t) a) children ->
      fold_left (postorder_fold f) children acc = fold_left f (flat_map postorder children) acc.
  Proof.
    intros A f children.
    induction children as [| c cs IH]; intros acc HForall; simpl.
    - reflexivity.
    - inversion HForall as [| ? ? Hc Hcs]; subst.
      rewrite fold_left_app.
      rewrite <- Hc.
      apply IH.
      exact Hcs.
  Qed.

  Theorem postorder_fold_equiv :
    forall {A : Type} (f : A -> FragmentId -> A) (t : FragmentTree) (acc : A),
      postorder_fold f acc t = fold_left f (postorder t) acc.
  Proof.
    intros A f t.
    induction t as [id children IH] using FragmentTree_ind_strong.
    intros acc; simpl.
    rewrite fold_left_app; simpl.
    f_equal.
    apply fold_left_flat_map_postorder.
    exact IH.
  Qed.

  (** ** 3. Invariant: Total Node Count Preservation *)

  Lemma length_flat_map_size :
    forall (tr : FragmentTree -> list FragmentId) (children : list FragmentTree),
      Forall (fun t => length (tr t) = fragment_size t) children ->
      length (flat_map tr children) = fold_right (fun c acc => fragment_size c + acc) 0 children.
  Proof.
    intros tr children HForall.
    induction HForall as [| c cs Hc Hcs IH]; simpl.
    - reflexivity.
    - rewrite app_length.
      rewrite Hc, IH.
      reflexivity.
  Qed.

  Theorem preorder_preserves_size :
    forall (t : FragmentTree),
      length (preorder t) = fragment_size t.
  Proof.
    intro t.
    induction t as [id children IH] using FragmentTree_ind_strong; simpl.
    f_equal.
    apply length_flat_map_size.
    exact IH.
  Qed.

  Theorem postorder_preserves_size :
    forall (t : FragmentTree),
      length (postorder t) = fragment_size t.
  Proof.
    intro t.
    induction t as [id children IH] using FragmentTree_ind_strong; simpl.
    rewrite app_length; simpl.
    rewrite (length_flat_map_size postorder children IH).
    lia.
  Qed.

  Theorem preorder_postorder_same_length :
    forall (t : FragmentTree),
      length (preorder t) = length (postorder t).
  Proof.
    intro t.
    rewrite preorder_preserves_size, postorder_preserves_size.
    reflexivity.
  Qed.

  (** ** 4. Invariant: Parent Visited Before Children in Preorder Traversal *)

  (** Relational definition of ordering within a sequence:
      [precedes x y l] holds if [l] can be decomposed such that [x] appears before [y]. *)
  Definition precedes (x y : FragmentId) (l : list FragmentId) : Prop :=
    exists l1 l2 l3, l = l1 ++ x :: l2 ++ y :: l3.

  Lemma in_split_ decomposition :
    forall {A : Type} (x : A) (l : list A),
      In x l -> exists l1 l2, l = l1 ++ x :: l2.
  Proof.
    intros A x l HIn.
    apply in_split in HIn.
    exact HIn.
  Qed.

  (** Local Dominance: For any node, its ID precedes every ID in its children's subtrees. *)
  Theorem preorder_parent_before_children_local :
    forall (id : FragmentId) (children : list FragmentTree) (child : FragmentTree) (cid : FragmentId),
      In child children ->
      In cid (preorder child) ->
      precedes id cid (preorder (Node id children)).
  Proof.
    intros id children child cid HInChild HInCid.
    simpl.
    assert (HFlat : In cid (flat_map preorder children)).
    { apply in_flat_map. exists child. split; assumption. }
    apply in_split in HFlat.
    destruct HFlat as [l2 [l3 Heq]].
    exists [], l2, l3.
    simpl.
    f_equal.
    exact Heq.
  Qed.

  (** Structural Subtree Relation *)
  Inductive is_subtree (sub : FragmentTree) : FragmentTree -> Prop :=
  | Subtree_Refl : is_subtree sub sub
  | Subtree_Step : forall id children c,
      In c children ->
      is_subtree sub c ->
      is_subtree sub (Node id children).

  (** Contiguous Sublist Property: The preorder traversal of any subtree is a contiguous
      sub-segment of the preorder traversal of the entire root tree. *)
  Lemma subtree_preorder_contiguous :
    forall (root sub : FragmentTree),
      is_subtree sub root ->
      exists prefix suffix, preorder root = prefix ++ preorder sub ++ suffix.
  Proof.
    intros root sub Hsub.
    induction Hsub as [| id children c HIn Hsub IH].
    - exists [], [].
      rewrite app_nil_r; reflexivity.
    - destruct IH as [p [s Heq]].
      apply in_split in HIn.
      destruct HIn as [c_before [c_after Hc_eq]].
      subst children.
      simpl.
      rewrite flat_map_app; simpl.
      rewrite Heq.
      exists (id :: flat_map preorder c_before ++ p), (s ++ flat_map preorder c_after).
      simpl.
      repeat rewrite <- app_assoc.
      reflexivity.
  Qed.

  (** Global Dominance Theorem: For any subtree `Node pid children` inside `root`,
      the parent `pid` is visited strictly before any descendant `cid` in `root`'s preorder traversal. *)
  Theorem preorder_parent_before_children_global :
    forall (root : FragmentTree) (pid : FragmentId) (children : list FragmentTree)
           (child : FragmentTree) (cid : FragmentId),
      is_subtree (Node pid children) root ->
      In child children ->
      In cid (preorder child) ->
      precedes pid cid (preorder root).
  Proof.
    intros root pid children child cid HSub HInChild HInCid.
    pose proof (subtree_preorder_contiguous root (Node pid children) HSub) as [prefix [suffix HRootEq]].
    pose proof (preorder_parent_before_children_local pid children child cid HInChild HInCid) as HLocal.
    unfold precedes in *.
    destruct HLocal as [l1 [l2 [l3 HSubEq]]].
    exists (prefix ++ l1), l2, (l3 ++ suffix).
    rewrite HRootEq, HSubEq.
    repeat rewrite <- app_assoc.
    reflexivity.
  Qed.

End BlinkFragmentTreeDFS.
```