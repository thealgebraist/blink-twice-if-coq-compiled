### 1. Break Token Fields: `text_offset` and `item_index`
In Chromium Blink's LayoutNG (`ng_inline_break_token.h`), `NGInlineBreakToken` (now `InlineBreakToken`) encapsulates the exact resumption coordinate within an `InlineNode`'s flattened `InlineItemsData` array and its backing UTF-16 `text_content` string:
*   **`item_index` (`unsigned`)**: The 0-based index into the `InlineItems` vector identifying the specific `InlineItem` (e.g., text run, open/close tag, atomic inline, or float) where layout was interrupted.
*   **`text_offset` (`unsigned`)**: The 0-based UTF-16 code unit offset into `InlineNodeData::text_content`. Every `InlineItem` spans a contiguous range `[start_offset, end_offset)` within `text_content`. For non-text items (e.g., open/close tags), `start_offset == end_offset`. A valid break token guarantees that `text_offset` lies within the bounds of the item at `item_index` (specifically, `item.start_offset <= text_offset <= item.end_offset`).

---

### 2. Resumption: Next Line Begins Exactly at `text_offset`
Per **CSS Fragmentation Module Level 3 §4 (Breaking Inline Boxes)** and CSS Text 3, breaking an inline formatting context across line boxes must partition the inline content without duplicating or dropping characters or layout items.

In Blink's `LineBreaker`:
1.  **Initialization**: When constructing line $k+1$, `LineBreaker` receives the `InlineBreakToken` emitted at the end of line $k$. If $k=0$ (the first line), it initializes `current_.item_index = 0` and `current_.text_offset = 0`. Otherwise, it sets `current_.item_index = break_token->ItemIndex()` and `current_.text_offset = break_token->TextOffset()`.
2.  **Mid-Item Resumption**: When `LineBreaker::NextLine()` processes `items[current_.item_index]`, if `current_.text_offset > item.start_offset`, `HandleText()` slices the `ShapeResult` of the `InlineItem` starting strictly at `current_.text_offset`. The preceding prefix `[item.start_offset, current_.text_offset)` was already consumed by prior lines.
3.  **Continuity**: Line $k+1$ consumes a contiguous interval $[t_k, t_{k+1})$ of `text_content` and advances the item cursor from $i_k$ to $i_{k+1}$, emitting a new `InlineBreakToken` with `(i_{k+1}, t_{k+1})` (unless the end of the paragraph is reached, where no break token or a finished token is emitted).

---

### 3. Invariants
To guarantee termination (no infinite loops in `InlineLayoutAlgorithm`) and completeness (compliance with CSS Fragmentation 3 §4), the sequence of break tokens $\langle (i_0, t_0), (i_1, t_1), \dots, (i_n, t_n) \rangle$ across a paragraph of total text length $L$ and item count $M$ satisfies:
1.  **Lexicographical Progress**: Across any line, the state $(i_k, t_k)$ cannot move backward: $i_k \le i_{k+1}$ and $t_k \le t_{k+1}$.
2.  **Strict `text_offset` Monotonicity across Non-Empty Text Lines**: For any line $k$ that consumes at least one character (or forced break / atomic inline represented by a U+FFFC Object Replacement Character in `text_content`), $t_k < t_{k+1}$. (Note: Lines containing only zero-length items like empty inline tags or unpositioned floats advance $i_k < i_{k+1}$ while $t_k = t_{k+1}$).
3.  **Contiguous Partitioning (No Gaps / No Overlaps)**: The start offset of line $k+1$ is identically the break token `text_offset` emitted by line $k$.
4.  **Total Length Completeness**: The final line $n-1$ terminates when all items and code units are exhausted, yielding a terminal state where $i_n = M$ and $t_n = L$ (matching `text_content.length()`).

---

### 4. Concrete Rocq / Coq Formalization (`BlinkInlineBreakTokenOffsetSemantics.v`)

```coq
(** * BlinkInlineBreakTokenOffsetSemantics.v
    Formal verification of Chromium Blink's InlineBreakToken offset continuation
    against CSS Fragmentation Module Level 3 §4. *)

From Coq Require Import Arith Lia List Bool.
Import ListNotations.

(** ** 1. Data Structures: InlineItem, Paragraph, and InlineBreakToken *)

Record InlineItem : Type := mkInlineItem {
  item_start_offset : nat;
  item_end_offset   : nat;
  item_valid        : item_start_offset <= item_end_offset
}.

Record InlineBreakToken : Type := mkBreakToken {
  item_index  : nat;
  text_offset : nat
}.

Record Paragraph : Type := mkParagraph {
  items              : list InlineItem;
  total_text_length  : nat
}.

(** Well-formedness of an InlineBreakToken with respect to a Paragraph *)
Definition wf_break_token (p : Paragraph) (bt : InlineBreakToken) : Prop :=
  bt.(item_index) <= length p.(items) /\
  bt.(text_offset) <= p.(total_text_length) /\
  (forall item, nth_error p.(items) bt.(item_index) = Some item ->
     item.(item_start_offset) <= bt.(text_offset) /\
     bt.(text_offset) <= item.(item_end_offset)) /\
  (bt.(item_index) = length p.(items) ->
     bt.(text_offset) = p.(total_text_length)).

(** ** 2. Line Fragment & Resumption Semantics *)

Record LineFragment : Type := mkLineFragment {
  line_start_token : InlineBreakToken;
  line_end_token   : InlineBreakToken
}.

(** A line is text-non-empty if it consumes at least one UTF-16 code unit
    (including U+FFFC for atomic inlines or '\n' for forced breaks). *)
Definition is_non_empty_text_line (lf : LineFragment) : Prop :=
  lf.(line_start_token).(text_offset) < lf.(line_end_token).(text_offset).

(** Valid single-line step in Blink's LineBreaker *)
Definition valid_line_step (p : Paragraph) (lf : LineFragment) : Prop :=
  wf_break_token p lf.(line_start_token) /\
  wf_break_token p lf.(line_end_token) /\
  lf.(line_start_token).(item_index) <= lf.(line_end_token).(item_index) /\
  lf.(line_start_token).(text_offset) <= lf.(line_end_token).(text_offset).

(** Resumption invariant: Next line begins exactly at the previous break token *)
Fixpoint valid_resumption_chain (lines : list LineFragment) : Prop :=
  match lines with
  | [] => True
  | [ _ ] => True
  | l1 :: (l2 :: _) as rest =>
      l2.(line_start_token) = l1.(line_end_token) /\
      valid_resumption_chain rest
  end.

(** Complete paragraph layout trace *)
Definition valid_paragraph_layout (p : Paragraph) (lines : list LineFragment) : Prop :=
  lines <> [] /\
  Forall (valid_line_step p) lines /\
  valid_resumption_chain lines /\
  (forall first_line, hd_error lines = Some first_line ->
     first_line.(line_start_token) = mkBreakToken 0 0) /\
  (forall last_line, last_error lines = Some last_line ->
     last_line.(line_end_token).(item_index) = length p.(items) /\
     last_line.(line_end_token).(text_offset) = p.(total_text_length)).

(** Helper for list last_error *)
Definition last_error {A : Type} (l : list A) : option A :=
  match rev l with
  | [] => None
  | x :: _ => Some x
  end.

(** Re-bind valid_paragraph_layout with explicit last_error in scope *)
Definition valid_paragraph_layout_spec (p : Paragraph) (lines : list LineFragment) : Prop :=
  lines <> [] /\
  Forall (valid_line_step p) lines /\
  valid_resumption_chain lines /\
  (forall first_line, hd_error lines = Some first_line ->
     first_line.(line_start_token) = mkBreakToken 0 0) /\
  (forall last_line, last_error lines = Some last_line ->
     last_line.(line_end_token).(item_index) = length p.(items) /\
     last_line.(line_end_token).(text_offset) = p.(total_text_length)).

(** ** 3. Theorems: Resumption Continuity, Strict Monotonicity, and Completeness *)

(** Theorem 1: Immediate Resumption Continuity.
    Every adjacent pair of lines in a valid chain resumes at the exact text_offset
    and item_index where the prior line broke. *)
Theorem resumption_exact_text_offset :
  forall (l1 l2 : LineFragment) (prefix suffix : list LineFragment),
    valid_resumption_chain (prefix ++ l1 :: l2 :: suffix) ->
    l2.(line_start_token).(text_offset) = l1.(line_end_token).(text_offset) /\
    l2.(line_start_token).(item_index) = l1.(line_end_token).(item_index).
Proof.
  intros l1 l2 prefix suffix Hchain.
  induction prefix as [| x xs IH].
  - simpl in Hchain. destruct Hchain as [Heq _].
    rewrite Heq. split; reflexivity.
  - simpl in Hchain. destruct xs as [| y ys].
    + simpl in Hchain. destruct Hchain as [_ [Heq _]].
      rewrite Heq. split; reflexivity.
    + destruct Hchain as [_ Hrest]. apply IH. exact Hrest.
Qed.

(** Measure of total text consumed across a sequence of lines *)
Fixpoint consumed_text_length (lines : list LineFragment) : nat :=
  match lines with
  | [] => 0
  | l :: rest =>
      (l.(line_end_token).(text_offset) - l.(line_start_token).(text_offset)) +
      consumed_text_length rest
  end.

(** Lemma: Telescoping sum of text offsets across a valid resumption chain *)
Lemma chain_telescoping_offsets :
  forall (p : Paragraph) (lines : list LineFragment) (first last : LineFragment),
    Forall (valid_line_step p) lines ->
    valid_resumption_chain lines ->
    hd_error lines = Some first ->
    last_error lines = Some last ->
    consumed_text_length lines =
      last.(line_end_token).(text_offset) - first.(line_start_token).(text_offset).
Proof.
  intros p lines.
  induction lines as [| l1 rest IH]; intros first last Hsteps Hchain Hhd Hlast.
  - discriminate Hhd.
  - inversion Hhd; subst first; clear Hhd.
    inversion Hsteps as [| ? ? Hstep1 Hsteps_rest]; subst.
    destruct rest as [| l2 rest'].
    + unfold last_error in Hlast. simpl in Hlast.
      inversion Hlast; subst last; clear Hlast.
      simpl. lia.
    + simpl in Hchain. destruct Hchain as [Hresume Hchain_rest].
      assert (Hlast_rest : last_error (l2 :: rest') = Some last).
      { unfold last_error in *. simpl in Hlast.
        destruct (rev rest') eqn:Hrev; simpl in *; exact Hlast. }
      specialize (IH l2 last Hsteps_rest Hchain_rest eq_refl Hlast_rest).
      simpl consumed_text_length.
      rewrite IH.
      rewrite Hresume.
      destruct Hstep1 as [_ [_ [_ Hle1]]].
      assert (Hle_last : l1.(line_end_token).(text_offset) <= last.(line_end_token).(text_offset)).
      { clear IH Hlast Hstep1 Hle1 Hresume.
         generalize dependent l2.
        induction rest' as [| l3 rest'' IH2]; intros l2 Hsteps_r Hchain_r Hlast_r.
        - unfold last_error in Hlast_r. simpl in Hlast_r.
          inversion Hlast_r; subst l2.
          inversion Hsteps_r as [| ? ? Hstep2 _]; subst.
          destruct Hstep2 as [_ [_ [_ Hle2]]]. exact Hle2.
        - inversion Hsteps_r as [| ? ? Hstep2 Hsteps_r']; subst.
          simpl in Hchain_r. destruct Hchain_r as [Hres2 Hchain_r'].
          assert (Hlast_r' : last_error (l3 :: rest'') = Some last).
          { unfold last_error in *. simpl in Hlast_r.
            destruct (rev rest'') eqn:Hrev2; simpl in *; exact Hlast_r. }
          specialize (IH2 l3 Hsteps_r' Hchain_r' Hlast_r').
          destruct Hstep2 as [_ [_ [_ Hle2]]].
          rewrite Hres2 in IH2. lia. }
      lia.
Qed.

(** Theorem 2: Strict Monotonicity Across Non-Empty Text Lines.
    For any sequence of non-empty text lines, the break token text_offset
    strictly increases at every step, and boundedness by total_text_length
    guarantees termination in at most total_text_length lines. *)
Theorem strict_offset_increase_on_non_empty_lines :
  forall (p : Paragraph) (l1 l2 : LineFragment),
    valid_line_step p l1 ->
    valid_line_step p l2 ->
    l2.(line_start_token) = l1.(line_end_token) ->
    is_non_empty_text_line l1 ->
    is_non_empty_text_line l2 ->
    l1.(line_start_token).(text_offset) < l1.(line_end_token).(text_offset) /\
    l1.(line_end_token).(text_offset) < l2.(line_end_token).(text_offset) /\
    l2.(line_end_token).(text_offset) <= p.(total_text_length).
Proof.