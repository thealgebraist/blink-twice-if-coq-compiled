### 1. Core Data Structures in Blink Inline Break Token Propagation

In Chromium’s Blink layout engine (LayoutNG), inline formatting contexts are represented as a flat sequence of `InlineItem` objects sharing a single backing `String` (`text_content`) within an `InlineItemsData` structure. Line breaking and fragmentation rely on immutable tokens to thread state across `LineBreaker` invocations.

#### `InlineBreakToken` (`third_party/blink/renderer/core/layout/inline/inline_break_token.h`)
Inherits from `BreakToken`. It captures the exact resumption coordinates within the `InlineNode`'s item list and text backing string.
*   **`item_index_` (`unsigned`):** The 0-based index into `InlineItemsData::items` identifying the `InlineItem` where layout must resume.
*   **`text_offset_` (`unsigned`):** The UTF-16 code unit offset into `InlineItemsData::text_content`. For text items, this satisfies $\text{item.StartOffset()} \le \text{text\_offset\_} < \text{item.EndOffset()}$. For zero-length items (e.g., `kOpenTag`, `kCloseTag`), $\text{text\_offset\_} = \text{item.StartOffset()}$.
*   **`flags_` (`unsigned` bitfield):**
    *   `kIsForcedBreak`: Indicates the break was induced by a mandatory break (`<br>`, `\n` with `pre`).
    *   `kUseFirstLineStyle`: Active only on the first line (or after a forced break if legacy behavior applies).
    *   `kClonedBoxDecorations`: Signals that an ancestor inline box specifies `box-decoration-break: clone`, requiring cloned borders/paddings to be re-applied at the start of the resumed line.
    *   `kHasSubBreakToken`: Indicates presence of a block-in-inline `BlockBreakToken` stored in a trailing flexible array member.

#### `InlineItem` & Coordinates (`ItemIndex`, `TextOffset`)
Every `InlineItem` covers a contiguous half-open range $[\text{start\_offset\_}, \text{end\_offset\_})$ in `text_content`.
*   **`kText`:** $\text{start\_offset\_} < \text{end\_offset\_}$. Contains shaped `ShapeResult` glyphs.
*   **`kAtomicInline` / `kControl`:** $\text{end\_offset\_} = \text{start\_offset\_} + 1$ (represented by `kObjectReplacementCharacter` `U+FFFC` or control char).
*   **`kOpenTag` / `kCloseTag`:** $\text{start\_offset\_} = \text{end\_offset\_}$ (zero-length markers representing `<span>` boundaries).

#### `LineBreakResult` & `LineInfo`
While `LineInfo` aggregates `InlineItemResult` instances for the current line, the termination state of `LineBreaker::NextLine(&LineInfo)` is governed by `LineBreaker::State`:
*   **`kContinue`:** Line still has available inline space.
*   **`kTrailing`:** Processing collapsible trailing whitespace or close tags after the break point has been committed.
*   **`kDone`:** Line break point is finalized; `LineBreaker::CreateBreakToken()` serializes `(current_.item_index, current_.text_offset)` into a new `InlineBreakToken` attached to `LineInfo`.

---

### 2. Splitting Runs, Inline Boxes, and Nested Spans Across Line Boxes

CSS Inline Layout Module Level 3 (§ 3, § 5) and CSS Fragmentation Module Level 3 (§ 3.3, § 4) dictate how inline boxes and runs fragment across line boxes. Blink translates hierarchical inline DOM trees into a flat tape of `InlineItem`s and reconstructs the box hierarchy per line via `InlineBoxState` (`InlineLayoutStateStack`).

```
DOM:  <span>Hello <b>world</b></span>
Tape: [0: kOpenTag <span>] [1: kText "Hello "] [2: kOpenTag <b>] [3: kText "world"] [4: kCloseTag <b>] [5: kCloseTag <span>]
Offs: [0, 0)               [0, 6)              [6, 6)            [6, 11)            [11, 11)           [11, 11)
```

#### Non-Atomic Inline Boxes and Nested Spans (`kOpenTag` / `kCloseTag`)
When a line breaks mid-span (e.g., at `ItemIndex = 3, TextOffset = 8`, inside `"world"`):
1.  **Implicit Closing at Line End:** `LineBreaker` finishes at `(3, 8)`. `InlineLayoutAlgorithm::CreateLine()` iterates over the `LineInfo::Results()`. The `InlineBoxState` stack still holds active states for `[0: <span>]` and `[2: <b>]`. Blink calls `InlineLayoutStateStack::OnCloseTag()` implicitly at the end of the line for all open boxes on the stack.
    *   *CSS Box Decoration Break (`slice` vs `clone`):* If `box-decoration-break: slice` (default), `InlineItemResult::has_edge` for the right border/padding is suppressed on this line. If `clone`, the right border/padding was already accounted for in `LineBreaker` via `cloned_box_decorations_count_`, and is painted at the end of the line.
2.  **Implicit Re-opening at Next Line Start:** On the next line, `InlineLayoutAlgorithm` initializes the `InlineBoxState` stack before processing `LineInfo::Results()` by calling `HandleOpenTag()` for all ancestor `kOpenTag` items that precede the `InlineBreakToken`'s `item_index_` and have not yet encountered their matching `kCloseTag` (`InlineItemsData::GetOpenTagItems()`).
    *   Left borders, margins, and padding are omitted on the resumed box fragment unless `box-decoration-break: clone` is active.

#### Splitting Text Runs (`kText`)
When `LineBreaker::HandleText()` determines that item $i$ covering $[S_i, E_i)$ overflows available width:
1.  `ShapingLineBreaker` queries `LazyLineBreakIterator` (UAX #14) and HarfBuzz `ShapeResult` to find the valid break opportunity offset $T_{break} \in (S_i, E_i)$.
2.  An `InlineItemResult` is emitted for $[T_{start}, T_{break})$ with a newly sliced `ShapeResultView`.
3.  `current_` advances to `(item_index = i, text_offset = T_break)`.
4.  Trailing spaces in $[T_{break}, E_{spaces})$ are consumed under `LineBreakerState::kTrailing` and marked `can_hang`, advancing `current_` further to `(i, E_spaces)` or `(i + 1, E_i)` if $E_{spaces} = E_i$.

#### Splitting Atomic Runs (`kAtomicInline`)
Atomic inlines (`display: inline-block`, replaced elements, inline tables) have a length of 1 code unit (`U+FFFC`, $[S_i, S_i + 1)$).
*   According to CSS Inline 3, atomic inlines are monolithic with respect to inline line breaking: they cannot be split *horizontally* across two lines.
*   If an atomic inline overflows an empty line (`LineInfo::IsEmpty()`), `LineBreaker::HandleAtomicInline()` force-places it on the current line to guarantee forward progress, advancing `current_` to `(i + 1, S_i + 1)`.
*   If the line is not empty, `LineBreaker` rewinds or stops *before* the atomic inline, emitting an `InlineBreakToken` at `(i, S_i)`. The atomic inline is placed at the start of the subsequent line.

---

### 3. Resuming Line Layout

Line resumption is deterministic and stateless outside of `InlineBreakToken`.

```
Line N End:   LineBreaker commits break -> CreateBreakToken(current_.item_index, current_.text_offset)
                                                    |
                                                    v
Line N+1 Beg: LineBreaker(node, space, break_token) -> Rewind/Seek to (token.item_index_, token.text_offset_)
```

1.  **Initialization (`LineBreaker` Constructor):**
    When `InlineLayoutAlgorithm::Layout()` constructs a `LineBreaker` for Line $N+1$, it passes the `InlineBreakToken*` produced by Line $N$.
    ```cpp
    if (break_token) {
      current_.item_index = break_token->ItemIndex();
      current_.text_offset = break_token->TextOffset();
    } else {
      current_.item_index = 0;
      current_.text_offset = 0;
    }
    ```
2.  **Mid-Item Resumption:**
    In `LineBreaker::BreakLine()`, the main loop dispatches based on `items[current_.item_index].Type()`. If `current_.item_index` points to a `kText` item with range $[S_i, E_i)$ and $S_i < \text{current\_.text\_offset} < E_i$, `HandleText()` shapes/slices only the sub-range $[\text{current\_.text\_offset}, E_i)$. The prefix $[S_i, \text{current\_.text\_offset})$ is completely ignored as it was already committed to prior line boxes.
3.  **Zero-Length Tag Alignment:**
    Because `kOpenTag` and `kCloseTag` items have $S_i = E_i$, `text_offset_` alone is ambiguous (multiple tags and a text start can share the exact same `TextOffset`). By pairing `ItemIndex` with `TextOffset`, Blink knows whether a break occurred *before* a tag, *between* nested tags, or *after* a tag at the exact same string offset.
4.  **Termination Condition:**
    When `current_.item_index == items.size()`, `LineBreaker::CreateBreakToken()` returns `nullptr`. `InlineLayoutAlgorithm` observes the null token and exits the line generation loop.

---

### 4. Mathematical Invariants

Let an `InlineNode` be defined by a finite sequence of $N$ items $I = [m_0, m_1, \dots, m_{N-1}]$ over a string of total length $L$. Each item $m_k$ has a type $\tau_k$ and spans $[s_k, e_k)$ such that:
*   $s_0 = 0$, $e_{N-1} = L$
*   $\forall k \in [0, N-1), e_k = s_{k+1}$
*   $\forall k \in [0, N), s_k \le e_k$ (with $s_k < e_k \iff \tau_k \in \{\text{Text}, \text{Atomic}, \text{Control}\}$).

A layout cursor state is a pair $c = (i, t) \in \mathbb{N} \times \mathbb{N}$. A state is **valid** ($\text{Valid}(c)$) iff:
$$\big(0 \le i < N \land s_i \le t \le e_i \land (s_i < e_i \implies t < e_i)\big) \lor (i = N \land t = L)$$

#### Invariant 1: Lexicographical Strict Monotonicity
Let $<_{\text{lex}}$ be the strict lexicographical order on cursor states:
$$(i_1, t_1) <_{\text{lex}} (i_2, t_2) \iff (i_1 < i_2) \lor (i_1 = i_2 \land t_1 < t_2)$$
Because $s_k \le e_k = s_{k+1}$, any transition from item $i_1$ to $i_2 > i_1$ guarantees $t_1 \le e_{i_1} \le s_{i_2} \le t_2$.
For every single line breaking step $\text{NextLine}(c_{\text{in}}) = (l, c_{\text{out}})$ where $c_{\text{in}} \neq (N, L)$:
$$c_{\text{in}} <_{\text{lex}} c_{\text{out}}$$
*Note on Blink Bug Classes:* If a zero-length item (`kOpenTag`) is followed by an unbreakable item that doesn't fit, advancing `item_index` from $i$ to $i+1$ (consuming only the open tag) advances $i$ while keeping $t$ constant. However, if the next line re-opens the tag without consuming the unbreakable item, an infinite loop occurs unless open tags without subsequent content are rewound. Blink enforces that a line cannot consist *solely* of `kOpenTag`s unless followed by a forced break or end-of-context; otherwise, it forces at least one code unit or atomic item onto the line.

#### Invariant 2: Total Text Length Conservation
Let $\mathcal{L} = [l_0, l_1, \dots, l_{k-1}]$ be the sequence of lines produced until $c_k = (N, L)$. Each line $l_j$ transitions from $c_j = (i_j, t_j)$ to $c_{j+1} = (i_{j+1}, t_{j+1})$ and consumes text interval $[t_j, t_{j+1})$.
$$\sum_{j=0}^{k-1} (t_{j+1} - t_j) = t_k - t_0 = L - 0 = L$$
The union of all line text ranges partitions $[0, L)$ without gaps or overlaps.

#### Invariant 3: Upper-Bounded Termination
Define the potential function (measure) $\mu(i, t)$ representing the remaining distance to $(N, L)$:
$$\mu(i, t) = (N - i) + (L - t)$$
Since $i \le N$ and $t \le L$ for all valid states, $\mu(i, t) \in [0, N + L]$. Because every step satisfies $(i_1, t_1) <_{\text{lex}} (i_2, t_2)$ and $t_1 \le t_2$ (by interval monotonicity $e_k = s_{k+1}$), every step strictly decreases $\mu(i, t)$:
$$\mu(c_{\text{out}}) < \mu(c_{\text{in}})$$
Thus, layout of any `InlineNode` terminates in at most $N + L$ line boxes.

---

### 5. Formalization in Rocq / Coq (`BlinkInlineFragmentationSemantics.v`)

The following self-contained Rocq (Coq) module formalizes the tape of `InlineItem`s, `InlineBreakToken` cursor states, the `LineBreaker` step relation, and proves strict monotonicity, termination, and text length conservation without any admitted lemmas.

```coq
(** * BlinkInlineFragmentationSemantics.v
    Formal verification of Chromium Blink's InlineBreakToken propagation,
    line breaking progress invariants, and CSS Inline 3 / Fragmentation 3 conservation. *)

From Coq Require Import Arith PeanoNat Lia List Bool Program.Wf.
Import ListNotations.

(** ** 1. Core Data Structures *)

Inductive InlineItemType : Type :=
  | kText          (* Variable length > 0, breakable