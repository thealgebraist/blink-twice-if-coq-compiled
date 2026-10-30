### 1. Core Data Structures in Blink Hyphenation vs. CSS Text Level 3 §5.4

In Chromium’s Blink rendering engine (specifically within LayoutNG / `core/layout/inline/`), inline hyphenation bridges W3C CSS Text Level 3 §5.4 specifications with platform-specific dictionary engines (e.g., Hunspell/Minikin on Android/Linux, CoreText on macOS) and ICU `ubrk_` boundary iterators.

```
                     +------------------------------------+
                     |        ComputedStyle::Hyphens      |
                     |       (kNone, kManual, kAuto)      |
                     +-----------------+------------------+
                                       |
             +-------------------------+-------------------------+
             |                         |                         |
      [Hyphens::kNone]         [Hyphens::kManual]         [Hyphens::kAuto]
             |                         |                         |
    No hyphenation             Scan for U+00AD            1. Scan for U+00AD
    Suppress U+00AD            (&shy; opportunities)      2. Query platform
                                                             LayoutHyphenator
```

#### Core C++ Representations in Blink
1. **`Hyphens` Enum (`ComputedStyle`):**
   Maps directly to CSS `hyphens: none | manual | auto`.
   * `Hyphens::kNone`: Words are not hyphenated, even if they contain explicit soft hyphens (`U+00AD`).
   * `Hyphens::kManual`: Words are only hyphenated where characters inside the word explicitly suggest hyphenation opportunities (e.g., `U+00AD` `SOFT HYPHEN`).
   * `Hyphens::kAuto`: Words may be broken at automatic hyphenation opportunities determined by a language-appropriate hyphenation resource (via the `LayoutHyphenator`), in addition to manual opportunities.

2. **`Hyphenation` Base Class (`platform/text/hyphenation.h`):**
   The abstract interface representing a language-specific dictionary engine.
   * `LastHyphenLocation(StringView text, wtf_size_t before_index) -> wtf_size_t`: Returns the largest valid hyphenation byte/character offset strictly less than `before_index`, or `0` if none exists.
   * `FirstHyphenLocation(StringView text, wtf_size_t after_index) -> wtf_size_t`: Returns the smallest valid hyphenation offset strictly greater than `after_index`.
   * `HyphenLocations(StringView text) -> Vector<wtf_size_t, 8>`: Computes all valid dictionary hyphenation offsets within a given word slice.

3. **`ShapingLineBreaker` & `NGLineBreaker` State:**
   Blink does not use a global TeX-style `hyphen_penalty` optimization pass across paragraphs by default in standard inline layout (`NGLineBreaker`). Instead, it uses a greedy line-breaking algorithm via `ShapingLineBreaker`:
   * When a word overflows the `available_width`, `ShapingLineBreaker::ShapeLine` checks if `hyphenation_` is non-null or if `U+00AD` exists.
   * `hyphen_penalty` is implicitly enforced by **preference ordering**: non-hyphenated break opportunities (spaces, `U+200B`) strictly dominate hyphenated breaks on a line unless the word itself overflows the remaining space. In `ScoreLineBreaker` (Blink's paragraph-level optimal line breaker used for `text-wrap: balance` / `pretty`), `kHyphenPenalty` is an explicit heuristic scalar added to the line penalty score when a line ends with a hyphenated break (`LineBreakCandidate::is_hyphenated`).

---

### 2. Hyphenation Boundary Computation

Let a word $W$ be a sequence of Unicode code points of length $N = |W|$, indexed $0 \dots N-1$. A hyphenation opportunity $k \in \{1, \dots, N-1\}$ splits $W$ into a prefix $W[0 \dots k-1]$ of length $k$ and a suffix $W[k \dots N-1]$ of length $N - k$.

#### Minimum Prefix and Suffix Constraints (`min-prefix`, `min-suffix`)
In Blink (`platform/text/hyphenation.h`), platform hyphenators enforce minimum character counts before and after the hyphen:
* `kMinimumPrefixLength` ($L_{\text{pre}}$): Typically `2` in Blink's default configurations (unless overridden by locale-specific rules or CSS Text Level 4 `hyphenate-limit-chars`).
* `kMinimumSuffixLength` ($L_{\text{suf}}$): Typically `2` or `3` depending on the platform dictionary (e.g., `HyphenationMinikin` uses `kMinimumPrefixLength = 2`, `kMinimumSuffixLength = 2`).
* **Total Word Length Threshold:** Any word with $N < L_{\text{pre}} + L_{\text{suf}}$ yields $\emptyset$ automatic hyphenation opportunities.

#### Soft Hyphen (`U+00AD` / `&shy;`) Matching and Precedence
Soft hyphens are zero-width control characters in the un-broken flow.
1. **`hyphens: none`**: `U+00AD` is shaped with zero advance width and ignored by `LineBreakIterator`.
2. **`hyphens: manual`**: `LineBreakIterator` identifies an opportunity immediately after any `U+00AD` index $i$ (so split point $k = i + 1$). Dictionary hyphenation (`Hyphenation` object) is set to `nullptr`.
3. **`hyphens: auto`**: Per CSS Text Level 3 §5.4: *"Conditional hyphenation characters inside a word, if present, take priority over automatic resources when determining hyphenation points within the word."*
   In Blink's `NGLineBreaker`, if a word contains `U+00AD`, `LineBreakIterator` surfaces the `U+00AD` break opportunities first. Automatic dictionary queries via `Hyphenation::LastHyphenLocation` are only invoked on word segments bounded by existing break opportunities or if no manual soft hyphen resolves the overflow cleanly within the sub-segment.

---

### 3. Width Contribution of the Hyphen Glyph

When a break occurs at a hyphenation opportunity $k$ (either via `U+00AD` or automatic dictionary lookup), a visible hyphen glyph must be rendered at the end of the broken line.

```
|<-------------------------- Available Width (W_avail) -------------------------->|
+---------------------------------------------------+--------------------+--------+
| Prefix: W[0 .. k-1]                               | Hyphen Glyph ("-") |        |
| Width:  ShapeWidth(W[0 .. k-1])                   | Width: W_hyphen    |        |
+---------------------------------------------------+--------------------+--------+
|<------------------ Total Candidate Width (W_cand) -------------------->|
```

1. **Hyphen String Resolution:**
   `NGLineBreaker::HyphenString()` resolves the string to append. It inspects `-webkit-locale` / `lang` and the CSS `hyphenate-character` property. If `auto`, it defaults to `U+2010` (`HYPHEN`) if the primary font supports it, falling back to `U+002D` (`HYPHEN-MINUS`).
2. **Width Calculation (`HyphenAdvance`):**
   The resolved hyphen string is shaped using the inline item's `ComputedStyle` font via `ShapeResult::CreateForSpaces` or a cached glyph advance lookup, yielding $W_{\text{hyphen}} \ge 0$.
3. **Overflow Condition:**
   During `ShapingLineBreaker::ShapeLine`, suppose the line currently has remaining space $W_{\text{rem}}$. To break a word $W$ at index $k$:
   $$\text{Width}(W[0 \dots k-1]) + W_{\text{hyphen}} \le W_{\text{rem}}$$
   Crucially, because kerning and ligatures may change when a word is split at $k$, Blink does **not** simply take the pre-shaped width of $W[0 \dots k-1]$ from the full word's `ShapeResult`. Instead, `ShapingLineBreaker` **re-shapes** the prefix $W[0 \dots k-1]$ in isolation (establishing a safe-to-break boundary) and adds $W_{\text{hyphen}}$ to verify it fits within $W_{\text{rem}}$.

---

### 4. Mathematical Invariants

1. **Boundary Strictness Invariant (Auto Hyphenation):**
   For any word $W$ of length $N$, and a dictionary hyphenator parameterized by $(L_{\text{pre}}, L_{\text{suf}})$ with $L_{\text{pre}} \ge 1, L_{\text{suf}} \ge 1$:
   $$\forall k \in \text{AutoOpportunities}(W), \quad L_{\text{pre}} \le k \le N - L_{\text{suf}}$$
2. **Width Feasibility Invariant:**
   If a line break is committed at hyphenation offset $k$ under available width $W_{\text{rem}}$ (and the line is not in a forced-overflow fallback state where $W_{\text{rem}}$ is exceeded by the very first break opportunity on the line):
   $$\text{ShapeWidth}(W[0 \dots k-1]) + W_{\text{hyphen}} \le W_{\text{rem}}$$
3. **Maximal Greedy Selection Invariant (`LastHyphenLocation`):**
   Given a target maximum character offset $M$ (derived from mapping $W_{\text{rem}} - W_{\text{hyphen}}$ back to a character index), the selected break $k^*$ satisfies:
   $$k^* = \max \{ k \in \text{ValidOpportunities}(W) \mid k < M \text{ and } \text{ShapeWidth}(W[0 \dots k-1]) + W_{\text{hyphen}} \le W_{\text{rem}} \}$$
4. **Determinism Invariant:**
   For a fixed tuple $(\text{Style}, \text{Locale}, W, W_{\text{rem}})$, the hyphenation break decision function returns a unique, deterministic option $\text{option } \mathbb{N}$.

---

### 5. Rocq / Coq Formalization (`BlinkHyphenationSemantics.v`)

The following self-contained Rocq (Coq) script formalizes the data structures, CSS Text Level 3 §5.4 mode semantics, width feasibility with hyphen glyph contribution, and proves the core structural and determinism invariants.

```coq
(** * BlinkHyphenationSemantics.v
    Formalization of Chromium Blink Inline Hyphenation vs W3C CSS Text Level 3 §5.4
    Agent 30 Audit Artifact *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

(** ** 1. Core Data Structures *)

(** CSS `hyphens` property values (CSS Text Level 3 §5.4) *)
Inductive HyphensMode : Type :=
  | HyphensNone
  | HyphensManual
  | HyphensAuto.

(** Representation of characters in a word: either a regular glyph or U+00AD (&shy;) *)
Inductive Char : Type :=
  | RegChar (id : nat)
  | SoftHyphen. (* U+00AD *)

Definition Word := list Char.

(** Configuration parameters for Blink's platform Hyphenator *)
Record HyphenatorConfig : Type := mkHyphenatorConfig {
  min_prefix : nat;
  min_suffix : nat;
  hyphen_width : nat;
  (** Abstract dictionary oracle: returns true if offset k is a dictionary break *)
  dict_oracle : Word -> nat -> bool
}.

(** Abstract shaping width function for a sub-slice of a word *)
Parameter shape_width : Word -> nat.

(** Slice helper: prefix of length k *)
Fixpoint take (k : nat) (w : Word) : Word :=
  match k, w with
  | 0, _ => []
  | _, [] => []
  | S k', c :: cs => c :: take k' cs
  end.

(** ** 2. Hyphenation Boundary Computation *)

(** Count of non-soft-hyphen characters, or raw code point length.
    Blink checks code unit / character bounds against min_prefix and min_suffix. *)
Definition word_length (w : Word) : nat := List.length w.

(** Check if an index k (1 <= k < length w) immediately follows a SoftHyphen (U+00AD) *)
Fixpoint is_manual_opportunity (w : Word) (k : nat) : bool :=
  match k, w with
  | 0, _ => false
  | _, [] => false
  | 1, SoftHyphen :: _ => true
  | 1, RegChar _ :: _ => false
  | S k', _ :: cs => is_manual_opportunity cs k'
  end.

(** Check if an index k is a valid automatic dictionary opportunity,
    strictly respecting min_prefix and min_suffix bounds. *)
Definition is_auto_opportunity (cfg : HyphenatorConfig) (w : Word) (k : nat) : bool :=
  let n := word_length w in
  (cfg.(min_prefix) <=? k) &&
  (k + cfg.(min_suffix) <=? n) &&
  (1 <=? k) &&
  (k <? n) &&
  cfg.(dict_oracle) w k.

(** Combined opportunity predicate governed by CSS `hyphens` mode.
    Note: In CSS Text 3 §5.4, if manual opportunities exist in a word,
    they take priority; for point-wise validity we model the union or override. *)
Definition has_any_manual (w : Word) : bool :=
  existsb (fun c => match c with SoftHyphen => true | _ => false end) w.

Definition is_valid_hyphen_opportunity
  (mode : HyphensMode) (cfg : HyphenatorConfig) (w : Word) (k : nat) : bool :=
  let n := word_length w in
  if (k =? 0) || (n <=? k) then false
  else
    match mode with
    | HyphensNone => false
    | HyphensManual => is_manual_opportunity w k
    | HyphensAuto =>
        if has_any_manual w then
          (* Priority to explicit U+00AD inside the word per CSS Text 3 §5.4 *)
          is_manual_opportunity w k
        else
          is_auto_opportunity cfg w k
    end.

(** ** 3. Width Contribution of Hyphen Glyph & Line Breaking *)

(** Total width of breaking word [w] at offset [k], adding hyphen_width *)
Definition hyphenated_prefix_width (cfg : HyphenatorConfig) (w : Word) (k : nat) : nat :=
  shape_width (take k w) + cfg.(hyphen_width).

(** Predicate: break at [k] fits within [avail_width] *)
Definition fits_in_line (cfg : HyphenatorConfig) (w : Word) (k : nat) (avail_width : nat) : bool :=
  hyphenated_prefix_width cfg w k <=? avail_width.

(** Generate candidate indices [1 .. n-1] in descending order to find LastHyphenLocation *)
Fixpoint rev_range (k : nat) : list nat :=
  match k with
  | 0 => []
  | S k' => S k' :: rev_range k'
  end.

(** Blink's greedy hyphenation selection: finds the largest valid k < length w
    such that prefix + hyphen_width <= avail_width. *)
Definition select_hyphen_break
  (mode : HyphensMode) (cfg : Hyp