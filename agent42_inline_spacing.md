## 1. Core Data Structures in Blink Inline Text Spacing

In Chromium's Blink layout engine (specifically LayoutNG and the HarfBuzz shaping integration in `third_party/blink/renderer/platform/fonts/shaping/`), inline spacing, tracking, and justification are applied directly to shaped glyph runs or calculated during inline layout item construction.

### `ShapeResult` (`shape_result.h`)
`ShapeResult` encapsulates the output of HarfBuzz text shaping for a contiguous text run. It is hierarchical:
```cpp
class PLATFORM_EXPORT ShapeResult : public RefCounted<ShapeResult> {
  // ...
  Vector<scoped_refptr<RunInfo>, 1> runs_;
  LayoutUnit width_; // Total advance width of the shaped result
  unsigned start_index_;
  unsigned num_characters_;
  unsigned num_glyphs_ : 30;
  unsigned direction_ : 1; // TextDirection (LTR / RTL)
  unsigned has_vertical_offsets_ : 1;
};
```
Each `ShapeResult::RunInfo` represents a single HarfBuzz run with a uniform `hb_script_t`, `hb_direction_t`, and `SimpleFontData`:
```cpp
struct RunInfo : public RefCounted<RunInfo> {
  scoped_refptr<SimpleFontData> font_data_;
  hb_direction_t direction_;
  CanvasRotationInVertical canvas_rotation_;
  hb_script_t script_;
  GlyphDataCollection glyph_data_; // Contiguous array of HarfBuzzGlyphData
  float width_;                    // Sub-pixel float accumulator for the run
  unsigned start_index_;
  unsigned num_characters_;
};
```
Within `RunInfo`, `HarfBuzzGlyphData` stores individual glyph metrics and UTF-16 character cluster mappings:
```cpp
struct HarfBuzzGlyphData {
  uint16_t glyph;
  uint16_t character_index; // Offset relative to RunInfo::start_index_
  bool safe_to_break_before : 1;
  float advance;            // Horizontal/vertical advance in CSS pixels (float)
  FloatPoint offset;        // x_offset, y_offset (GPOS kerning/mark attachment)
};
```

### `ShapeResultSpacing<TextContainerType>` (`shape_result_spacing.h`)
`ShapeResultSpacing` is the stateful mutator/calculator used by Blink to apply CSS `letter-spacing`, `word-spacing`, and `text-align: justify` expansion over either a `String` (16-bit/8-bit text) or an `NGInlineItemsBuilder` text buffer.
```cpp
template <typename TextContainerType>
class PLATFORM_EXPORT ShapeResultSpacing final {
  STACK_ALLOCATED();
 public:
  explicit ShapeResultSpacing(const TextContainerType&, bool allow_tabs = false);
  
  void SetSpacing(float letter_spacing, float word_spacing);
  void SetExpansion(float expansion, TextDirection, 
                    bool allows_leading_expansion = false,
                    bool allows_trailing_expansion = false);
  
  // Computes spacing for the current glyph cluster and updates internal expansion state
  float ComputeSpacing(unsigned index, float& offset, bool is_cursive = false);

 private:
  const TextContainerType& text_;
  float letter_spacing_ = 0;
  float word_spacing_ = 0;
  float expansion_ = 0;               // Remaining pixel delta to distribute
  float expansion_per_opportunity_ = 0;
  unsigned expansion_opportunity_count_ = 0;
  bool is_after_expansion_ = false;   // Tracks adjacent expansion suppression
  bool allows_leading_expansion_ = false;
  bool allows_trailing_expansion_ = false;
  bool has_spacing_ = false;
  bool normalize_space_ = false;
  bool allow_tabs_ = false;
};
```

### `NGJustificationUtils` / `TextJustifier` (`ng_justification_utils.cc`)
In LayoutNG, line justification is orchestrated by `NGJustificationUtils` (operating on `NGLogicalLineItems`), which acts as the modern `TextJustifier`. It configures `ShapeResultSpacing<String>` across the line's `text_content` and invokes `ShapeResult::ApplySpacing` to mutate the underlying `HarfBuzzGlyphData::advance` and `HarfBuzzGlyphData::offset` fields.

### `SpacingParameters` (`ComputeSpacingParameters`)
When `ShapeResult::ApplySpacing` iterates over glyph clusters, it packages cluster-level parameters into an internal struct passed to `ShapeResultSpacing::ComputeSpacing`:
```cpp
struct ComputeSpacingParameters {
  unsigned index;          // Absolute UTF-16 character index in TextContainerType
  float original_advance;  // Base advance of the cluster before spacing
};
```

---

## 2. Justification Algorithm (CSS Text Level 3 §8)

CSS Text Level 3 §8 defines justification (`text-justify: auto` / `inter-word` / `inter-character`) as the distribution of the remaining unoccupied inline space $\Delta W = W_{\text{available}} - W_{\text{line}}$ across discrete **expansion opportunities**.

In Blink, justification is executed in a **two-pass algorithm** over the line's text content:

### Pass 1: Counting Expansion Opportunities (`CountExpansionOpportunities`)
Blink scans the UTF-16 code units $[i_{\text{start}}, i_{\text{end}})$ of the line (`Character::ExpansionOpportunityCount`). It maintains a state variable `bool is_after_expansion` initialized to `!allows_leading_expansion`.

1. **Word Separators (Spaces):**
   If $c_i \in \{\text{U+0020 (SPACE)}, \text{U+00A0 (NO-BREAK SPACE)}, \text{U+3000 (IDEOGRAPHIC SPACE)}\}$ (and U+0009 if `allow_tabs_` is false and normalized):
   - Increment `expansion_opportunity_count_`.
   - Set `is_after_expansion = true`.
   *(Note: Pursuant to CSS Text 3 §8.1, every typographic space character constitutes its own expansion opportunity, even if consecutive).*

2. **CJK / Ideographic Boundaries (`Character::IsCJKIdeographOrSymbol`):**
   If $c_i$ is classified as a CJK ideograph, Hiragana, Katakana, Hangul, or CJK symbol:
   - **Leading / Pre-Character Expansion:** If `!is_after_expansion` is true (meaning the preceding character did not already emit a trailing expansion opportunity at this boundary, and it is not a forbidden leading edge), increment `expansion_opportunity_count_`.
   - **Trailing / Post-Character Expansion:** Increment `expansion_opportunity_count_` and set `is_after_expansion = true`.
   - **Trailing Suppression:** If $c_i$ is the final character of the run and `!allows_trailing_expansion` is true, decrement `expansion_opportunity_count_` (suppressing expansion after the last glyph on the line).

3. **Cursive Scripts (Arabic, Syriac, N'Ko, etc.):**
   Characters where `Character::IsCursiveScript(c)` is true cannot be expanded via inter-character spacing without breaking cursive ligatures. They set `is_after_expansion = true` without incrementing the count, preventing an adjacent CJK character from inserting a leading expansion opportunity against them.

4. **Default (Latin, Cyrillic, Greek, etc.):**
   Set `is_after_expansion = false`. No inter-character opportunity is added.

### Pass 2: Distributing $\Delta W$ (`ShapeResultSpacing::SetExpansion` & `ComputeSpacing`)
Once the total count $N_{\text{opp}} = \text{expansion\_opportunity\_count\_}$ is known for the line:
$$\text{expansion\_per\_opportunity\_} = \begin{cases} \frac{\Delta W}{N_{\text{opp}}} & \text{if } N_{\text{opp}} > 0 \\ 0 & \text{if } N_{\text{opp}} = 0 \end{cases}$$

As `ApplySpacing` traverses each glyph cluster at character index $i$, `ComputeSpacing(index, offset)` re-evaluates the exact same state machine (`is_after_expansion_`):
```cpp
float ShapeResultSpacing<TextContainerType>::NextExpansion() {
  if (!expansion_opportunity_count_)
    return 0;
  expansion_ -= expansion_per_opportunity_;
  if (!--expansion_opportunity_count_) {
    // Absorb floating-point rounding residual on the final opportunity!
    return expansion_per_opportunity_ + expansion_;
  }
  return expansion_per_opportunity_;
}
```
- **Pre-cluster expansion (CJK after non-expanding character):**
  Calls `NextExpansion()`, adds the result to both `spacing` (which increases the glyph's `advance`) and `offset` (which shifts the glyph's rendering `x_offset` rightward by the expansion amount so the space visually appears *before* the CJK glyph).
- **Post-cluster expansion (Space or CJK trailing):**
  Calls `NextExpansion()` and adds it to `spacing` (increasing `advance` only, placing the space *after* the glyph).

---

## 3. Letter-Spacing and Word-Spacing Addition (CSS Text Level 3 §6)

CSS Text Level 3 §6 specifies `word-spacing` (§6.1) and `letter-spacing` (§6.2). In Blink, these are applied per **typographic character unit (grapheme cluster)** represented by a HarfBuzz cluster in `ShapeResult::ApplySpacingImpl`:

```cpp
float ShapeResult::ApplySpacingImpl(ShapeResultSpacing<TextContainerType>& spacing, int text_start_offset) {
  float offset = 0;
  float total_space = 0;
  for (auto& run : runs_) {
    if (!run) continue;
    float total_space_for_run = 0;
    for (wtf_size_t i = 0; i < run->glyph_data_.size(); i++) {
      HarfBuzzGlyphData& glyph_data = run->glyph_data_[i];
      
      // Skip non-final glyphs within a multi-glyph cluster!
      if (i + 1 < run->glyph_data_.size() &&
          glyph_data.character_index == run->glyph_data_[i + 1].character_index) {
        continue;
      }
      // ...
```

### Cluster Boundary Resolution
HarfBuzz assigns identical `character_index` values to all glyphs belonging to the same grapheme cluster (e.g., a base character + combining diacritical marks, or a multi-glyph ligature). Blink skips all glyphs in a cluster except the **last glyph** ($i$ where $\text{cluster}(i) \neq \text{cluster}(i+1)$). Thus, spacing is applied once per shaped cluster, never splitting a base glyph from its combining marks.

### Calculating Cluster Spacing (`ComputeSpacing`)
For the cluster starting at character index `index` ($c = \text{text\_}[\text{index}]$):
1. **Control & Zero-Width Suppression:**
   If `Character::TreatAsZeroWidthSpaceInComplexScript(c)` is true (e.g., ZWNJ U+200C, ZWJ U+200D, SOFT HYPHEN U+00AD, control characters), `ComputeSpacing` immediately returns `0.0f` (unless $c$ is a tab and `allow_tabs_` is false).
2. **Word-Spacing (`word_spacing_`):**
   If `Character::TreatAsSpace(c)` is true (U+0020, U+00A0, or U+0009 when normalized) or $c == \text{U+3000}$ (Ideographic Space):
   $$\text{space} \mathrel{+}= \text{word\_spacing\_}$$
3. **Letter-Spacing (`letter_spacing_`):**
   If `letter_spacing_ != 0` and `!Character::IsCursiveScript(c)`:
   $$\text{space} \mathrel{+}= \text{letter\_spacing\_}$$
   *(Compliance Note: CSS Text Level 3 §6.2 mandates that if a script is cursive, the UA must not apply letter-spacing between connected glyphs if doing so would break the cursive connection. Blink enforces this via `is_cursive` / `Character::IsCursiveScript`).*
4. **Mutating the Glyph Metrics:**
   ```cpp
   float space = spacing.ComputeSpacing( params, offset );
   glyph_data.advance += space;
   glyph_data.offset.Move(offset, 0);
   total_space_for_run += space;
   ```
   Finally, `run->width_ += total_space_for_run`, and the parent `ShapeResult::width_` is updated to `LayoutUnit::FromFloatRound(total_width)`.

---

## 4. Mathematical Invariants

Let a line consist of a sequence of $K$ shaped clusters $C = (c_0, c_1, \dots, c_{K-1})$, each having an initial shaped advance $a_k \in \mathbb{R}$, initial x-offset $x_k \in \mathbb{R}$, letter-spacing contribution $l_k \in \mathbb{R}$, word-spacing contribution $w_k \in \mathbb{R}$, pre-expansion flag $e^{\text{pre}}_k \in \{0, 1\}$, and post-expansion flag $e^{\text{post}}_k \in \{0, 1\}$.

### Invariant 1: Opportunity Count Conservation
The number of expansion opportunities counted in Pass 1 ($N_{\text{opp}}$) is strictly equal to the sum of pre-cluster and post-cluster expansion triggers fired in Pass 2:
$$N_{\text{opp}} = \sum_{k=0}^{K-1} \left( e^{\text{pre}}_k + e^{\text{post}}_k \right)$$
Because both passes execute the identical deterministic finite automaton over the same code-unit range $[i_{\text{start}}, i_{\text{end}})$ with identical initial states (`allows_leading_expansion`, `allows_trailing_expansion`), `expansion_opportunity_count_` reaches $0$ on and only on the final expansion trigger of the line.

### Invariant 2: Exact Total Expansion Absorption
Let $\Delta W$ be the target expansion delta passed to `SetExpansion`. In ideal real arithmetic (and in Blink's residual-absorbing floating-point arithmetic via `expansion_per_opportunity_ + expansion_` when `--expansion_opportunity_count_ == 0`), if $N_{\text{opp}} > 0$, the sum of expansion amounts $\delta_j$ returned by the $N_{\text{opp}}$ invocations of `NextExpansion()` satisfies:
$$\sum_{j=1}^{N_{\text{opp}}} \delta_j = \left( \sum_{j=1}^{N_{\text{opp}}-1} \frac{\Delta W}{N_{\text{opp}}} \right) + \left( \frac{\Delta W}{N_{\text{opp}}} + \left( \Delta W - N_{\text{opp}} \cdot \frac{\Delta W}{N_{\text{opp}}} \right) \right) = \Delta W$$

### Invariant 3: Target Inline Width Conservation
Let $W_{\text{base}} = \sum_{k=0}^{K-1} a_k$ be the unspaced shaped width, and $W_{\text{track}} = \