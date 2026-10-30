# Audit Report: Chromium Blink Inline BiDi Resolution vs. UAX #9 & CSS Writing Modes 3
**Auditor**: Agent 7  
**Target Subsystem**: `third_party/blink/renderer/core/layout/inline/` (`NGInlineNode`, `BidiParagraph`, `NGInlineItem`, `InlineBox`) and ICU (`UBiDi`).  
**Reference Specifications**: Unicode Standard Annex #9 (UAX #9, Revision 46+), W3C CSS Writing Modes Level 3 (§ 2 Inline Direction and Bidirectionality).

---

## 1. Core Data Structures & Architecture in Blink Inline BiDi

In Blink's LayoutNG architecture, bidirectional text resolution operates over a flat, pre-processed logical character buffer (`text_content_`) produced during the `NGInlineNode::PrepareLayout` phase (specifically `CollectInlines` and `SegmentText`). CSS directional controls (`unicode-bidi`, `direction`) are translated directly into synthetic Unicode BiDi control characters injected into `text_content_` prior to invoking the underlying ICU `UBiDi` engine.

### 1.1 `TextDirection` (`platform/text/text_direction.h`)
The fundamental base directionality enumeration:
```cpp
enum class TextDirection : uint8_t {
  kLtr = 0,
  kRtl = 1
};
```
**Invariant**: `static_cast<UBiDiLevel>(TextDirection::kLtr) == 0` (even) and `static_cast<UBiDiLevel>(TextDirection::kRtl) == 1` (odd), aligning directly with UAX #9 level parity.

### 1.2 `BidiParagraph` (`core/layout/inline/bidi_paragraph.h`)
Wraps the ICU `UBiDi` state machine to resolve paragraph base direction and character-level embedding levels over a `StringView` representing a single UAX #9 paragraph (delimited by hard line breaks or block boundaries).

```cpp
class CORE_EXPORT BidiParagraph {
  STACK_ALLOCATED();
 public:
  using Level = UBiDiLevel; // uint8_t

  struct Run {
    unsigned start;
    unsigned end;
    Level level;
    
    TextDirection Direction() const { return DirectionFromLevel(level); }
  };
  using Runs = Vector<Run, 32>;

  // Initializes UBiDi and runs UAX #9 stages P2-P3, X1-X8, W1-W7, N0-N2, I1-I2.
  bool SetParagraph(const String&, std::optional<TextDirection> base_direction);
  
  TextDirection BaseDirection() const { return base_direction_; }
  
  // Iterates contiguous logical runs sharing an identical resolved UBiDiLevel.
  unsigned GetLogicalRun(unsigned start, Level* level_out) const;
  
  // Populates visual runs from logical runs via UBiDi_reorderVisual (L2).
  static void IndicesInVisualOrder(const Vector<Level, 32>& levels,
                                   Vector<int32_t, 32>* indices_in_visual_order);
 private:
  ScopedUBiDi ubidi_;
  TextDirection base_direction_ = TextDirection::kLtr;
};
```

### 1.3 `NGInlineItem` & `NGInlineItemsBuilder` (`core/layout/inline/ng_inline_item.h`)
Before `BidiParagraph` runs, `NGInlineItemsBuilder` translates the DOM tree and CSS box properties into a flat logical string and a list of `NGInlineItem`s.

| CSS `unicode-bidi` | CSS `direction` | Injected Prefix (`NGInlineItem::kBidiControl`) | Injected Suffix (`NGInlineItem::kBidiControl`) | UAX #9 Equivalent |
| :--- | :--- | :--- | :--- | :--- |
| `normal` | `ltr` / `rtl` | *None* | *None* | — |
| `embed` | `ltr` | `U+202A` (LRE) | `U+202C` (PDF) | Explicit Embedding |
| `embed` | `rtl` | `U+202B` (RLE) | `U+202C` (PDF) | Explicit Embedding |
| `isolate` | `ltr` | `U+2066` (LRI) | `U+2069` (PDI) | Explicit Isolate |
| `isolate` | `rtl` | `U+2067` (RLI) | `U+2069` (PDI) | Explicit Isolate |
| `bidi-override` | `ltr` | `U+202D` (LRO) | `U+202C` (PDF) | Explicit Override |
| `bidi-override` | `rtl` | `U+202E` (RLO) | `U+202C` (PDF) | Explicit Override |
| `isolate-override`| `ltr` | `U+2068` (FSI) + `U+202D` (LRO) | `U+202C` (PDF) + `U+2069` (PDI) | Isolate + Override |
| `isolate-override`| `rtl` | `U+2068` (FSI) + `U+202E` (RLO) | `U+202C` (PDF) + `U+2069` (PDI) | Isolate + Override |
| `plaintext` | *any* | `U+2068` (FSI) | `U+2069` (PDI) | First-Strong Isolate |

Atomic inlines (`inline-block`, images, replaced elements) are represented in `text_content_` as `U+FFFC` (OBJECT REPLACEMENT CHARACTER, BiDi class `ON` - Other Neutral).

### 1.4 `NGLogicalLineItem` & `BidiRun` Equivalent
In LayoutNG, once `NGInlineNode::SegmentBidiRuns` slices `NGInlineItem`s at level boundaries (assigning `bidi_level_` to each `NGInlineItem`), `NGLineBreaker` breaks the items into lines. For each line, `NGInlineLayoutAlgorithm::CreateLine` constructs `NGLogicalLineItems`. Visual reordering operates on a list of indices into `NGLogicalLineItems` based on their resolved `UBiDiLevel`.

---

## 2. Resolving Embedding Levels (0..125) and Reordering Visual Runs

### 2.1 Embedding Level Resolution (`MAX_DEPTH = 125`)
UAX #9 defines `max_depth = 125`. Valid resolved levels lie in $[0, 126]$ (since rule I1/I2 can increment an explicit level of 125 to 126 for weak/strong characters of opposite parity).
1. **Paragraph Level ($P_2, P_3$)**: `ubidi_setPara` is called with `paraLevel` set to `0` (`kLtr`), `1` (`kRtl`), or `UBIDI_DEFAULT_LTR` (`0xFE`) when `unicode-bidi: plaintext` is active on the block container.
2. **Explicit Levels and Directions ($X_1 - X_8$)**:
   - Maintains a directional status stack of size `max_depth + 2` (127 entries). Each entry contains `(embedding_level, override_status, isolate_status)`.
   - `LRE`/`RLE`/`LRO`/`RLO`/`LRI`/`RLI`/`FSI` push to the stack if the new level $\le 125$ and overflow counters (`overflow_isolate_count`, `overflow_embedding_count`) are 0. Otherwise, overflow counters increment.
   - `PDI` matches the last open isolate (`LRI`, `RLI`, `FSI`), unwinding any unclosed embeddings (`LRE`, `RLE`, `LRO`, `RLO`) inside it.
   - `PDF` pops the last embedding/override if `overflow_embedding_count == 0`, stopping at an isolate boundary.
3. **Isolating Run Sequences ($X_{10}$)**:
   - UAX #9 groups level runs into *isolating run sequences* across matched `LRI`/`RLI`/`FSI` $\leftrightarrow$ `PDI` pairs. An isolate sequence acts as a single neutral (`ON`) character to its surrounding sequence, while inside the sequence, text across an intermediate isolate is joined directly.
4. **Weak ($W_1 - W_7$) and Neutral ($N_0 - N_2$) Resolution**:
   - Resolves `NSM`, `EN`, `ES`, `ET`, `AN`, `CS`, paired brackets (`N0`, BPA), and remaining neutrals (`B`, `S`, `WS`, `ON`, `FSI`, `LRI`, `RLI`, `PDI`) to either `L` or `R` based on surrounding strong types and the isolating run sequence's `sos` (start-of-sequence) and `eos` (end-of-sequence) types.
5. **Implicit Levels ($I_1, I_2$)**:
   - Let $e \in [0, 125]$ be the embedding level of a character after stage $N_2$, and $t \in \{L, R, AN, EN\}$ be its resolved character type:
   $$
   \text{level}(e, t) = \begin{cases} 
   e + 1 & \text{if } e \equiv 0 \pmod 2 \land t \in \{R\} \\
   e + 2 & \text{if } e \equiv 0 \pmod 2 \land t \in \{AN, EN\} \\
   e + 1 & \text{if } e \equiv 1 \pmod 2 \land t \in \{L, AN, EN\} \\
   e     & \text{otherwise}
   \end{cases}
   $$
   *Note*: Consequently, the maximum possible final resolved level is $125 + 1 = 126$ (when $e = 125$ is odd and $t \in \{L, AN, EN\}$).

### 2.2 Line Break Reset (Rule $L_1$) & Visual Reordering (Rule $L_2$)
Crucially, UAX #9 splits resolution into **Paragraph-level resolution** ($P_1 - I_2$) and **Line-level resolution** ($L_1 - L_4$).
In Blink:
1. **Pre-line-breaking**: `NGInlineNode::SegmentBidiRuns` resolves $P_1 - I_2$ across the *entire paragraph* once.
2. **Post-line-breaking ($L_1$ Reset)**: After `NGLineBreaker` produces a single line, `NGInlineLayoutAlgorithm::BidiReorder` applies Rule $L_1$:
   - Trailing whitespace (`WS`, `FSI`, `LRI`, `RLI`, `PDI`) and isolate formatting characters at the end of the line (or preceding a segment/paragraph separator `S`/`B`) have their resolved levels reset to the **paragraph base embedding level** (`base_direction_`).
3. **Visual Reordering ($L_2$)**:
   Given a sequence of $N$ visual items on a line with levels $L = [l_0, l_1, \dots, l_{N-1}]$:
   - Let $l_{\max} = \max_{0 \le i < N} l_i$, and $l_{\min\_odd} = \min (\{ l_i \mid l_i \equiv 1 \pmod 2 \} \cup \{ \infty \})$.
   - If $l_{\min\_odd} = \infty$ (all levels are even, e.g., all $0$), no reordering is required; the identity permutation $[0, 1, \dots, N-1]$ is returned.
   - Otherwise, for each level $k$ descending from $l_{\max}$ down to $l_{\min\_odd}$:
     - Find every maximal contiguous subsegment $[a, b]$ ($0 \le a \le b < N$) where $\forall i \in [a, b], l_i \ge k$.
     - Reverse the order of elements within $[a, b]$ in-place.

---

## 3. LTR vs. RTL Paragraph Base Direction Heuristics

Blink determines the paragraph base direction via two distinct entry points depending on CSS `unicode-bidi` and HTML `dir="auto"`:

### 3.1 UAX #9 Rule P2 & P3 (`BidiParagraph::ResolveParagraphDirection`)
Used for `unicode-bidi: plaintext` and FSI (`U+2068`) resolution:
1. **Rule P2**: Scan characters in the paragraph.
   - When an isolate initiator (`LRI`, `RLI`, `FSI`) is encountered, skip all characters up to and including its matching `PDI` (or the end of the paragraph if unmatched).
   - Ignore embedding/override controls (`LRE`, `RLE`, `LRO`, `RLO`, `PDF`) and all weak/neutral characters.
   - Stop at the first character with a strong BiDi class: `L`, `R`, or `AL` (Arabic Letter).
2. **Rule P3**:
   - If a strong character is found: return `kLtr` if it is `L`, or `kRtl` if it is `R` or `AL`.
   - If no strong character is found: default to `kLtr` (0) in pure UAX #9 P3. *(Note: Blink's `BidiParagraph::SetParagraph` falls back to `kLtr` when `ubidi_getParaLevel` has no strong characters).*

### 3.2 HTML `dir="auto"` vs. CSS `unicode-bidi: plaintext`
Blink implements `ResolveParagraphDirection` in `BidiParagraph` using ICU's `ubidi_getBaseDirection` or a custom loop scanning `u_charDirection(c)`.
- **Divergence / Nuance**: For HTML `dir="auto"` (`Element::DetermineDirectionality`), the HTML specification skips `<script>`, `<style>`, `<textarea>`, and elements with an explicit `dir` attribute, rather than relying purely on injected `LRI`/`RLI`/`FSI`..`PDI` pairs in the layout text buffer. Once inside LayoutNG (`unicode-bidi: plaintext`), however, child blocks or inlines with `unicode-bidi: isolate` have already been wrapped in `U+2066`/`U+2067`/`U+2068`..`U+2069`, so P2's isolate-skipping rule naturally ignores them.

---

## 4. Mathematical Invariants, Edge Cases, and Divergences

### 4.1 Core Mathematical Invariants
1. **Level Bounds**:
   $$\forall i \in [0, N), \quad 0 \le \text{level}[i] \le 126$$
   Specifically, explicit levels $\le 125$, and implicit resolution ($I_1, I_2$) adds at most $1$ to odd level $125$ ($125 + 1 = 126$) or $2$ to even level $124$ ($124 + 2 = 126$).
2. **Parity-Direction Homomorphism**:
   $$\text{Direction}(\text{level}) = \begin{cases} \text{LTR