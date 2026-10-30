### 1. Fragment Assembly Architecture in Chromium Blink

In Chromium Blink’s LayoutNG engine (`NGTableLayoutAlgorithm`), a CSS table is decomposed into two primary formatting contexts: the **Table Wrapper Box** and the **Table Grid Box**. 

The table wrapper box establishes a block formatting context that encapsulates both the `<table>` grid itself and any associated `<caption>` elements. During the fragment tree assembly phase (`NGBoxFragmentBuilder`), the layout algorithm computes inline and block sizes for all sub-elements and places their physical fragments into the wrapper fragment in a strictly ordered vertical sequence:

1. **Top Captions**: Any `<caption>` elements with `caption-side: top` (the default) are laid out first. Their block offsets advance the current `block_offset` cursor downward (including collapsed or uncollapsed margins depending on the specification details, modeled here as non-negative spacing adjustments).
2. **Table Grid Fragment**: Once all top captions are positioned, the core table grid (containing column groups, row groups, rows, and cells) is laid out and added as a single child fragment at the current `block_offset`.
3. **Bottom Captions**: Finally, any `<caption>` elements with `caption-side: bottom` are laid out sequentially below the table grid fragment.

The wrapper fragment’s final intrinsic block size is the sum of the block sizes and intervening spacings of all these children, plus the wrapper's own border and padding.

---

### 2. Vertical Coordinate Advancement Invariants

To guarantee absence of unintended fragment overlap and ensure deterministic visual rendering during painting and hit-testing, the fragment assembly phase maintains strict monotonicity invariants along the block progression axis:

* **Non-Negativity of Sizes**: Every child box fragment $f$ has a non-negative block extent: $\text{block\_size}(f) \ge 0$. Spacing offsets (margins/paddings) before and after fragments during standard block progression are non-negative: $\text{spacing} \ge 0$.
* **Intra-Group Monotonicity**: For any two consecutive captions $c_i, c_{i+1}$ in the same group (top or bottom), $\text{bottom}(c_i) \le \text{top}(c_{i+1})$.
* **Top Caption to Grid Boundary**: For every top caption $c_{\text{top}}$, its bottom edge must not exceed the top edge of the table grid fragment:
  $$\text{top}(c_{\text{top}}) + \text{block\_size}(c_{\text{top}}) \le \text{top}(\text{grid})$$
* **Grid to Bottom Caption Boundary**: For every bottom caption $c_{\text{bot}}$, the bottom edge of the table grid fragment must not exceed the top edge of $c_{\text{bot}}$:
  $$\text{top}(\text{grid}) + \text{block\_size}(\text{grid}) \le \text{top}(c_{\text{bot}})$$

---

### 3. Formalization in Rocq / Coq

The following file (`BlinkTableWrapperFragmentAssemblySemantics.v`) provides a complete, self-contained mechanization of the table wrapper fragment assembly process and proves the vertical coordinate advancement invariants with zero admits.

```coq
(** * BlinkTableWrapperFragmentAssemblySemantics.v
    Formal audit of Chromium Blink Table Wrapper Box Fragment Tree Assembly.
    Agent 224. *)

From Coq Require Import List.
From Coq Require Import Arith.
From Coq Require Import Lia.
Import ListNotations.

(** ** 1. Data Definitions *)

(** Input specification for a single caption or grid box prior to placement.
    All dimensions are represented in non-negative layout units (nat). *)
Record BoxInput : Type := mkBoxInput {
  space_before : nat;
  block_size   : nat;
  space_after  : nat
}.

(** A placed physical fragment inside the Table Wrapper's coordinate space. *)
Record PlacedFragment : Type := mkPlacedFragment {
  frag_offset : nat;
  frag_size   : nat
}.

(** Top edge of a placed fragment. *)
Definition frag_top (f : PlacedFragment) : nat :=
  frag_offset f.

(** Bottom edge of a placed fragment. *)
Definition frag_bottom (f : PlacedFragment) : nat :=
  frag_offset f + frag_size f.

(** Complete assembled Table Wrapper Fragment. *)
Record TableWrapperFragment : Type := mkTableWrapperFragment {
  wrapper_top_captions    : list PlacedFragment;
  wrapper_grid_fragment   : PlacedFragment;
  wrapper_bottom_captions : list PlacedFragment;
  wrapper_total_block_size : nat
}.

(** ** 2. Fragment Assembly Algorithm *)

(** Lay out a single box at [current_offset], returning the placed fragment
    and the updated block offset cursor. *)
Definition place_single_box (current_offset : nat) (b : BoxInput) 
  : PlacedFragment * nat :=
  let offset := current_offset + space_before b in
  let frag := mkPlacedFragment offset (block_size b) in
  let next_offset := offset + block_size b + space_after b in
  (frag, next_offset).

(** Lay out a sequence of boxes (e.g., captions) sequentially. *)
Fixpoint place_box_list (current_offset : nat) (boxes : list BoxInput) 
  : list PlacedFragment * nat :=
  match boxes with
  | [] => ([], current_offset)
  | b :: rest =>
      let (frag, next_offset) := place_single_box current_offset b in
      let (rest_frags, final_offset) := place_box_list next_offset rest in
      (frag :: rest_frags, final_offset)
  end.

(** Assemble the complete Table Wrapper Box Fragment from top captions,
    the table grid box, bottom captions, and wrapper border/padding. *)
Definition assemble_table_wrapper
  (border_padding_before : nat)
  (top_caps : list BoxInput)
  (grid_box : BoxInput)
  (bot_caps : list BoxInput)
  (border_padding_after : nat)
  : TableWrapperFragment :=
  let (placed_top, offset_after_top) := 
    place_box_list border_padding_before top_caps in
  let (placed_grid, offset_after_grid) := 
    place_single_box offset_after_top grid_box in
  let (placed_bot, offset_after_bot) := 
    place_box_list offset_after_grid bot_caps in
  let total_size := offset_after_bot + border_padding_after in
  mkTableWrapperFragment placed_top placed_grid placed_bot total_size.

(** ** 3. Lemmas on Cursor Advancement and Bounds *)

Lemma place_single_box_monotonic : forall offset b frag next_offset,
  place_single_box offset b = (frag, next_offset) ->
  offset <= frag_top frag /\
  frag_top frag <= frag_bottom frag /\
  frag_bottom frag <= next_offset.
Proof.
  intros offset b frag next_offset H.
  unfold place_single_box in H.
  inversion H; subst; clear H.
  unfold frag_top, frag_bottom; simpl.
  lia.
Qed.

Lemma place_box_list_monotonic : forall boxes offset frags final_offset,
  place_box_list offset boxes = (frags, final_offset) ->
  offset <= final_offset.
Proof.
  induction boxes as [| b rest IH]; intros offset frags final_offset H.
  - simpl in H. inversion H; subst. lia.
  - simpl in H.
    destruct (place_single_box offset b) as [frag next_offset] eqn:Hsingle.
    destruct (place_box_list next_offset rest) as [rest_frags f_offset] eqn:Hlist.
    inversion H; subst; clear H.
    apply place_single_box_monotonic in Hsingle.
    apply IH in Hlist.
    lia.
Qed.

Lemma place_box_list_bounds : forall boxes offset frags final_offset f,
  place_box_list offset boxes = (frags, final_offset) ->
  In f frags ->
  offset <= frag_top f /\ frag_bottom f <= final_offset.
Proof.
  induction boxes as [| b rest IH]; intros offset frags final_offset f H Hin.
  - simpl in H. inversion H; subst. inversion Hin.
  - simpl in H.
    destruct (place_single_box offset b) as [frag next_offset] eqn:Hsingle.
    destruct (place_box_list next_offset rest) as [rest_frags f_offset] eqn:Hlist.
    inversion H; subst; clear H.
    simpl in Hin.
    pose proof (place_single_box_monotonic offset b frag next_offset Hsingle) as Hbounds.
    destruct Hin as [Heq | Hin_rest].
    + subst f.
      pose proof (place_box_list_monotonic rest next_offset rest_frags final_offset Hlist) as Hmono.
      lia.
    + specialize (IH next_offset rest_frags final_offset f Hlist Hin_rest).
      lia.
Qed.

(** Pairwise ordering predicate for a list of placed fragments. *)
Inductive StrictlyAdvancing : list PlacedFragment -> Prop :=
  | SA_Nil : StrictlyAdvancing []
  | SA_One : forall f, StrictlyAdvancing [f]
  | SA_Cons : forall f1 f2 rest,
      frag_bottom f1 <= frag_top f2 ->
      StrictlyAdvancing (f2 :: rest) ->
      StrictlyAdvancing (f1 :: f2 :: rest).

Lemma place_box_list_head_top : forall boxes offset f rest final_offset,
  place_box_list offset boxes = (f :: rest, final_offset) ->
  offset <= frag_top f.
Proof.
  intros boxes offset f rest final_offset H.
  eapply place_box_list_bounds with (f := f) in H.
  - lia.
  - simpl; left; reflexivity.
Qed.

Lemma place_box_list_strictly_advancing : forall boxes offset frags final_offset,
  place_box_list offset boxes = (frags, final_offset) ->
  StrictlyAdvancing frags.
Proof.
  induction boxes as [| b rest IH]; intros offset frags final_offset H.
  - simpl in H. inversion H; subst. constructor.
  - simpl in H.
    destruct (place_single_box offset b) as [frag next_offset] eqn:Hsingle.
    destruct (place_box_list next_offset rest) as [rest_frags f_offset] eqn:Hlist.
    inversion H; subst; clear H.
    pose proof (place_single_box_monotonic offset b frag next_offset Hsingle) as Hsingle_b.
    destruct rest_frags as [| f2 rest_frags'].
    + constructor.
    + constructor.
      * pose proof (place_box_list_head_top rest next_offset f2 rest_frags' final_offset Hlist) as Htop.
        lia.
      * eapply IH; eauto.
Qed.

(** ** 4. Main Audit Invariant Theorems *)

(** Invariant 1: Every top caption's bottom coordinate is <= the table grid's top coordinate. *)
Theorem top_caption_precedes_grid :
  forall bp_before top_caps grid_box bot_caps bp_after wrapper f_top,
    wrapper = assemble_table_wrapper bp_before top_caps grid_box bot_caps bp_after ->
    In f_top (wrapper_top_captions wrapper) ->
    frag_bottom f_top <= frag_top (wrapper_grid_fragment wrapper).
Proof.
  intros bp_before top_caps grid_box bot_caps bp_after wrapper f_top Hw Hin.
  unfold assemble_table_wrapper in Hw.
  destruct (place_box_list bp_before top_caps) as [placed_top offset_after_top] eqn:Htop.
  destruct (place_single_box offset_after_top grid_box) as [placed_grid offset_after_grid] eqn:Hgrid.
  destruct (place_box_list offset_after_grid bot_caps) as [placed_bot offset_after_bot] eqn:Hbot.
  subst wrapper; simpl in *.
  eapply place_box_list_bounds in Htop; [| exact Hin].
  apply place_single_box_monotonic in Hgrid.
  lia.
Qed.

(** Invariant 2: The table grid's bottom coordinate is <= every bottom caption's top coordinate. *)
Theorem grid_precedes_bottom_caption :
  forall bp_before top_caps grid_box bot_caps bp_after wrapper f_bot,
    wrapper = assemble_table_wrapper bp_before top_caps grid_box bot_caps bp_after ->
    In f_bot (wrapper_bottom_captions wrapper) ->
    frag_bottom (wrapper_grid_fragment wrapper) <= frag_top f_bot.
Proof.
  intros bp_before top_caps grid_box bot_caps bp_after wrapper f_bot Hw Hin.
  unfold assemble_table_wrapper in Hw.
  destruct (place_box_list bp_before top_caps) as [placed_top offset_after_top] eqn:Htop.
  destruct (place_single_box offset_after_top grid_box) as [placed_grid offset_after_grid] eqn:Hgrid.
  destruct (place_box_list offset_after_grid bot_caps) as [placed_bot offset_after_bot] eqn:Hbot.
  subst wrapper; simpl in *.
  apply place_single_box_monotonic in Hgrid.
  eapply place_box_list_bounds in Hbot; [| exact Hin].
  lia.
Qed.

(** Invariant 3: All fragments in the wrapper (top captions ++ [grid] ++ bottom captions)
    strictly advance in vertical coordinates and stay within the wrapper's total block size. *)
Theorem wrapper_assembly_full_correctness :
  forall bp_before top_caps grid_box bot_caps bp_after wrapper,
    wrapper = assemble_table_wrapper bp_before top_caps grid_box bot_caps bp_after ->
    StrictlyAdvancing (wrapper_top_captions wrapper) /\
    StrictlyAdvancing (wrapper_bottom_captions wrapper) /\
    (forall f_top, In f_top (wrapper_top_captions wrapper) ->
       bp_before <= frag_top f_top /\
       frag_bottom f_top <= frag_top (wrapper_grid_fragment wrapper)) /\
    (forall f_bot, In f_bot (wrapper_bottom_captions wrapper) ->
       frag_bottom (wrapper_grid_fragment wrapper) <= frag_top f_bot /\
       frag_bottom f_bot <= wrapper_total_block_size wrapper) /\
    frag_bottom (wrapper_grid_fragment wrapper) <= wrapper_total_block_size wrapper.
Proof.