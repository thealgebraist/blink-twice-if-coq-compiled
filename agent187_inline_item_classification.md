### 1. Inline Item Types & CSS Inline 3 §2 Alignment

In Chromium’s LayoutNG/Blink engine, the `InlineItemsBuilder` phase flattens the DOM tree within an inline formatting context into a linear sequence of `InlineItem` structures alongside a unified `text_content` string (represented by `NGInlineNodeData`). This aligns with **CSS Inline Layout Module Level 3, §2 (Inline-Level Content)**, which defines how inline boxes, text runs, and atomic inlines participate in an inline formatting context.

The core item classifications audited are:

*   **`Text` (`InlineItem::kText`)**:
    *   *Blink Representation*: Represents a run of measurable, shapeable characters (handled via HarfBuzz). Contains a non-empty `[start_offset, end_offset)` range indexing into the paragraph's `text_content`.
    *   *CSS Inline 3 Alignment*: Corresponds to anonymous inline text runs (§2.2).
*   **`Control` (`InlineItem::kControl`)**:
    *   *Blink Representation*: Represents layout-affecting Unicode control characters such as forced line breaks (`\n`, `U+000A`), carriage returns, tabs (`\t`, `U+0009`), or bidirectional isolate controls injected during text collection. Occupies a strict 1-character offset range `[i, i+1)`.
    *   *CSS Inline 3 Alignment*: Implements CSS Text 3/4 and Inline 3 white space processing and forced break semantics.
*   **`OpenTag` / `CloseTag` (`InlineItem::kOpenTag`, `InlineItem::kCloseTag`)**:
    *   *Blink Representation*: Delimits the start and end of an inline box (e.g., `<span>`, `<b>`). Because tags themselves do not emit shapeable glyphs (unless they induce margins/borders/padding, which are resolved into box fragments), they occupy a zero-length character offset range `[i, i)` in the `text_content` string.
    *   *CSS Inline 3 Alignment*: Directly models the boundaries of non-replaced inline boxes (§2.1) that split or wrap inline content.
*   **`AtomicInline` (`InlineItem::kAtomicInline`)**:
    *   *Blink Representation*: Represents replaced elements (`<img>`), `inline-block`, `inline-table`, or `inline-flex` elements. Blink injects a single `U+FFFC` (Object Replacement Character) into the `text_content` string to act as an opaque anchor for line breaking and BiDi resolution. Therefore, an `AtomicInline` item always has a 1-character range `[i, i+1)`.
    *   *CSS Inline 3 Alignment*: Models atomic inline-level boxes (§2.1), which participate in the inline formatting context as a single opaque glyph-like unit.

---

### 2. Formal Invariants of `InlineItemsBuilder`

When `InlineItemsBuilder` finishes constructing the `Vector<InlineItem>` for a paragraph of total character length $N$ (`text_content.length()`), the sequence of items $I_0, I_1, \dots, I_{k-1}$ must satisfy the **Continuous Partition Invariant**:

1.  **Local Well-Formedness (Type-Length Validity)**:
    *   $\forall I \in \text{Items}$:
        *   If $\text{type}(I) \in \{\text{OpenTag}, \text{CloseTag}\}$, then $\text{start}(I) = \text{end}(I)$.
        *   If $\text{type}(I) \in \{\text{Control}, \text{AtomicInline}\}$, then $\text{end}(I) = \text{start}(I) + 1$.
        *   If $\text{type}(I) = \text{Text}$, then $\text{start}(I) < \text{end}(I)$.
2.  **Boundary Anchoring**:
    *   If $\text{Items}$ is non-empty, $\text{start}(I_0) = 0$ and $\text{end}(I_{k-1}) = N$. (If $N=0$ and $\text{Items} = \emptyset$, the range $[0,0)$ is trivially covered).
3.  **Contiguity (No Gaps, No Overlaps)**:
    *   $\forall j \in [0, k-2], \quad \text{end}(I_j) = \text{start}(I_{j+1})$.
4.  **Monotonicity**:
    *   The offsets form a monotonically non-decreasing sequence from $0$ to $N$.

---

### 3. Rocq / Coq Formalization (`BlinkInlineItemClassificationSemantics.v`)

The following file is self-contained and compiles cleanly in Coq/Rocq (8.16+). It formalizes the item classifications, the offset invariants, and proves that a valid item list forms a complete, gap-free partition of the paragraph text range $[0, N)$.

```coq
(** * BlinkInlineItemClassificationSemantics.v
    Formal Audit of Chromium Blink InlineItem Classification vs CSS Inline 3 §2.
    Agent 187. *)

Require Import Coq.Lists.List.
Require Import Coq.Arith.Arith.
Require Import Coq.micromega.Lia.
Import ListNotations.

(** ** 1. Inline Item Classifications *)

Inductive InlineItemType : Type :=
  | Text         (* Measurable, shapeable text run *)
  | Control      (* Forced line breaks (\n), tabs (\t), bidi controls *)
  | OpenTag      (* Start of an inline box (e.g., <span>) *)
  | CloseTag     (* End of an inline box (e.g., </span>) *)
  | AtomicInline (* Replaced elements, inline-block (anchored by U+FFFC) *).

Record InlineItem : Type := mkInlineItem {
  item_type  : InlineItemType;
  start_ofs  : nat;
  end_ofs    : nat
}.

(** ** 2. Local Type-Offset Invariants *)

(** Each item type enforces strict constraints on its character offset span
    within the LayoutNG paragraph text_content buffer. *)
Definition valid_item_span (item : InlineItem) : Prop :=
  match item.(item_type) with
  | Text         => item.(start_ofs) < item.(end_ofs)
  | Control      => item.(end_ofs) = item.(start_ofs) + 1
  | OpenTag      => item.(end_ofs) = item.(start_ofs)
  | CloseTag     => item.(end_ofs) = item.(start_ofs)
  | AtomicInline => item.(end_ofs) = item.(start_ofs) + 1
  end.

Lemma valid_item_monotonic : forall (item : InlineItem),
  valid_item_span item -> item.(start_ofs) <= item.(end_ofs).
Proof.
  intros [t s e] H; destruct t; simpl in *; lia.
Qed.

(** ** 3. Continuous Partition Predicate *)

(** [is_contiguous_chain current_ofs end_target items] asserts that [items]
    forms a gapless, non-overlapping chain starting at [current_ofs] and
    terminating exactly at [end_target]. *)
Fixpoint is_contiguous_chain (cur : nat) (target : nat) (items : list InlineItem) : Prop :=
  match items with
  | [] => cur = target
  | item :: rest =>
      item.(start_ofs) = cur /\
      valid_item_span item /\
      is_contiguous_chain item.(end_ofs) target rest
  end.

(** Top-level validity of an InlineItem list for a paragraph of length [N]. *)
Definition valid_inline_items (N : nat) (items : list InlineItem) : Prop :=
  is_contiguous_chain 0 N items.

(** ** 4. Coverage and Partition Theorems *)

(** Helper: If a chain is contiguous from [cur] to [target], then [cur <= target]. *)
Theorem contiguous_chain_le : forall (items : list InlineItem) (cur target : nat),
  is_contiguous_chain cur target items ->
  cur <= target.
Proof.
  induction items as [| item rest IH]; intros cur target H.
  - simpl in H. lia.
  - simpl in H. destruct H as [Hstart [Hspan Hrest]].
    pose proof (valid_item_monotonic item Hspan) as Hle.
    pose proof (IH (end_ofs item) target Hrest) as Hrest_le.
    lia.
Qed.

(** Definition of a character index [c] being covered by a specific [InlineItem].
    Note that zero-length items (OpenTag/CloseTag) cover no character indices,
    as half-open intervals [s, s) are empty. *)
Definition item_covers_char (item : InlineItem) (c : nat) : Prop :=
  item.(start_ofs) <= c < item.(end_ofs).

(** Theorem 1 (No Overlaps):
    In a contiguous chain, no two distinct items in the list can cover the
    same character index [c]. *)
Theorem chain_disjoint_coverage : forall (items : list InlineItem) (cur target c : nat),
  is_contiguous_chain cur target items ->
  forall i j item_i item_j,
    i < j ->
    nth_error items i = Some item_i ->
    nth_error items j = Some item_j ->
    item_covers_char item_i c ->
    ~ item_covers_char item_j c.
Proof.
  induction items as [| hd tl IH]; intros cur target c Hchain i j item_i item_j Hij Hnth_i Hnth_j Hcov_i Hcov_j.
  - destruct i; discriminate.
  - simpl in Hchain. destruct Hchain as [Hstart [Hspan Hrest]].
    destruct i as [| i'].
    + (* i = 0, so item_i = hd *)
      simpl in Hnth_i. injection Hnth_i as Heq_i. subst hd.
      destruct j as [| j']; [lia |].
      simpl in Hnth_j.
      (* Show that all items in [tl] have start_ofs >= end_ofs item_i *)
      assert (Htl_ge : forall k item_k,
        nth_error tl k = Some item_k -> end_ofs item_i <= start_ofs item_k).
      {
        clear - Hrest.
        revert Hrest. generalize (end_ofs item_i) as base.
        induction tl as [| x xs IHxs]; intros base Hchain k item_k Hnth.
        - destruct k; discriminate.
        - simpl in Hchain. destruct Hchain as [Hx_start [Hx_span Hxs_rest]].
          destruct k as [| k'].
          + simpl in Hnth. injection Hnth as Heq. subst item_k. lia.
          + simpl in Hnth.
            pose proof (valid_item_monotonic x Hx_span) as Hx_le.
            pose proof (IHxs (end_ofs x) Hxs_rest k' item_k Hnth) as Hrec.
            lia.
      }
      pose proof (Htl_ge j' item_j Hnth_j) as Hge.
      unfold item_covers_char in *. lia.
    + (* i > 0, recurse on tl *)
      destruct j as [| j']; [lia |].
      assert (Hij' : i' < j') by lia.
      simpl in Hnth_i, Hnth_j.
      eapply IH; eauto.
Qed.

(** Theorem 2 (Complete Partition / No Gaps):
    Every character offset [c] in the range [cur, target) is covered by an
    item in the chain, and that item is necessarily a content-bearing item
    (Text, Control, or AtomicInline, never OpenTag/CloseTag). *)
Theorem chain_complete_coverage : forall (items : list InlineItem) (cur target c : nat),
  is_contiguous_chain cur target items ->
  cur <= c < target ->
  exists item,
    In item items /\
    item_covers_char item c /\
    item.(item_type) <> OpenTag /\
    item.(item_type) <> CloseTag.
Proof.
  induction items as [| item rest IH]; intros cur target c Hchain Hc.
  - (* Base case: empty list implies cur = target, contradicting cur <= c < target *)
    simpl in Hchain. lia.
  - simpl in Hchain. destruct Hchain as [Hstart [Hspan Hrest]].
    pose proof (valid_item_monotonic item Hspan) as Hmono.
    (* Decide whether c falls into [item] or [rest] *)
    destruct (lt_dec c (end_ofs item)) as [Hlt | Hge].
    + (* c is covered by [item] *)
      exists item.
      split; [left; reflexivity |].
      split; [unfold item_covers_char; lia |].
      (* Prove that [item] cannot be OpenTag or CloseTag because start_ofs < end_ofs *)
      destruct (item_type item) eqn:Htype; simpl in Hspan;
        try (split; discriminate); lia.
    + (* c >= end_ofs item, so c is covered by [rest] *)
      assert (Hc_rest : end_ofs item <= c < target) by lia.
      destruct (IH (end_ofs item) target c Hrest Hc_rest)
        as [item' [Hin [Hcov [HnotOpen HnotClose]]]].
      exists item'.
      split; [right; exact Hin |].
      auto.
Qed.

(** Corollary: Master Audit Guarantee for Blink's InlineItemsBuilder.
    For any valid inline item sequence over a paragraph of length [N],
    every character [c < N] is uniquely partitioned into a measurable/layout
    item (Text, Control, or AtomicInline) without gaps. *)
Corollary blink_inline_items_partition_guarantee :
  forall (N : nat) (items : list InlineItem) (c : nat),
    valid_inline_items N items ->
    c < N ->
    exists item,
      In item items /\
      item_covers_char item c /\
      (item.(item_type) = Text \/
       item.(item_type) = Control \/
       item.(item_type) = AtomicInline).
Proof.
  intros N items c Hvalid Hc.
  unfold valid_inline_items in Hvalid.
  assert (Hc_bounds : 0 <= c < N) by lia.
  destruct (chain_complete_coverage items 0 N c Hvalid Hc_bounds)
    as [item [Hin [Hcov [HnoOpen HnoClose]]]].
  exists item.
  repeat split; try assumption.
  destruct (item_type item); auto; contradiction.
Qed.
```