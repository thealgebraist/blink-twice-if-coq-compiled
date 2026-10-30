# Formal Verification Report: Agent 681
## Topic: Inline Soft Hyphen and Hyphenation Opportunity Offsets
**Chromium Source:** `third_party/blink/renderer/core/layout/inline/inline_break_token.cc` (and interacting modules `line_breaker.cc`, `inline_item_result.cc`)  
**Specification:** CSS Text Module Level 3 §5.4 (Hyphenation: the `hyphens` property) & §5.1 (Line Breaking Details)  
**Formal Theory Target:** `BlinkInlineHyphenationOpportunitySemantics.v`  
**Mathematical Property:** $\text{hyphenated\_line\_width} = \text{text\_segment\_width} + \text{hyphen\_width} \le \text{avail\_width}$ (with graceful overflow fallback when no valid break opportunity fits).

---

## 1. Normative W3C / CSSWG Specification Requirements

In CSS Text Module Level 3, hyphenation is the controlled splitting of words across lines to improve the visual uniformity of inline formatting contexts.

### 1.1 CSS Text 3 §5.4: Soft Hyphens and `hyphens` Property
* **`hyphens: none`**: Words are not hyphenated, even if characters inside the word explicitly suggest hyphenation opportunities (such as U+00AD SOFT HYPHEN). Soft hyphens are suppressed and neither rendered nor measured for line breaking.
* **`hyphens: manual`** (Initial Value): Words are hyphenated only where characters inside the word explicitly suggest hyphenation opportunities:
  * **U+00AD (SOFT HYPHEN / SHY)**: Indicates a conditional hyphenation opportunity. When a line is NOT broken at U+00AD, it generates no visible glyph and consumes zero inline advance width. When a line IS broken at U+00AD, a hyphen glyph (determined by `hyphenate-character`, defaulting to U+2010 HYPHEN or U+002D HYPHEN-MINUS) is rendered immediately following the broken text segment at the end of the line.
  * **U+2010 (HYPHEN)** / **U+002D (HYPHEN-MINUS)**: Unconditional visible hyphens that permit a line break immediately after them without adding an extra hyphen glyph.
* **`hyphens: auto`**: Words may be broken at dictionary-driven or algorithmic hyphenation opportunities in addition to manual opportunities, conditional on language tagging (`lang`) and available hyphenation resources. Explicit U+00AD opportunities take priority over automatic algorithmic opportunities within the same word.

### 1.2 CSS Text 3 §5.4 / CSS Text 4: `hyphenate-character` Width & Line Fitting
1. **Conditional Width Inclusion**: When evaluating whether a prefix of an inline text item ending at offset $k$ (where $k$ is a soft hyphen or auto-hyphenation point) fits within the remaining available inline size ($\text{avail\_width}$), the layout engine MUST compute:
   $$\text{hyphenated\_line\_width}(k) = \text{text\_segment\_width}(\text{start}, k) + \text{hyphen\_width}$$
2. **Fit Constraint**: A hyphenated break at offset $k$ is valid (non-overflowing) if and only if:
   $$\text{text\_segment\_width}(\text{start}, k) + \text{hyphen\_width} \le \text{avail\_width}$$
3. **Break Offset Continuity**: When a line breaks at a soft hyphen at string index $i$ (where `text[i] == U+00AD`), the current line includes the text segment `[start, i + 1)` (the U+00AD code unit itself has 0 advance width in the shaped `ShapeResult`, while the `InlineItemResult::is_hyphenated` flag triggers the addition of `hyphen_width`), and the emitted `InlineBreakToken` records the resume offset $i + 1$ so the next line starts immediately after the soft hyphen. When a line breaks at an automatic hyphenation opportunity at string index $k$, the current line includes `[start, k)` and the `InlineBreakToken` records resume offset $k$.

---

## 2. Chromium Blink Implementation & Invariants

In Blink’s LayoutNG inline layout architecture, inline content is flattened into a DOM-order string (`InlineNodeData::text_content`) paired with a sequence of `InlineItem` ranges.

### 2.1 `InlineBreakToken` (`third_party/blink/renderer/core/layout/inline/inline_break_token.cc`)
`InlineBreakToken` represents the continuation state emitted at the end of a broken line box and passed as input to the construction of the next line box.

```cpp
// Conceptual structure in inline_break_token.h / inline_break_token.cc
class CORE_EXPORT InlineBreakToken final : public BreakToken {
 public:
  static InlineBreakToken* Create(
      InlineNode node,
      const ComputedStyle* style,
      const InlineItemTextIndex& start, // {item_index, text_offset}
      unsigned flags /* kIsForcedBreak, kHasClonedBoxDecorations, etc. */,
      const BreakToken* sub_break_token = nullptr);

  const InlineItemTextIndex& Start() const { return start_; }
  wtf_size_t StartItemIndex() const { return start_.item_index; }
  wtf_size_t StartTextOffset() const { return start_.text_offset; }
};
```

### 2.2 Interaction with `LineBreaker` and `ShapingLineBreaker`
1. **Hyphenation Offset Discovery**:
   * **Soft Hyphens (`kSoftHyphenCharacter = 0x00AD`)**: During shaping and `LineBreaker::BreakText`, U+00AD characters in `text_content` act as break opportunities unless `style.GetHyphens() == Hyphens::kNone`.
   * **Auto Hyphenation (`Hyphenation::LastHyphenLocation`)**: Queries platform hyphenation dictionaries for the largest prefix offset $k < \text{max\_offset}$ where a word can be hyphenated.
2. **Width Accumulation & Invariant Enforcement**:
   * `InlineItemResult::Hyphenate()` computes the shaped inline advance of the hyphen string (`hyphen_string` / `hyphen_shape_result`) and adds `HyphenInlineSize()` to `item_result->inline_size`.
   * Before committing a break at a hyphenation candidate $k$, `ShapingLineBreaker::ShapeLine` and `LineBreaker::BreakText` verify that:
     ```cpp
     LayoutUnit candidate_width = text_segment_width + hyphen_inline_size;
     bool fits = (position_ + candidate_width <= available_width_);
     ```
   * Once the optimal fitting break candidate is selected, `LineBreaker::CreateBreakToken()` constructs the `InlineBreakToken` with `start_.text_offset` equal to the exact post-break character index ($i + 1$ for soft hyphen at $i$, or $k$ for dictionary hyphenation before $k$).

### 2.3 Key Blink Invariants
1. **Bounded Line Width Invariant**: For any non-overflowing hyphenated line break, `hyphenated_line_width = text_segment_width + hyphen_width <= avail_width`.
2. **Non-Negative Widths**: All character advance widths, segment widths, and `hyphen_width` are non-negative integers (`LayoutUnit` fixed-point ticks $\ge 0$).
3. **Strict Forward Progress**: For any non-empty text item starting at `start_offset < end_offset`, the `InlineBreakToken` produced after breaking at a hyphenation opportunity has `StartTextOffset() > start_offset` and `StartTextOffset() <= end_offset`.
4. **Zero-Width Soft Hyphen Unbroken Invariant**: Any U+00AD character that is *not* chosen as the line-ending break point contributes `0` to `text_segment_width`.

---

## 3. Formal Specification & Verification in Rocq (Coq)

Below is the complete, self-contained, admitted-free Rocq formalization `BlinkInlineHyphenationOpportunitySemantics.v`. It models CSS `hyphens` modes, inline characters, U+00AD soft hyphens, automatic dictionary hyphenation opportunities, `ShapingLineBreaker` candidate selection, and `InlineBreakToken` creation.

```coq
(** * BlinkInlineHyphenationOpportunitySemantics.v
    Formal verification of W3C CSS Text 3 §5.4 Inline Soft Hyphen and
    Hyphenation Opportunity Offsets in Chromium Blink
    (third_party/blink/renderer/core/layout/inline/inline_break_token.cc). *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Bool.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Data Types & CSS Specification Primitives *)

(** CSS `hyphens` property values (CSS Text 3 §5.4) *)
Inductive HyphensMode : Type :=
  | HyphensNone
  | HyphensManual
  | HyphensAuto.

(** Classification of inline character positions / break opportunities *)
Inductive CharKind : Type :=
  | CharRegular (advance : Z)       (** Normal glyph with advance >= 0 *)
  | CharSpace (advance : Z)         (** Whitespace break opportunity *)
  | CharSoftHyphen                  (** U+00AD SOFT HYPHEN: 0 intrinsic width *)
  | CharAutoHyphen (advance : Z).   (** Glyph immediately preceding an auto-hyphen point *)

(** Extract intrinsic unbroken advance width of a character in LayoutUnit ticks *)
Definition char_advance (c : CharKind) : Z :=
  match c with
  | CharRegular adv => Z.max 0 adv
  | CharSpace adv => Z.max 0 adv
  | CharSoftHyphen => 0
  | CharAutoHyphen adv => Z.max 0 adv
  end.

(** An inline text buffer is a list of characters. *)
Definition InlineText := list CharKind.

(** Compute the unbroken text segment width over prefix length [len] *)
Fixpoint prefix_text_width (text : InlineText) (len : nat) : Z :=
  match text, len with
  | _, O => 0
  | [], S _ => 0
  | c :: rest, S n => char_advance c + prefix_text_width rest n
  end.

(** Break candidate classification at prefix length [len] (1-based count of chars consumed) *)
Inductive BreakKind : Type :=
  | BreakUnbrokenEnd
  | BreakAtSpace
  | BreakAtSoftHyphen
  | BreakAtAutoHyphen
  | BreakForcedOverflow.

(** A candidate line break evaluated by Blink's LineBreaker *)
Record BreakCandidate : Type := mkBreakCandidate {
  bc_resume_offset : nat;      (** Offset stored in InlineBreakToken::StartTextOffset() *)
  bc_kind : BreakKind;         (** Type of break *)
  bc_text_segment_width : Z;   (** Width of text segment before hyphen *)
  bc_hyphen_width : Z;         (** Width of hyphen glyph (0 if not hyphenated) *)
  bc_total_width : Z           (** hyphenated_line_width = text_segment_width + hyphen_width *)
}.

(** InlineBreakToken emitted by inline_break_token.cc *)
Record InlineBreakToken : Type := mkInlineBreakToken {
  ibt_item_index : nat;
  ibt_start_text_offset : nat;
  ibt_is_hyphenated : bool
}.

(** LineFragment produced alongside InlineBreakToken *)
Record LineFragment : Type := mkLineFragment {
  lf_text_segment_width : Z;
  lf_hyphen_width : Z;
  lf_line_width : Z;
  lf_is_hyphenated : bool;
  lf_break_token : InlineBreakToken
}.

(** ** 2. Blink Hyphenation & Break Opportunity Semantics *)

(** Determines whether character [c] provides a valid break opportunity under [mode],
    and whether breaking after [c] requires appending a visible hyphen glyph. *)
Definition break_opportunity_of_char (mode : HyphensMode) (c : CharKind)
  : option (BreakKind * bool) :=
  match c with
  | CharRegular _ => None
  | CharSpace _ => Some (BreakAtSpace, false)
  | CharSoftHyphen =>
      match mode with
      | HyphensNone => None
      | HyphensManual | HyphensAuto => Some (BreakAtSoftHyphen, true)
      end
  | CharAutoHyphen _ =>
      match mode with
      | HyphensAuto => Some (BreakAtAutoHyphen, true)
      | HyphensNone | HyphensManual => None
      end
  end.

(** Build a BreakCandidate after consuming [len] characters (where [len > 0]) *)
Definition make_candidate
  (text : InlineText) (len : nat) (kind : BreakKind)
  (needs_hyphen : bool) (hyphen_glyph_width : Z) : BreakCandidate :=
  let seg_w := prefix_text_width text len in
  let hyp_w := if needs_hyphen then Z.max 0 hyphen_glyph_width else 0 in
  mkBreakCandidate len kind seg_w hyp_w (seg_w + hyp_w).

(** Collect all valid break candidates across prefix lengths 1 .. length text *)
Fixpoint collect_candidates_aux
  (mode : HyphensMode) (full_text : InlineText) (rem_text : InlineText)
  (idx : nat) (hyphen_glyph_width : Z) : list BreakCandidate :=
  match rem_text with
  | [] => []
  | c :: rest =>
      let curr_len := S idx in
      let rest_candidates :=
        collect_candidates_aux mode full_text rest curr_len hyphen_glyph_width in
      match break_opportunity_of_char mode c with
      | Some (kind, needs_hyphen) =>
          make_candidate full_text curr_len kind needs_hyphen hyphen_glyph_width
          :: rest_candidates
      | None => rest_candidates
      end
  end.

Definition collect_candidates
  (mode : HyphensMode) (text : InlineText) (hyphen_glyph_width : Z)
  : list BreakCandidate :=
  collect_candidates_aux mode text text 0%nat hyphen_glyph_width.

(** Predicate: candidate fits within available width *)
Definition candidate_fits (avail_width : Z) (bc : BreakCandidate) : bool :=
  bc.(bc_total_width) <=? avail_width.

(** Select the furthest fitting candidate (greedy line breaking in Blink LineBreaker) *)
Fixpoint select_last_fitting
  (avail_width : Z) (candidates : list BreakCandidate)
  : option BreakCandidate :=
  match candidates with
  | [] => None
  | bc :: rest =>
      match select_last_fitting avail_width rest with
      | Some best_later => Some best_later
      | None => if candidate_fits avail_width bc then Some bc else None
      end
  end.

(** Top-level Blink LineBreaker + InlineBreakToken::Create step for a text item *)
Definition break_inline_text
  (item_index : nat) (mode : HyphensMode) (text : InlineText)
  (hyphen_glyph_width : Z) (avail_width : Z) : LineFragment :=
  let total_len := List