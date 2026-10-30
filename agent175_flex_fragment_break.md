### Audit Report: Agent 175 — Chromium Blink Flexbox Fragmentation Continuation vs. CSS Fragmentation Module Level 3 §4

**Target System:** Chromium Blink LayoutNG (`NGFlexLayoutAlgorithm`, `NGBlockBreakToken`, `NGBreakTokenData`)  
**Specification:** CSS Fragmentation Module Level 3 §4 (Fragmentation Model and Rules for Breaking)  

---

### 1. FlexBreakToken Representation

In Blink's LayoutNG engine, when a flex container fragments across fragmentainers (columns, pages, or regions), state is serialized into an `NGBlockBreakToken`. For flex containers, this token encapsulates specialized flex continuation data (`NGFlexBreakTokenData`) alongside the base block fragmentation metrics, as well as a tree of child break tokens for items that fragmented mid-element.

To formally audit the continuation state against CSS Fragmentation 3 §4, we abstract the representation of a `FlexBreakToken` into a deterministic state tuple:

$$\mathcal{T}_{\text{flex}} = \langle \ell_{\text{idx}}, i_{\text{idx}}, B_{\text{consumed}}, \tau_{\text{child}}, \sigma_{\text{done}} \rangle$$

1. **Current Flex Line Index ($\ell_{\text{idx}} \in \mathbb{N}$):**  
   Tracks the 0-based index of the flex line currently undergoing fragmentation. For row-direction flex containers, a break between flex lines advances $\ell_{\text{idx}}$ while resetting $i_{\text{idx}}$ to $0$. For column-direction flex containers, multiple lines may fragment concurrently across the block progression axis, requiring $\ell_{\text{idx}}$ to coordinate with per-line item resumption.
2. **Item Fragment Index ($i_{\text{idx}} \in \mathbb{N}$):**  
   Identifies the 0-based index of the flex item within line $\ell_{\text{idx}}$ where layout must resume in the next fragmentainer. If a break occurs cleanly *between* two sibling items (or before an item that gets pushed to the next fragmentainer due to `break-inside: avoid` or insufficient space), $i_{\text{idx}}$ points to the unplaced item.
3. **Consumed Block Size ($B_{\text{consumed}} \in \mathbb{N}$):**  
   The cumulative block-axis size of the flex container consumed by all preceding fragmentainers up to the point of this break. Per CSS Fragmentation 3 §4.1, a box's layout in subsequent fragmentainers is conceptually positioned relative to this offset.
4. **Child Break Token State ($\tau_{\text{child}} \in \mathbb{N}$):**  
   Represents the internal consumed block size of item $(\ell_{\text{idx}}, i_{\text{idx}})$ if that specific item broke internally across fragmentainers (i.e., $0 < \tau_{\text{child}} < \text{ItemBlockSize}(\ell_{\text{idx}}, i_{\text{idx}})$). If $\tau_{\text{child}} = 0$, item $(\ell_{\text{idx}}, i_{\text{idx}})$ begins fresh in the next fragmentainer.

---

### 2. Resumption Semantics

When `NGFlexLayoutAlgorithm::Layout()` executes for fragmentainer $k$, it inspects the incoming `BreakToken` ($\mathcal{T}_{k-1}$):

* **Initial Entry ($\mathcal{T}_0 = \text{None}$):**  
  Layout begins at $(\ell_{\text{idx}} = 0, i_{\text{idx}} = 0)$ with $B_{\text{consumed}} = 0$ and $\tau_{\text{child}} = 0$.
* **Continuation Entry ($\mathcal{T}_{k-1} = \text{Some}(\ell, i, B, \tau)$):**  
  1. The algorithm skips all flex lines $\ell' < \ell$.
  2. Within line $\ell$, it skips all flex items $i' < i$, as their layout was fully resolved in fragmentainers $0 \dots k-1$.
  3. Layout resumes precisely at item $(\ell, i)$. If $\tau > 0$, item $(\ell, i)$ is invoked with its own incoming child break token holding consumed block size $\tau$.
  4. As items are placed into fragmentainer $k$ (which has available block capacity $C_k > 0$), the cursor $(\ell, i, \tau)$ advances lexicographically.
  5. When the remaining block space in fragmentainer $k$ is exhausted (or a forced break is encountered) prior to placing all lines and items, `FinishFragmentation()` emits $\mathcal{T}_k = \text{Some}(\ell', i', B + \Delta B_k, \tau')$, where $\Delta B_k$ is the block size consumed in fragmentainer $k$.

---

### 3. Core Invariants

To guarantee compliance with CSS Fragmentation 3 §4 (specifically §4.4 *Monotonic Progress / Unbreakable Content*), Blink's continuation mechanism must satisfy two structural invariants:

1. **Strict Monotonicity of Consumed Block Size & Lexicographical Cursor:**  
   Even if a flex item is unbreakable and taller than the fragmentainer capacity ($C_k$), the fragmentation algorithm *must* make forward progress to prevent infinite pagination loops. Across any sequence of consecutive break tokens $\mathcal{T}_1, \mathcal{T}_2, \dots, \mathcal{T}_n$:
   $$B_{\text{consumed}}(\mathcal{T}_k) < B_{\text{consumed}}(\mathcal{T}_{k+1})$$
   $$\langle \ell_{\text{idx}}(\mathcal{T}_k), i_{\text{idx}}(\mathcal{T}_k), \tau_{\text{child}}(\mathcal{T}_k) \rangle \prec_{\text{lex}} \langle \ell_{\text{idx}}(\mathcal{T}_{k+1}), i_{\text{idx}}(\mathcal{T}_{k+1}), \tau_{\text{child}}(\mathcal{T}_{k+1}) \rangle$$

2. **Total Item Coverage (Conservation of Content):**  
   A completed fragmentation sequence $\mathcal{F}_0, \mathcal{F}_1, \dots, \mathcal{F}_m$ (where $\mathcal{F}_m$ emits a terminal break token with $\sigma_{\text{done}} = \text{true}$) partitions the set of all flex items across the container's lines without omission or duplication, and the sum of block fragments for every item $(\ell, i)$ equals its total layout block size.

---

### 4. Formal Verification in Rocq / Coq (`BlinkFlexFragmentBreakSemantics.v`)

Below is the complete, self-contained Rocq/Coq specification and proof script formalizing `FlexBreakToken`, the continuation transition system, strict monotonicity, and total item coverage.

```coq
(** * BlinkFlexFragmentBreakSemantics.v
    Formal Audit of Chromium Blink Flexbox Fragmentation Continuation
    vs. CSS Fragmentation Module Level 3 Section 4.
    Agent 175 Verification Artifact. *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

Section BlinkFlexFragmentation.

  (** ** 1. Layout Input Representation *)

  (** A FlexItem is characterized by its required non-negative block size.
      Per CSS Fragmentation 3 §4.4, even zero-sized items occupy a discrete
      logical layout step, here modeled with positive layout cost (>= 1)
      to unify progress metrics, or explicitly stepped over. *)
  Record FlexItem : Type := mkFlexItem {
    item_id : nat;
    item_block_size : nat;
    item_size_pos : item_block_size > 0
  }.

  (** A FlexLine is a non-empty list of FlexItems. *)
  Record FlexLine : Type := mkFlexLine {
    line_items : list FlexItem
  }.

  (** A FlexContainer is a list of FlexLines. *)
  Definition FlexContainer := list FlexLine.

  (** ** 2. FlexBreakToken Representation *)

  (** Represents the serialized continuation state emitted at the end of a
      fragmentainer (NGBlockBreakToken + NGFlexBreakTokenData). *)
  Record FlexBreakToken : Type := mkFlexBreakToken {
    line_index : nat;          (** Current flex line index *)
    item_index : nat;          (** Current item index within the flex line *)
    item_consumed : nat;       (** Consumed block size of current item (child break token) *)
    consumed_block_size : nat; (** Total consumed block size of the flex container *)
    is_at_end : bool           (** True iff all lines and items have finished layout *)
  }.

  (** Initial state prior to the first fragmentainer (Incoming break token = None). *)
  Definition initial_token : FlexBreakToken := {|
    line_index := 0;
    item_index := 0;
    item_consumed := 0;
    consumed_block_size := 0;
    is_at_end := false
  |}.

  (** ** 3. Sliced Item Fragment & Layout Fragment Output *)

  (** Represents a slice of a FlexItem placed inside a single fragmentainer. *)
  Record ItemFragment : Type := mkItemFragment {
    frag_line_idx : nat;
    frag_item_idx : nat;
    frag_item_id  : nat;
    frag_offset   : nat;
    frag_block_sz : nat
  }.

  (** Represents the physical fragment produced for one fragmentainer pass. *)
  Record FlexPhysicalFragment : Type := mkFlexPhysicalFragment {
    placed_items : list ItemFragment;
    fragment_block_size : nat;
    outgoing_token : FlexBreakToken
  }.

  (** ** 4. Resumption and Step Semantics *)

  (** Helper: retrieve the FlexLine at [l_idx] *)
  Definition get_line (c : FlexContainer) (l_idx : nat) : option FlexLine :=
    nth_error c l_idx.

  (** Helper: retrieve the FlexItem at [l_idx, i_idx] *)
  Definition get_item (c : FlexContainer) (l_idx i_idx : nat) : option FlexItem :=
    match get_line c l_idx with
    | Some line => nth_error (line_items line) i_idx
    | None => None
    end.

  (** Advances the (line_index, item_index) cursor to the next valid item in the container,
      or marks completion if no further items exist. *)
  Fixpoint advance_cursor (c : FlexContainer) (l_idx i_idx : nat) (fuel : nat) : (nat * nat * bool) :=
    match fuel with
    | 0 => (l_idx, i_idx, true)
    | S fuel' =>
      match get_line c l_idx with
      | None => (l_idx, i_idx, true) (* All lines exhausted *)
      | Some line =>
        if i_idx <? length (line_items line) then
          (l_idx, i_idx, false) (* Valid item found *)
        else
          (* Advance to the start of the next flex line *)
          advance_cursor c (S l_idx) 0 fuel'
      end
    end.

  Definition normalize_cursor (c : FlexContainer) (l_idx i_idx : nat) : (nat * nat * bool) :=
    advance_cursor c l_idx i_idx (S (length c - l_idx)).

  (** Single fragmentainer layout step:
      Given a container [c], incoming [token], and fragmentainer block capacity [avail_space > 0],
      resumes at (token.line_index, token.item_index) and consumes up to [avail_space]
      (or forces 1 unit of progress per CSS Fragmentation 3 §4.4 if avail_space == 0). *)
  Definition layout_next_fragment
    (c : FlexContainer)
    (in_token : FlexBreakToken)
    (avail_space : nat) : FlexPhysicalFragment :=
    let effective_space := Nat.max 1 avail_space in
    let '(l_idx, i_idx, done) := normalize_cursor c (line_index in_token) (item_index in_token) in
    if done || is_at_end in_token then
      {| placed_items := [];
         fragment_block_size := 0;
         outgoing_token := {| line_index := l_idx;
                              item_index := i_idx;
                              item_consumed := 0;
                              consumed_block_size := consumed_block_size in_token;
                              is_at_end := true |} |}
    else
      match get_item c l_idx i_idx with
      | None =>
        {| placed_items := [];
           fragment_block_size := 0;
           outgoing_token := {| line_index := l_idx;
                                item_index := i_idx;
                                item_consumed := 0;
                                consumed_block_size := consumed_block_size in_token;
                                is_at_end := true |} |}
      | Some item =>
        let rem_item_size := item_block_size item - item_consumed in_token in
        let actual_rem := Nat.max 1 rem_item_size in
        if actual_rem <=? effective_space then
          (* Item finishes inside this fragmentainer; advance to next item/line *)
          let '(next_l, next_i, next_done) := normalize_cursor c l_idx (S i_idx) in
          let frag := {| frag_line_idx := l_idx;
                         frag_item_idx := i_idx;
                         frag_item_id  := item_id item;
                         frag_offset   := item_consumed in_token;
                         frag_block_sz := actual_rem |} in
          {| placed_items := [frag];
             fragment_block_size := actual_rem;
             outgoing_token := {| line_index := next_l;
                                  item_index := next_i;
                                  item_consumed := 0;
                                  consumed_block_size := consumed_block_size in_token + actual_rem;
                                  is_at_end := next_done |} |}
        else
          (* Item breaks inside this fragmentainer; resume same item at next offset *)
          let frag := {| frag_line_idx := l_idx;
                         frag_item_idx := i_idx;
                         frag_item_id  := item_id item;
                         frag_offset   := item_consumed in_token;
                         frag_block_sz := effective_space |} in
          {| placed_items := [frag];
             fragment_block_size := effective_space;
             outgoing_token := {| line_index := l_idx;
                                  item_index := i_idx;
                                  item_consumed := item_consumed in_token + effective_space;
                                  consumed_block_size := consumed_block_size in_token + effective_space;
                                  is_at_end := false |} |}
      end.

  (** ** 5. Invariant 1: Strict Monotonicity of Consumed Block Size & Cursor *)

  (** Lexicographical ordering on the continuation cursor (line_index, item_index, item_consumed). *)
  Definition cursor_lt (t1 t2 : FlexBreakToken) : Prop :=
    (line_index t1 <