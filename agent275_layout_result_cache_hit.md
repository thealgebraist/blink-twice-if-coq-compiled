Here is the formalization of Chromium Blink's Layout Result Cache Hit Semantics in Rocq (Coq), complete with concrete definitions, invariance theorems, and zero admits.

### Overview of Audit & Formalization

1. **Cache Lookup Semantics**: In Blink's LayoutNG (`NGLayoutResult` caching), a `LayoutBox` caches one or more layout results keyed by the input `NGConstraintSpace`. When a layout pass occurs, `CachedLayoutResult` checks if the new constraint space is compatible with the cached constraint space and that the node is not marked dirty (`NeedsLayout`). If compatible, a cache hit occurs, avoiding a fresh execution of the layout algorithm.
2. **Invariants**: A valid cache hit guarantees that the physical fragment (`NGPhysicalFragment`) dimensions (`Size`) and child offsets (`Offset`) inside the `NGLayoutResult` are strictly identical to what a fresh invocation of the layout algorithm would produce.

---

### `BlinkLayoutResultCacheHitSemantics.v`

```coq
(** * BlinkLayoutResultCacheHitSemantics.v
    Formal Audit by Agent 275: Chromium Blink Layout Result Cache Invariance.
    Verifies that cache hits in Blink's LayoutNG preserve physical fragment
    dimensions and offsets identically compared to fresh layout executions.
    Contains 0 admits. *)

From Coq Require Import Arith.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

(** ** 1. Geometric Primitives (LayoutUnit abstracted as nat) *)

Record PhysicalSize : Type := mkSize {
  width : nat;
  height : nat
}.

Definition PhysicalSize_eqb (s1 s2 : PhysicalSize) : bool :=
  (width s1 =? width s2) && (height s1 =? height s2).

Lemma PhysicalSize_eqb_eq : forall s1 s2,
  PhysicalSize_eqb s1 s2 = true <-> s1 = s2.
Proof.
  intros [w1 h1] [w2 h2]. unfold PhysicalSize_eqb. simpl.
  rewrite andb_true_iff. repeat rewrite Nat.eqb_eq.
  split; [intros [-> ->]; reflexivity | intros H; injection H; auto].
Qed.

Record PhysicalOffset : Type := mkOffset {
  left_offset : nat;
  top_offset : nat
}.

Definition PhysicalOffset_eqb (o1 o2 : PhysicalOffset) : bool :=
  (left_offset o1 =? left_offset o2) && (top_offset o1 =? top_offset o2).

Lemma PhysicalOffset_eqb_eq : forall o1 o2,
  PhysicalOffset_eqb o1 o2 = true <-> o1 = o2.
Proof.
  intros [l1 t1] [l2 t2]. unfold PhysicalOffset_eqb. simpl.
  rewrite andb_true_iff. repeat rewrite Nat.eqb_eq.
  split; [intros [-> ->]; reflexivity | intros H; injection H; auto].
Qed.

(** ** 2. Blink LayoutNG Data Structures *)

(** Represents NGConstraintSpace: inputs to a layout algorithm *)
Record ConstraintSpace : Type := mkSpace {
  available_size : PhysicalSize;
  percentage_resolution_size : PhysicalSize;
  is_fixed_inline : bool;
  is_fixed_block : bool
}.

Definition ConstraintSpace_eqb (cs1 cs2 : ConstraintSpace) : bool :=
  PhysicalSize_eqb (available_size cs1) (available_size cs2) &&
  PhysicalSize_eqb (percentage_resolution_size cs1) (percentage_resolution_size cs2) &&
  Bool.eqb (is_fixed_inline cs1) (is_fixed_inline cs2) &&
  Bool.eqb (is_fixed_block cs1) (is_fixed_block cs2).

Lemma ConstraintSpace_eqb_eq : forall cs1 cs2,
  ConstraintSpace_eqb cs1 cs2 = true <-> cs1 = cs2.
Proof.
  intros [a1 p1 i1 b1] [a2 p2 i2 b2].
  unfold ConstraintSpace_eqb. simpl.
  repeat rewrite andb_true_iff.
  rewrite PhysicalSize_eqb_eq, PhysicalSize_eqb_eq.
  rewrite Bool.eqb_true_iff, Bool.eqb_true_iff.
  split.
  - intros [[[-> ->] ->] ->]. reflexivity.
  - intros H. injection H as -> -> -> ->. repeat split; reflexivity.
Qed.

(** Represents NGPhysicalFragment: the immutable geometric output *)
Record PhysicalFragment : Type := mkFragment {
  fragment_size : PhysicalSize;
  children_offsets : list PhysicalOffset
}.

(** Represents NGLayoutResult: wraps the fragment and the space that generated it *)
Record LayoutResult : Type := mkResult {
  space_used : ConstraintSpace;
  physical_fragment : PhysicalFragment;
  intrinsic_block_size : nat
}.

(** Represents Geometry extraction for verification *)
Record Geometry : Type := mkGeometry {
  geom_size : PhysicalSize;
  geom_offsets : list PhysicalOffset
}.

Definition extract_geometry (res : LayoutResult) : Geometry :=
  mkGeometry 
    (fragment_size (physical_fragment res))
    (children_offsets (physical_fragment res)).

(** Represents LayoutBox / NGBlockNode with its single-slot cache *)
Record LayoutNode : Type := mkNode {
  node_id : nat;
  style_width : nat;
  style_height : nat;
  child_count : nat;
  is_dirty : bool; (* Corresponds to NeedsLayout() in Blink *)
  cached_result : option LayoutResult
}.

(** ** 3. Fresh Layout Algorithm & Cache Lookup Semantics *)

(** Helper to generate deterministic child offsets based on style and space *)
Fixpoint compute_child_offsets (count : nat) (step_x step_y : nat) : list PhysicalOffset :=
  match count with
  | 0 => []
  | S c => mkOffset (c * step_x) (c * step_y) :: compute_child_offsets c step_x step_y
  end.

(** Fresh layout execution (e.g., NGBlockLayoutAlgorithm::Layout) *)
Definition compute_fresh_layout (space : ConstraintSpace) (node : LayoutNode) : LayoutResult :=
  let final_w := if is_fixed_inline space 
                 then width (available_size space) 
                 else Nat.min (width (available_size space)) (style_width node) in
  let final_h := if is_fixed_block space 
                 then height (available_size space) 
                 else Nat.min (height (available_size space)) (style_height node) in
  let sz := mkSize final_w final_h in
  let offsets := compute_child_offsets (child_count node) 
                                       (width (percentage_resolution_size space)) 
                                       (height (percentage_resolution_size space)) in
  let frag := mkFragment sz offsets in
  mkResult space frag final_h.

(** Blink's LayoutBox::CachedLayoutResult lookup logic *)
Definition lookup (space : ConstraintSpace) (node : LayoutNode) : option LayoutResult :=
  if is_dirty node then None
  else match cached_result node with
       | None => None
       | Some res => 
           if ConstraintSpace_eqb space (space_used res) 
           then Some res 
           else None
       end.

(** ** 4. Cache Invariant Definitions *)

(** A LayoutNode satisfies the Blink Cache Invariant if, whenever it is not
    marked dirty (`is_dirty = false`) and holds a cached result, that result
    is identical to a fresh layout computation for the stored ConstraintSpace. *)
Definition NodeCacheValid (node : LayoutNode) : Prop :=
  is_dirty node = false ->
  forall res, cached_result node = Some res ->
  res = compute_fresh_layout (space_used res) node.

(** ** 5. Main Invariance Theorems *)

(** Theorem 1: Fundamental Cache Hit Correctness.
    If the cache is valid and lookup hits, the cached result is strictly equal
    to a freshly computed layout result. *)
Theorem lookup_hit_equals_fresh :
  forall (space : ConstraintSpace) (node : LayoutNode) (cached_res : LayoutResult),
    NodeCacheValid node ->
    lookup space node = Some cached_res ->
    cached_res = compute_fresh_layout space node.
Proof.
  intros space node cached_res Hvalid Hlookup.
  unfold lookup in Hlookup.
  destruct (is_dirty node) eqn:Hdirty.
  - discriminate Hlookup.
  - destruct (cached_result node) as [res|] eqn:Hcache.
    + destruct (ConstraintSpace_eqb space (space_used res)) eqn:Hspace.
      * injection Hlookup as Heq. subst res.
        apply ConstraintSpace_eqb_eq in Hspace.
        rewrite Hspace.
        apply Hvalid; [reflexivity | exact Hcache].
      * discriminate Hlookup.
    + discriminate Hlookup.
Qed.

(** Theorem 2: Geometry Invariance (Detail 1).
    lookup(space, node) = Some cached_res -> geometry(cached_res) == geometry(fresh_res). *)
Theorem cache_hit_geometry_invariance :
  forall (space : ConstraintSpace) (node : LayoutNode) (cached_res : LayoutResult),
    NodeCacheValid node ->
    lookup space node = Some cached_res ->
    extract_geometry cached_res = extract_geometry (compute_fresh_layout space node).
Proof.
  intros space node cached_res Hvalid Hlookup.
  pose proof (lookup_hit_equals_fresh space node cached_res Hvalid Hlookup) as Heq.
  rewrite Heq.
  reflexivity.
Qed.

(** Theorem 3: Physical Fragment Dimensions and Offsets Preservation (Detail 2).
    Cache hits preserve physical fragment dimensions and offsets identically. *)
Theorem cache_hit_preserves_dimensions_and_offsets :
  forall (space : ConstraintSpace) (node : LayoutNode) (cached_res : LayoutResult),
    NodeCacheValid node ->
    lookup space node = Some cached_res ->
    let fresh_res := compute_fresh_layout space node in
    fragment_size (physical_fragment cached_res) = fragment_size (physical_fragment fresh_res) /\
    children_offsets (physical_fragment cached_res) = children_offsets (physical_fragment fresh_res).
Proof.
  intros space node cached_res Hvalid Hlookup fresh_res.
  pose proof (cache_hit_geometry_invariance space node cached_res Hvalid Hlookup) as Hgeom.
  unfold extract_geometry in Hgeom.
  injection Hgeom as Hsize Hoffsets.
   subst fresh_res.
  split; [exact Hsize | exact Hoffsets].
Qed.

(** ** 6. Cache Lifecycle Preservation (Updating and Invalidating Cache) *)

(** Transitions a node by storing a freshly computed layout result *)
Definition update_node_cache (space : ConstraintSpace) (node : LayoutNode) : LayoutNode :=
  let fresh := compute_fresh_layout space node in
  mkNode (node_id node) 
         (style_width node) 
         (style_height node) 
         (child_count node) 
         false (* Clears dirty bit upon layout completion *)
         (Some fresh).

(** Marks a node dirty when DOM/Style mutates (e.g., LayoutObject::SetNeedsLayout) *)
Definition mark_node_dirty (node : LayoutNode) : LayoutNode :=
  mkNode (node_id node)
         (style_width node)
         (style_height node)
         (child_count node)
         true (* Sets dirty bit *)
         (cached_result node).

(** Lemma: Updating the cache with a fresh layout preserves `NodeCacheValid`. *)
Theorem update_cache_preserves_validity :
  forall (space : ConstraintSpace) (node : LayoutNode),
    NodeCacheValid (update_node_cache space node).
Proof.
  intros space node.
  unfold NodeCacheValid, update_node_cache. simpl.
  intros _ res Hsom.
  injection Hsom as Heq.
  subst res.
  unfold compute_fresh_layout. simpl.
  reflexivity.
Qed.

(** Lemma: Marking a node dirty upon style mutation trivially preserves `NodeCacheValid`. *)
Theorem mark_dirty_preserves_validity :
  forall (node : LayoutNode),
    NodeCacheValid (mark_node_dirty node).
Proof.
  intros node.
  unfold NodeCacheValid, mark_node_dirty. simpl.
  intros Hfalse.
  discriminate Hfalse.
Qed.
```