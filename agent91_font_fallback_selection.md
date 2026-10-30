## 1. Core Data Structures in Blink Font Fallback

Blink’s font matching algorithm translates the declarative cascade of CSS Fonts Module Level 4 §5 into an imperative, lazy-evaluation state machine. The architecture decouples the logical font specification from the instantiated platform font data and the geometric text runs.

```
+------------------------+       +-----------------------+
|  FontDescription       |------>|   FontFallbackList    |
|  (CSS font-family,     |       |   (Caches FontData    |
|   weight, style, etc.) |       |    at index i)        |
+------------------------+       +-----------------------+
                                             |
                                             | Instantiate
                                             v
+------------------------+       +-----------------------+
|  CharacterRun /        |       |  FontFallbackIterator |
|  UTF-32 Cluster        |<----->|  (State: family_idx,  |
|  (Code points U_1..U_n)|       |   range_set_idx,      |
+------------------------+       |   fallback_stage)     |
                                 +-----------------------+
                                             |
                                             | Yields
                                             v
                                 +-----------------------+
                                 | FontDataForRangeSet   |
                                 | - SimpleFontData*     |
                                 | - UnicodeRangeSet*    |
                                 +-----------------------+
```

### `FontFallbackList`
Resides in `third_party/blink/renderer/platform/fonts/font_fallback_list.h`. It acts as the per-`FontDescription` memoization table for resolved font instances.
*   **`font_list_`**: A `Vector<scoped_refptr<FontData>, 1>` caching instantiated `FontData` objects (which are either `SimpleFontData` or `SegmentedFontData`).
*   **`family_index_`**: Tracks the current traversal progress through the `FontFamily` linked list defined in `FontDescription`.
*   **Lazy Population**: Calling `FontDataAt(const FontDescription&, unsigned index)` returns `font_list_[index]` if already populated. Otherwise, it walks the `FontFamily` linked list starting from `family_index_`, querying the `FontCache` or `CSSFontSelector` until it resolves a valid `FontData` instance, appends it to `font_list_`, and increments `family_index_`.

### `FontFallbackIterator`
Resides in `third_party/blink/renderer/platform/fonts/font_fallback_iterator.h`. It is a stateful cursor used by `HarfBuzzShaper` to resolve fonts for a given grapheme cluster or character run.
*   **State Variables**:
    *   `current_font_data_index_`: Index into `FontFallbackList::font_list_`.
    *   `segmented_face_index_`: If the current `FontData` at `current_font_data_index_` is a `SegmentedFontData` (e.g., a `@font-face` family consisting of multiple faces segmented by `unicode-range`), this tracks the sub-index within its segments.
    *   `fallback_stage_`: An enum (`kFontGroupFonts`, `kSegmentedFace`, `kPreferencesFonts`, `kSystemFonts`, `kOutOfLuck`) controlling the macro-state of the fallback pipeline.
    *   `unique_font_data_for_range_sets_returned_`: A hash set (`Vector` of `uint32_t` font IDs) used to prevent yielding duplicate `SimpleFontData` instances across the iteration lifecycle.

### `SimpleFontData` & `FontDataForRangeSet`
*   **`SimpleFontData`**: Represents a concrete, realized platform font face (wrapping a `FontPlatformData` and `HarfBuzzFace`). It represents the leaves of the font resolution tree.
*   **`FontDataForRangeSet`**: The return type of `FontFallbackIterator::Next()`. It pairs a `scoped_refptr<SimpleFontData>` with a `scoped_refptr<UnicodeRangeSet>`. The `UnicodeRangeSet` represents the CSS `unicode-range` descriptor restriction (if any). If the font is a local system font without CSS restrictions, the range set is null (semantically covering `[U+0000, U+10FFFF]`).

### `CharacterRun` (Hint List / Grapheme Cluster)
Within `HarfBuzzShaper` (`harfbuzz_shaper.cc`), text is segmented into runs of consistent script, direction, and orientation. Before shaping a segment, Blink extracts grapheme clusters (represented as `Vector<UChar32>` hint lists). This vector of UTF-32 code points is passed to `FontFallbackIterator::Next(const Vector<UChar32>& hint_list)` to drive the coverage check.

---

## 2. Fallback Traversal vs. CSS Fonts 4 §5

CSS Fonts Module Level 4 §5 ("Font Matching Algorithm") specifies that for a given character (or cluster), the user agent must iterate through the prioritized list of `font-family` names, evaluate `@font-face` rules (including `unicode-range`), and verify glyph coverage using the font's character map (`cmap`).

### The `Next(const Vector<UChar32>& hint_list)` State Machine

1.  **Stage 1: `kFontGroupFonts` & `kSegmentedFace` (Author & Generic Families)**
    *   The iterator queries `font_fallback_list_->FontDataAt(font_description_, current_font_data_index_)`.
    *   If `FontData` is a `SimpleFontData`, it wraps it in a `FontDataForRangeSet` (with an unrestricted range) and advances `current_font_data_index_`.
    *   If `FontData` is a `SegmentedFontData`, the state transitions to `kSegmentedFace`. The iterator steps through the `FontDataForRangeSet` segments via `segmented_face_index_`. Once all segments are exhausted, it increments `current_font_data_index_` and reverts to `kFontGroupFonts`.

2.  **Coverage Intersection (`WillUseRange`)**
    *   Before yielding a `FontDataForRangeSet` candidate, the iterator executes `RangeSetContributesForHint(hint_list, candidate)`:
        *   **CSS Range Check**: It checks if any $U \in \text{hint\_list}$ intersects the candidate's `UnicodeRangeSet` (`ranges->IntersectsWith(hint_list)`). This directly implements CSS Fonts 4 §4.5 (`unicode-range`), pruning network downloads or shaping passes for web fonts whose declared range excludes the cluster.
        *   **HarfBuzz / `cmap` Check**: For segmented web fonts or system fallbacks, it invokes `SimpleFontData::CanRenderCombiningCharacterSequence` or queries `HarfBuzzFace::HasGlyph(U)`. Under the hood, HarfBuzz queries the OpenType `cmap` table (typically Format 4 for BMP, Format 12 for Astral planes, and Format 14 for Unicode Variation Sequences) via `hb_font_get_nominal_glyph` or `hb_font_get_variation_glyph`.

3.  **Cluster Coverage Semantics**
    *   Per CSS Fonts 4 §5.2, a base character and its combining marks must be matched as a single unit if possible. Blink passes the entire grapheme cluster in `hint_list`. If the candidate font covers the base character (and any variation selector via `cmap` Format 14), the candidate is yielded to `HarfBuzzShaper`, which then attempts to shape the entire run and verifies that no `.notdef` (glyph ID `0`) is emitted.

---

## 3. System Fallback Termination

If the author-specified `font-family` list (including generic families like `sans-serif` resolved via user preferences) is exhausted and characters in the run remain unshaped (mapped to `.notdef`), `FontDataAt()` returns `nullptr`. `FontFallbackIterator` transitions out of `kFontGroupFonts` into the system fallback stages, corresponding to CSS Fonts 4 §5 Step 6 ("System font fallback").

1.  **`kPreferencesFonts`**: Blink queries priority fallback fonts configured via internal locale/script preferences (e.g., CJK or Emoji preference lists).
2.  **`kSystemFonts` (`UniqueSystemFontForHintList`)**:
    *   Blink invokes `FontCache::GetFontCache()->PlatformFallbackFontForCharacter(...)`.
    *   **Selection**: It passes the first code point of the `hint_list` (accounting for emoji presentation vs. text presentation via `Character::IsEmoji` and variation selectors `U+FE0E`/`U+FE0F`), the resolved `UScriptCode`, and the `FontDescription`'s locale/weight/style to the OS-specific backend (DirectWrite on Windows, CoreText on macOS, FontConfig/Skia on Linux/Android).
    *   If the OS returns a valid `SimpleFontData` that has not been previously yielded (tracked by `unique_font_data_for_range_sets_returned_`), the iterator returns it.
3.  **`kOutOfLuck` (Last Resort / `.notdef` Termination)**:
    *   If the OS backend cannot find a font covering the code point, or if `UniqueSystemFontForHintList` has been queried and failed, `fallback_stage_` transitions to `kOutOfLuck`.
    *   The iterator returns an empty `FontDataForRangeSet` (where `HasFontData()` is `false`).
    *   `HarfBuzzShaper` catches this termination signal, halts the fallback loop, and assigns the remaining unshaped characters to the primary font (the very first valid `SimpleFontData` in `FontFallbackList`), rendering the missing glyph symbol (`.notdef` / tofu), satisfying CSS Fonts 4 §5 Step 7.

---

## 4. Mathematical Invariants

Let $\mathcal{U} = \{0, \dots, \text{0x10FFFF}\}$ be the set of Unicode code points.
Let a font candidate $F_i$ be a tuple $(R_i, C_i)$ where:
*   $R_i \subseteq \mathcal{U}$ is the declared CSS `unicode-range` (for non-segmented fonts, $R_i = \mathcal{U}$).
*   $C_i \subseteq \mathcal{U}$ is the physical character coverage defined by the font's OpenType `cmap` table ($u \in C_i \iff \text{cmap}(u) \neq 0$).

The effective coverage of candidate $F_i$ is $E(F_i) = R_i \cap C_i$.

Let the complete fallback sequence for a given `FontDescription` and character run $S \subseteq \mathcal{U}$ be the finite ordered sequence of candidates:
$$\mathcal{F} = \langle F_1, F_2, \dots, F_k, F_{\text{sys}(1)}, \dots, F_{\text{sys}(m)}, F_{\text{last}} \rangle$$

### Invariant 1: Finite Iteration Termination
The state space of `FontFallbackIterator` is governed by the tuple $\sigma = (\text{stage}, i, j, V)$, where:
*   $\text{stage} \in \{0, 1, 2, 3, 4\}$ (corresponding to `kFontGroupFonts` through `kOutOfLuck`).
*   $i \in [0, N_{\text{families}}]$ is the family index.
*   $j \in [0, N_{\text{segments}}(i)]$ is the segment index.
*   $V \subseteq \mathcal{F}_{\text{all}}$ is the set of unique font IDs already yielded.

We define a lexicographical ranking function $\mathcal{M}(\sigma) \in \mathbb{N}^3$:
$$\mathcal{M}(\sigma) = \left( 4 - \text{stage}, \; N_{\text{families}} - i, \; N_{\text{segments}}(i) - j \right)$$
At every invocation of `Next()`, either $i$ increments, $j$ increments, or $\text{stage}$ increments. In `kSystemFonts` ($\text{stage} = 3$), the iteration is bounded by the finite number of characters in the hint list and deduplicated via $V$. Therefore, $\mathcal{M}(\sigma)$ strictly decreases under the well-founded lexicographical order $<_{\text{lex}}$, guaranteeing termination in $\mathcal{O}(N_{\text{families}} \cdot N_{\text{segments}} + |S|)$ steps.

### Invariant 2: Monotonic Search Step
For any two consecutive calls `Next()` yielding candidates $F_a$ and $F_b$ from $\mathcal{F}$, their indices in the flattened sequence satisfy $a < b$. Furthermore, by the deduplication invariant maintained by `unique_font_data_for_range_sets_returned_`, if $F_a$ and $F_b$ share the same underlying `SimpleFontData` and $R_a = R_b = \mathcal{U}$, $F_b$ is suppressed. Thus, the sequence of yielded `(SimpleFontData, UnicodeRangeSet)` pairs contains no redundant total-range fonts.

### Invariant 3: Exact Character Set Coverage Partitioning
Given an input character run (set of code points) $S \subseteq \mathcal{U}$, the shaping loop partitions $S$ across the sequence $\mathcal{F}$ of length $L = |\mathcal{F}|$. Define the set of characters resolved at step $n \in \{1, \dots, L-1\}$ as:
$$P_n = \left( S \cap E(F_n) \right) \setminus \bigcup_{m=1}^{n-1} P_m$$
And for the terminal fallback step $L$ ($F_{\text{last}}$, which renders `.notdef` via the primary font):
$$P_L = S \setminus \bigcup_{m=1}^{L-1} P_m$$

This construction guarantees an exact set partition of $S$:
1.  **Pairwise Disjointness**: $\forall a \neq b \in \{1, \dots, L\}, \; P_a \cap P_b = \emptyset$.
2.  **Exhaustive Coverage**: $\bigcup_{n=1}^{L} P_n = S$.

---

## 5. Formalization in Rocq / Coq (`BlinkFontFallbackSemantics.v`)

The following script is fully self-contained and compiles cleanly in Coq/Rocq (8.16+ / 9.0) with no admitted proofs.

```coq
(** * BlinkFontFallbackSemantics.v
    Formalization of Chromium Blink FontFallbackIterator vs CSS Fonts 4 §5. *)

From Coq Require Import List Arith Lia Bool.
Import ListNotations.

(** ** 1. Core Data Structures *)

(** A Unicode code point (U+0000 to U+10FFFF). *)
Definition CodePoint := nat.

(** A UnicodeRange represents a closed interval [u_start, u_end]. *)
Record UnicodeRange : Type := mkRange {
  u_start : CodePoint;
  u_end   : CodePoint
}.

(** A UnicodeRangeSet is a list of intervals. An empty list in Blink's 
    UnicodeRangeSet represents the unrestricted universal range [0, 0x10FFFF]. *)
Definition UnicodeRangeSet := list UnicodeRange.

(** Checks if a code point falls within a single UnicodeRange. *)
Definition in_range (u : CodePoint) (r : UnicodeRange) : bool :=
  (r.(u_start) <=? u) && (u <=? r.(u_end)).

(** Checks if a code point is covered by a UnicodeRangeSet. *)
Definition in_range_