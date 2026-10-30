### 1. GridBreakToken Representation

In Chromium Blink's LayoutNG architecture (`ng_grid_break_token_data.h` and `ng_grid_layout_algorithm.cc`), grid fragmentation continuation state is encapsulated within `NGGridBreakTokenData` (attached to `NGBlockBreakToken`). 

To comply with **CSS Fragmentation Module Level 3 §4 (Fragmentation Model)**, which dictates that layout must resume cleanly from the exact point of interruption without duplicating or dropping content, the break token tracks the following core coordinates:

1. **Broken Row Index (`row_index`):** The zero-based index of the grid track (row) where fragmentation occurred. If a break occurs *between* rows $i-1$ and $i$, the token records row $i$ with an offset of $0$. If a break slices *through* row $i$ (an intra-row break), the token records row $i$.
2. **Row Offset (`consumed_row_offset` / `consumed_grid_size`):** The layout block-size (in `LayoutUnit`) already consumed within the broken row across prior fragmentainers. For a break between rows, this is $0$. For an intra-row break, $0 < \text{offset} < \text{height}(\text{row}_i)$.

---

### 2. Resumption Semantics

When `NGGridLayoutAlgorithm::Layout()` executes for fragmentainer $k > 0$:
1. **Token Extraction:** It reads the incoming `NGBlockBreakToken`.
2. **Coordinate Restoration:** Instead of starting track sizing and item placement at row $0$, the algorithm initializes its placement cursor at the token's `row_index`.
3. **Intra-Row Slicing:** The remaining block-size for `row_index` in the current fragmentainer is computed as $\text{remaining\_row\_height} = \text{row\_height}[\text{row\_index}] - \text{row\_offset}$. Grid items spanning this row have their local break tokens resolved relative to this offset.
4. **Advancement:** Subsequent rows ($r > \text{row\_index}$) are laid out sequentially until the current fragmentainer's available block-size (`fragmentainer_space`) is exhausted, generating a new `GridBreakToken` if content remains.

---

### 3. Formal Invariants

To satisfy CSS Fragmentation 3 §4 (progress guarantee and geometric conservation), the fragmentation loop must maintain two primary invariants:

1. **Strict Lexicographical State Advancement (Termination / No Infinite Loops):**
   Assuming every fragmentainer provides strictly positive available block-size ($\text{avail\_space} > 0$), the continuation state $(r, o)$ representing $(\text{row\_index}, \text{row\_offset})$ must strictly advance across consecutive break tokens:
   $$(r_{k}, o_{k}) <_{\text{lex}} (r_{k+1}, o_{k+1}) \iff (r_k < r_{k+1}) \lor (r_k = r_{k+1} \land o_k < o_{k+1})$$
2. **Block-Size Conservation (Height Monotonicity):**
   The sum of the block-sizes of all generated grid fragments must be greater than or equal to the total unfragmented intrinsic block-size of the grid container (accounting for potential row expansion due to child fragmentation struts/forced breaks):
   $$\sum_{f \in \text{Fragments}} \text{height}(f) \ge \sum_{r \in \text{Rows}} \text{height}(r)$$

---

### 4. Rocq / Coq Formalization (`BlinkGridFragmentBreakSemantics.v`)

The following complete, self-contained Rocq (Coq) module formalizes the break token state machine, resumption semantics, and proves the required invariants.

```coq
(** * BlinkGridFragmentBreakSemantics.v
    Formal audit of Chromium Blink Grid Fragmentation Continuation
    against CSS Fragmentation Module Level 3 §4. *)

Require Import Coq.Lists.List.
Require Import Coq.Arith.Arith.
Require Import Coq.micromega.Lia.
Import ListNotations.

(** ** 1. Data Structures & Representation *)

(** A Grid is represented by the intrinsic block-sizes (heights) of its rows. *)
Definition GridRows := list nat.

(** GridBreakToken representation:
    - [broken_row_index]: The row index where layout was interrupted.
    - [row_offset]: The vertical offset already consumed within that row. *)
Record GridBreakToken := mkBreakToken {
  broken_row_index : nat;
  row_offset : nat
}.

(** A generated GridFragment records its consumed block-size, the starting
    state, and the outgoing break token (None if layout completed). *)
Record GridFragment := mkFragment {
  frag_start_row : nat;
  frag_start_offset : nat;
  frag_height : nat;
  frag_next_token : option GridBreakToken
}.

(** Total intrinsic height of a list of rows. *)
Fixpoint total_rows_height (rows : GridRows) : nat :=
  match rows with
  | [] => 0
  | h :: t => h + total_rows_height t
  end.

(** Remaining height of the grid from a given BreakToken state. *)
Definition remaining_grid_height (rows : GridRows) (tok : GridBreakToken) : nat :=
  let rem_rows := skipn (broken_row_index tok) rows in
  match rem_rows with
  | [] => 0
  | r_h :: rest => (r_h - row_offset tok) + total_rows_height rest
  end.

(** ** 2. Resumption & Single-Fragment Layout Step *)

(** [step_row] computes the fragmentation of the active row at [idx]
    given [offset] already consumed and [avail] fragmentainer space (> 0).
    Returns: (consumed_height, next_token_option). *)
Definition layout_single_fragment
  (rows : GridRows) (in_tok : option GridBreakToken) (avail : nat) : GridFragment :=
  let start_r := match in_tok with None => 0 | Some t => broken_row_index t end in
  let start_o := match in_tok with None => 0 | Some t => row_offset t end in
  match nth_error rows start_r with
  | None =>
      (* Out of bounds / Empty grid completion *)
      mkFragment start_r start_o 0 None
  | Some r_height =>
      let rem_in_row := r_height - start_o in
      if Nat.leb rem_in_row avail then
        (* The remainder of the current row fits entirely in the fragmentainer.
           Advance to the next row. (Simplified to 1-row-per-step or exact fit
           for fundamental state transition verification). *)
        let next_r := S start_r in
        let next_tok :=
          match nth_error rows next_r with
          | None => None (* Grid completely consumed *)
          | Some _ => Some (mkBreakToken next_r 0)
          end
        in mkFragment start_r start_o rem_in_row next_tok
      else
        (* Intra-row break: row slices across the fragmentainer boundary. *)
        let next_o := start_o + avail in
        mkFragment start_r start_o avail (Some (mkBreakToken start_r next_o))
  end.

(** ** 3. Invariant 1: Strict Lexicographical Advancement *)

(** Lexicographical order on GridBreakToken:
    Token A < Token B iff row_index A < row_index B, or
    row_index A = row_index B and row_offset A < row_offset B. *)
Definition token_lt (t1 t2 : GridBreakToken) : Prop :=
  (broken_row_index t1 < broken_row_index t2) \/
  (broken_row_index t1 = broken_row_index t2 /\ row_offset t1 < row_offset t2).

(** Well-formedness of an incoming break token wrt a Grid. *)
Definition wf_token (rows : GridRows) (t : GridBreakToken) : Prop :=
  exists r_height,
    nth_error rows (broken_row_index t) = Some r_height /\
    row_offset t < r_height.

(** Resumption Theorem: The generated fragment immediately resumes at the
    exact row index and offset specified by the incoming break token. *)
Theorem resumption_exactness :
  forall rows t avail,
    let frag := layout_single_fragment rows (Some t) avail in
    frag_start_row frag = broken_row_index t /\
    frag_start_offset frag = row_offset t.
Proof.
  intros rows t avail.
  unfold layout_single_fragment.
  destruct (nth_error rows (broken_row_index t)); simpl.
  - destruct (Nat.leb (n - row_offset t) avail); simpl; auto.
  - auto.
Qed.

(** Progress Theorem: If fragmentainer available space is strictly positive
    (avail > 0) and the incoming token is well-formed, any emitted continuation
    token strictly advances in lexicographical order. *)
Theorem break_token_strict_advance :
  forall rows t_in t_out avail,
    avail > 0 ->
    wf_token rows t_in ->
    frag_next_token (layout_single_fragment rows (Some t_in) avail) = Some t_out ->
    token_lt t_in t_out.
Proof.
  intros rows t_in t_out avail Havail Hwf Hstep.
  unfold wf_token in Hwf.
  destruct Hwf as [r_h [Hnth Hlt]].
  unfold layout_single_fragment in Hstep.
  simpl in Hstep.
  rewrite Hnth in Hstep.
  destruct (Nat.leb (r_h - row_offset t_in) avail) eqn:Hfit.
  - (* Case 1: Remainder of row fits; advances to next row *)
    destruct (nth_error rows (S (broken_row_index t_in))) eqn:Hnext;
       try discriminate.
    inversion Hstep; subst; clear Hstep.
    unfold token_lt; simpl.
    left; lia.
  - (* Case 2: Intra-row break; offset advances by avail *)
    inversion Hstep; subst; clear Hstep.
    unfold token_lt; simpl.
    right; split; [reflexivity | lia].
Qed.

(** ** 4. Invariant 2: Fragment Height Conservation *)

(** Multi-step fragmentation trace: Inductive relation modeling a valid
    sequence of fragments produced from a starting state to completion,
    allowing for Blink's fragmentation expansion (struts) where actual
    fragment height >= consumed intrinsic row height. *)
Inductive ValidFragmentSequence :
  GridRows -> nat (* current row *) -> nat (* current offset *) ->
  list GridFragment -> Prop :=
  | VFS_Done : forall rows r,
      r >= length rows ->
      ValidFragmentSequence rows r 0 []
  | VFS_IntraRow : forall rows r o avail strut f rest r_h,
      nth_error rows r = Some r_h ->
      o + avail < r_h ->
      avail > 0 ->
      frag_start_row f = r ->
      frag_start_offset f = o ->
      frag_height f = avail + strut -> (* includes optional pagination strut *)
      frag_next_token f = Some (mkBreakToken r (o + avail)) ->
      ValidFragmentSequence rows r (o + avail) rest ->
      ValidFragmentSequence rows r o (f :: rest)
  | VFS_NextRow : forall rows r o strut f rest r_h,
      nth_error rows r = Some r_h ->
      o <= r_h ->
      frag_start_row f = r ->
      frag_start_offset f = o ->
      frag_height f = (r_h - o) + strut ->
      ValidFragmentSequence rows (S r) 0 rest ->
      ValidFragmentSequence rows r o (f :: rest).

Fixpoint sum_fragment_heights (frags : list GridFragment) : nat :=
  match frags with
  | [] => 0
  | f :: rest => frag_height f + sum_fragment_heights rest
  end.

(** Helper lemma connecting [nth_error] and [skipn] to [total_rows_height]. *)
Lemma skipn_total_height_split :
  forall rows r r_h,
    nth_error rows r = Some r_h ->
    total_rows_height (skipn r rows) = r_h + total_rows_height (skipn (S r) rows).
Proof.
  induction rows as [|x xs IH]; intros r r_h Hnth.
  - destruct r; discriminate.
  - destruct r as [|r'].
    + simpl in Hnth. inversion Hnth; subst.
      simpl. reflexivity.
    + simpl in Hnth. simpl.
      apply IH with (r_h := r_h); assumption.
Qed.

Lemma skipn_oob_height :
  forall rows r,
    r >= length rows ->
    total_rows_height (skipn r rows) = 0.
Proof.
  induction rows as [|x xs IH]; intros r Hlen.
  - destruct r; reflexivity.
  - destruct r as [|r'].
    + simpl in Hlen. lia.
    + simpl in *. apply IH. lia.
Qed.

(** Generalized Conservation Lemma: For any valid fragmentation sequence
    starting at (r, o), the sum of fragment heights is >= the remaining
    unconsumed height of the grid from (r, o). *)
Lemma fragment_height_conservation_gen :
  forall rows r o frags,
    ValidFragmentSequence rows r o frags ->
    sum_fragment_heights frags >=
      total_rows_height (skipn r rows) - o.
Proof.
  intros rows r o frags Hvfs.
  induction Hvfs.
  - (* VFS_Done *)
    simpl. rewrite skipn_oob_height by assumption. lia.
  - (* VFS_IntraRow *)
    simpl. rewrite H4.
    pose proof (skipn_total_height_split rows r r_h H) as Hsplit.
    lia.
  - (* VFS_NextRow *)
    simpl. rewrite H3.
    pose proof (skipn_total_height_split rows r r_h H) as Hsplit.
    lia.
Qed.

(** Main Conservation Theorem: A complete fragmentation sequence starting at
    row 0, offset 0 produces fragments whose total block-size is at least
    the total intrinsic block-size of the grid. *)
Theorem blink_grid_fragment_height_conservation :
  forall rows frags,
    ValidFragmentSequence rows 0 0 frags ->
    sum_fragment_heights frags >= total_rows_height rows.
Proof.
  intros rows frags Hvfs.
  pose proof (fragment_height_conservation_gen rows 0 0 frags Hvfs) as Hgen.
  simpl in