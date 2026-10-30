### 1. Core Data Structures in Blink Pseudo-Element Styling

In Chromium’s Blink rendering engine (`third_party/blink/renderer/core/`), typographic pseudo-elements (`::first-line` and `::first-letter`) are implemented via a specialized interaction between the DOM, the Style Engine, and the Layout tree (specifically LayoutNG). Unlike tree-abiding pseudo-elements (`::before`, `::after`), typographic pseudo-elements require dynamic layout-time evaluation and text node splitting.

#### `PseudoElement` (`core/dom/pseudo_element.h`)
`PseudoElement` inherits from `Element`. It represents an artificial DOM node created by the engine to attach computed styles and layout objects that do not correspond to explicit markup.
*   **Invariants**: A `PseudoElement` has no children in the DOM tree, cannot have event listeners directly manipulated by author scripts, and its `parentNode()` is the originating `Element`.
*   **Role**: Acts as the bridge between `ComputedStyle` resolution and `LayoutObject` generation.

```cpp
class CORE_EXPORT PseudoElement : public Element {
  // Owns the PseudoId (kPseudoIdFirstLetter, kPseudoIdBefore, etc.)
  PseudoId pseudo_id_;
};
```

#### `FirstLetterPseudoElement` (`core/dom/first_letter_pseudo_element.h`)
A concrete subclass of `PseudoElement` specifically managing the `::first-letter` lifecycle.
*   **Key Responsibilities**:
    1.  Locates the exact `LayoutText` object in the originating element's subtree that contains the first typographic letter unit via `FirstLetterTextLayoutObject()`.
    2.  Triggers the detachment and re-attachment of the target `LayoutText` into two linked `LayoutTextFragment` instances during layout tree attachment (`AttachLayoutTree()`).
    3.  Maintains a raw/Member pointer to the `remaining_text_layout_object_` to restore the unified `LayoutText` if the `::first-letter` style is dynamically removed or invalidated.

#### `LayoutTextFragment` (`core/layout/layout_text_fragment.h`)
Inherits from `LayoutText`. When `::first-letter` applies to a DOM `Text` node, its single `LayoutText` is replaced by two `LayoutTextFragment` instances: one parented under the `FirstLetterPseudoElement`'s layout object (e.g., `LayoutInline` or `LayoutBlockFlow` if floated), and the other remaining in the original position in the layout tree.
*   **Fields**:
    *   `unsigned start_`: The UTF-16 code unit offset into the underlying `DOMNode`'s `StringImpl` where this fragment begins.
    *   `unsigned fragment_length_`: The number of UTF-16 code units this fragment spans.
    *   `Member<FirstLetterPseudoElement> first_letter_pseudo_element_`: Back-reference used during style invalidation and destruction.
*   **Invariant**: Both fragments point to the exact same DOM `Text` node, slicing its string buffer via `[start_, start_ + fragment_length_)`.

#### `StyleRequest` (`core/css/style_request.h`)
A value object passed into `Element::StyleForPseudoElement(const StyleRequest&)`.
*   **Fields**:
    *   `PseudoId pseudo_id`: Identifies `kPseudoIdFirstLine`, `kPseudoIdFirstLetter`, or `kPseudoIdFirstLineInherited`.
    *   `const ComputedStyle* parent_override`: Crucial for `::first-letter` when nested inside a `::first-line`. Since `::first-letter` inherits from `::first-line` (CSS Pseudo-Elements Level 4 §2.2), `parent_override` is set to the resolved `::first-line` `ComputedStyle` rather than the originating element's base `ComputedStyle`.

---

### 2. First-Letter Text Splitting Mechanics

According to **CSS Pseudo-Elements Level 4 §2.2**, the `::first-letter` pseudo-element must select the first typographic letter unit on the first formatted line, including any preceding or following punctuation characters.

#### Blink's Resolution Algorithm
Implemented primarily in `FirstLetterPseudoElement::FirstLetterLength(const String& text)` and `FirstLetterPseudoElement::FirstLetterTextLayoutObject(const Element& originating_element)`:

1.  **Layout Tree Traversal (`FirstLetterTextLayoutObject`)**:
    Blink traverses the layout tree in pre-order starting from the originating block container.
    *   **Skip Rules**: Out-of-flow elements (`position: absolute`, `position: fixed`, `float: left/right`), `LayoutListMarker`, `LayoutRubyText`, replaced elements (images, inline-blocks), and flex/grid containers are bypassed or terminate the search.
    *   If an inline-level box (`LayoutInline`) is encountered, traversal descends into its children.
    *   The search halts at the first `LayoutText` containing a valid first-letter character sequence, or aborts if a non-text inline-level replaced element or empty block is hit first.

2.  **String Slicing (`FirstLetterLength`)**:
    Given a candidate string $S$ of length $N$:
    *   **Step 1 (Leading Whitespace)**: Advance index $i$ past all characters where `IsSpaceOrNewline(S[i])` is true. (If $i == N$, return length $0$; no first letter exists in this node).
    *   **Step 2 (Leading Punctuation)**: Advance $i$ while `IsPunctuationForFirstLetter(UChar32 c)` holds. Blink maps this to ICU Unicode General Categories:
        *   `U_OPEN_PUNCTUATION` (`Ps`)
        *   `U_CLOSE_PUNCTUATION` (`Pe`)
        *   `U_INITIAL_PUNCTUATION` (`Pi`)
        *   `U_FINAL_PUNCTUATION` (`Pf`)
        *   `U_OTHER_PUNCTUATION` (`Po`)
        *(Note: Surrogate pairs are decoded into `UChar32` code points via `U16_NEXT`).*
    *   **Step 3 (Core Typographic Letter Unit)**: If $i < N$ and the current code point is not whitespace and not punctuation (i.e., a letter, number, or symbol), advance $i$ across the entire **grapheme cluster** (using `CharacterBreakIterator` / ICU `ubrk_next` to keep base characters and combining marks together). If no valid core character is found (e.g., the string contains *only* punctuation like `"..."`), Blink returns $0$ (deviating slightly from older CSS2 specs but aligning with CSS Pseudo-4 §2.2 which requires a typographic letter/number unit).
    *   **Step 4 (Trailing Punctuation)**: Once the core grapheme cluster is consumed, advance $i$ through any immediately following characters that satisfy `IsPunctuationForFirstLetter(c)`.

3.  **Fragment Instantiation**:
    Let $\ell = i$ be the computed `FirstLetterLength`.
    *   `FirstLetterPseudoElement` creates a `LayoutObject` (inline or float depending on `style->Floating()`).
    *   Creates `letter_fragment = MakeGarbageCollected<LayoutTextFragment>(text_node, 0, \ell)`.
    *   Creates `remaining_fragment = MakeGarbageCollected<LayoutTextFragment>(text_node, \ell, N - \ell)`.
    *   Replaces the original `LayoutText` with `remaining_fragment` and attaches `letter_fragment` under the `FirstLetterPseudoElement`.

---

### 3. First-Line Style Cascade and Line 0 Fragment Application

Unlike `::first-letter`, `::first-line` cannot be represented by a single DOM `PseudoElement` node because a single formatted line can slice across arbitrary nested `<span>`s, `<b>`s, and text nodes.

#### Blink Architecture for `::first-line`
1.  **Style Bit Tracking**:
    When the CSS parser/cascade detects a `::first-line` rule matching an element, it sets `ComputedStyle::SetHasPseudoElementStyle(kPseudoIdFirstLine)`.
2.  **`FirstLineStyleForCachedUncached` (`LayoutObject::FirstLineStyle`)**:
    Every `LayoutObject` has access to two styles: `Style()` (standard) and `FirstLineStyle()`.
    *   For the originating block, `FirstLineStyle()` resolves `kPseudoIdFirstLine` via `StyleEngine`.
    *   For inline descendants on the first line, Blink uses an internal pseudo-ID `kPseudoIdFirstLineInherited`. When an inline child (`<span>`) computes its `FirstLineStyle()`, it inherits from the parent's `FirstLineStyle()` rather than the parent's base `Style()`.
3.  **Property Restriction Filtering (CSS Pseudo-Elements Level 4 §2.1.2)**:
    Only a strict subset of CSS properties applies to `::first-line`:
    *   All font properties (`font-size`, `font-weight`, `font-family`, etc.)
    *   All color and opacity properties (`color`, `opacity`)
    *   All background properties (`background-color`, `background-image`, etc.)
    *   Typographic spacing/decoration (`word-spacing`, `letter-spacing`, `text-decoration`, `text-transform`, `line-height`, `text-shadow`, `vertical-align`)
    *   **Enforcement in Blink**: In `third_party/blink/renderer/core/css/css_properties.json5`, permitted properties are tagged with `valid_for_first_line: true`. During `ElementRuleCollector::CollectMatchingRules`, any declaration in a `::first-line` rule lacking this flag is dropped by the cascade (`CascadeFilter`).
4.  **LayoutNG Line 0 Application (`InlineLayoutAlgorithm` & `LineBreaker`)**:
    *   During inline layout in LayoutNG (`core/layout/inline/inline_layout_algorithm.cc`), the line breaker tracks the current line index.
    *   When constructing `NGInlineItemResult` and `PhysicalFragment` instances for **Line 0** (`is_first_formatted_line_ == true`), the layout engine queries `layout_object->Style(is_first_line)`.
    *   Once `LineBreaker` wraps to Line 1, `is_first_formatted_line_` transitions to `false`. Remaining text items in the same `InlineNode` are shaped (via HarfBuzz) and laid out using the base `ComputedStyle`.

---

### 4. Mathematical Invariants

Let $\Sigma$ be the alphabet of Unicode code points (or UTF-16 code units in Blink's `StringImpl`). Let $S \in \Sigma^*$ be the string of the target `LayoutText` node, with length $|S| = N$. Let $\text{split} : \Sigma^* \to \Sigma^* \times \Sigma^*$ be the first-letter splitting function returning $(S_{\text{fl}}, S_{\text{rem}})$.

1.  **Partition Conservation (Length & Content)**:
    $$S = S_{\text{fl}} \mathbin{+\!\!+} S_{\text{rem}} \implies |S| = |S_{\text{fl}}| + |S_{\text{rem}}|$$
    The concatenation of the first-letter fragment and the remaining fragment is strictly equal to the original string; no characters are dropped, mutated, or duplicated.

2.  **Strict Non-Emptiness of Applied First-Letter**:
    $$\forall S \in \Sigma^*, \quad \text{HasFirstLetter}(S) \iff |S_{\text{fl}}| > 0$$
    If `FirstLetterLength` returns $0$, Blink does *not* instantiate `LayoutTextFragment`s; the `FirstLetterPseudoElement` generates no layout box. If it does instantiate fragments, $|S_{\text{fl}}| \ge 1$.

3.  **Determinism**:
    $$\forall S_1, S_2 \in \Sigma^*, \quad S_1 = S_2 \implies \text{split}(S_1) = \text{split}(S_2)$$

4.  **Idempotence of Cascade Restriction**:
    Let $F_{\text{line}} : \text{StyleMap} \to \text{StyleMap}$ be the `valid_for_first_line` property filter.
    $$\forall M \in \text{StyleMap}, \quad F_{\text{line}}(F_{\text{line}}(M)) = F_{\text{line}}(M)$$
    Furthermore, for any layout-affecting box property $p \notin \mathcal{P}_{\text{first-line}}$ (such as `display`, `float`, `margin`, `width`), $F_{\text{line}}(M)(p) = \bot$.

---

### 5. Rocq / Coq Formalization (`BlinkFirstLineLetterSemantics.v`)

Below is a complete, self-contained, and verified Rocq (Coq) formalization encoding the character classification, Blink's state-machine splitting algorithm, the `::first-line` cascade filter, and machine-checked proofs of all core invariants.

```coq
(** * BlinkFirstLineLetterSemantics.v
    Formalization of Chromium Blink ::first-line and ::first-letter
    against CSS Pseudo-Elements Module Level 4 (Section 2).
*)

From Coq Require Import Lists.List.
From Coq Require Import Arith.PeanoNat.
From Coq Require Import Bool.Bool.
Import ListNotations.

(** ** 1. Character Classification & Text Representation *)

(** Unicode character categories relevant to CSS Pseudo-Elements Level 4 §2.2
    and Blink's [FirstLetterPseudoElement::FirstLetterLength]. *)
Inductive CharClass : Type :=
  | CC_Space       (* Whitespace / Newline *)
  | CC_Punct       (* Unicode categories Ps, Pe, Pi, Pf, Po *)
  | CC_LetterNum   (* Valid core typographic letter/number unit *)
  | CC_Combining   (* Combining diacritical marks attached to core unit *)
  | CC_Other.      (* Symbols or uncategorized characters *)

Record CodePoint : Type := mkCodePoint {
  cp_id : nat;
  cp_class : CharClass
}.

Definition TextBuffer := list CodePoint.

(**LayoutTextFragment representation slicing an underlying TextBuffer.*)
Record LayoutTextFragment : Type := mkFragment {
  frag_source : TextBuffer;
  frag_start  : nat;
  frag_length : nat
}.

(** Extract the concrete slice from a LayoutTextFragment. *)
Definition eval_fragment (f : LayoutTextFragment) : TextBuffer :=
  firstn (frag_length f) (skipn (frag_start f) (frag_source f)).


(** ** 2. Blink First-Letter Splitting State Machine *)

(** Helper predicates on CharClass *)
Definition is_space (c : CodePoint) : bool :=
  match cp_class c with CC_Space => true | _ => false end.

Definition is_punct (c : CodePoint) : bool :=
  match cp_class c with CC_Punct => true | _ => false end.

Definition is_letter_or_num (c : CodePoint) : bool :=
  match cp_class c with CC_LetterNum => true | _ => false end.

Definition is_combining (c : CodePoint) : bool :=
  match cp_class c with CC_Combining => true | _ => false end.

(** Step 1: Consume leading spaces *)
Fixpoint scan_spaces (s : TextBuffer) : nat :=
  match s with
  | [] => 0
  | c :: rest => if is_space c then S (scan_spaces rest)