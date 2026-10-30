### 1. Hyphenation Break Opportunity Detection in Blink (`Hyphenator`)

In Chromium Blink’s LayoutNG inline layout engine, automatic hyphenation and line-breaking interact across `LineBreaker` (`core/layout/inline/line_breaker.cc`), `ShapingLineBreaker` (`platform/fonts/shaping/shaping_line_breaker.cc`), and `Hyphenation` (`platform/text/hyphenation.h` and platform-specific implementations).

#### Architectural Flow
1. **Trigger Condition**: During inline item shaping and breaking (`LineBreaker::BreakText`), when a word overflows the available inline space (`available_width`), `ShapingLineBreaker::ShapeLine` is invoked. If `hyphens: auto` is enabled on the `ComputedStyle` and a valid locale-specific `Hyphenation` dictionary is attached to the font description, Blink queries for hyphenation points prior to falling back to emergency word-breaking (`overflow-wrap: break-word` or `word-break: break-all`).
2. **Maximum Prefix Calculation**: Blink computes the maximum character offset `max_prefix_len` within the current word that can geometrically fit into the remaining line space after subtracting the measurement of the hyphen glyph (`hyphen_width`):
   $$\text{available\_for\_prefix} = \text{available\_width} - \text{hyphen\_width}$$
   Using `ShapeResult::OffsetForPosition(available_for_prefix)`, Blink translates this geometric budget into a UTF-16 code unit offset within the word.
3. **Dictionary Query (`LastHyphenLocation`)**: Blink invokes `Hyphenation::LastHyphenLocation(StringView word, unsigned before_index)` where `before_index = max_prefix_len`. The platform hyphenator (e.g., Hunspell/Libhyphen backed `HyphenationMinikin` on Android/Linux or CoreText on macOS) evaluates the word againstLiang's hyphenation algorithm patterns and returns the largest valid hyphenation offset $i < \text{before\_index}$.
4. **Minimum Prefix/Suffix Clamping**: The `Hyphenation` base class enforces geometric and typographic bounds: `kMinimumPrefixLength` (typically 2) and `kMinimumSuffixLength` (typically 2, or platform-configured via hyphenation rules). Any candidate index $i$ that violates $i < \text{min\_prefix}$ or $\text{word\_len} - i < \text{min\_suffix}$ is rejected (returning `0` / no break).

---

### 2. Soft Hyphen (`&shy;` / `U+00AD`) vs. Dictionary Auto-Hyphenation

CSS Text Module Level 3 §5.4 specifies the `hyphens` property (`none`, `manual`, `auto`) and dictates the prioritization and suppression semantics between explicit soft hyphens (`U+00AD`) and automatic dictionary-driven hyphenation.

| Dimension | Soft Hyphen (`U+00AD` / `&shy;`) | Dictionary Auto-Hyphenation (`hyphens: auto`) |
| :--- | :--- | :--- |
| **CSS Property Gate** | Active under `hyphens: manual` (default) and `hyphens: auto`. Disabled under `hyphens: none`. | Active **only** under `hyphens: auto` when `lang` attribute maps to an available hyphenation dictionary. |
| **Detection Mechanism** | Handled directly by `LazyLineBreakIterator` (ICU UAX #14 `LINE_BREAK_SOFT_HYPHEN`) as a natural break opportunity during character scanning in `LineBreaker`. | Invoked dynamically inside `ShapingLineBreaker` only when a word crosses the inline end boundary and fails to fit as a whole. |
| **Glyph Rendering** | Zero-width and invisible when not broken. When a line breaks at `U+00AD`, `LineBreaker::AddHyphen()` synthesizes the visible hyphen glyph from the font (`-` or `U+2010`). | No character exists in the DOM text node. When broken, `ShapingLineBreaker` sets `is_hyphenated = true` on `ShapeResult`, and `LineBreaker` appends the synthesized hyphen string. |
| **Prefix/Suffix Limits** | **Exempt** from `min_prefix` and `min_suffix` constraints. An author can place `&shy;` after the 1st character of a 2-letter word, and Blink will honor it if it fits. | **Strictly bound** by `min_prefix` ($\ge 2$) and `min_suffix` ($\ge 2$). |
| **Precedence (CSS Text 3 §5.4)** | **Overrides automatic hyphenation.** Per CSS Text 3: *"When a word contains explicit hyphenation opportunities (such as U+00AD), those opportunities must be prioritized over automatic resources."* | Suppressed within words containing `U+00AD` (or evaluated only as fallback if sub-segments between soft hyphens still require breaking, though Blink disables dictionary lookup for words containing `U+00AD` unless segments are isolated). |

---

### 3. Formal Invariants

Let a word $W$ have length $L = |W|$ (in characters/clusters), with cumulative advance width function $A : [0, L] \to \mathbb{N}$ (monotonically increasing, $A(0) = 0$). Let $W_{\text{avail}} \in \mathbb{N}$ be the remaining inline space on the current line, and $W_{\text{hyph}} \in \mathbb{N}$ be the inline advance width of the hyphen glyph. Let $P_{\min}$ and $S_{\min}$ denote `min_prefix` and `min_suffix` respectively.

1. **Structural Sub-word Bounds Invariant (Auto-Hyphenation)**:
   For any break opportunity index $i$ selected by automatic dictionary hyphenation:
   $$P_{\min} \le i \le L - S_{\min}$$
   *(Corollary: If $L < P_{\min} + S_{\min}$, the set of valid automatic hyphenation break indices is empty: $\emptyset$.)*

2. **Geometric Inline Fit Invariant**:
   For any hyphenated break index $i$ (whether induced by `U+00AD` or `hyphens: auto`), the width of the prefix substring $W[0..i)$ plus the synthesized hyphen width must not exceed the remaining available inline space:
   $$A(i) + W_{\text{hyph}} \le W_{\text{avail}}$$
   *(Exception: Only violated if the line is currently empty and `overflow-wrap: anywhere` / `break-word` forces an unbreakable fallback, which bypasses `Hyphenator` and breaks without a hyphen.)*

3. **Greedy Maximal Fit Invariant**:
   Among all valid candidate break opportunities $C \subseteq [1, L-1]$ active under the current `hyphens` mode, `ShapingLineBreaker` selects the maximal index $i^* \in C$ satisfying the Geometric Inline Fit Invariant:
   $$\forall j \in C,\; (A(j) + W_{\text{hyph}} \le W_{\text{avail}}) \implies j \le i^*$$

4. **Manual-Over-Auto Priority Invariant**:
   If `hyphens: auto` is active and the word $W$ contains at least one explicit soft hyphen (`U+00AD`), the effective candidate set $C$ is restricted to the explicit soft hyphen indices $C_{\text{manual}}$, suppressing dictionary candidates $C_{\text{dict}}$.

---

### 4. Concrete Rocq / Coq Formalization (`BlinkTextHyphenationBreakSemantics.v`)

The following self-contained Coq file formalizes the CSS Text 3 §5.4 hyphenation modes, Blink's `Hyphenator` and `ShapingLineBreaker` selection semantics, and proves the structural bounds, geometric fit, greedy optimality, and manual-priority theorems without any `Admitted` obligations.

```coq
(** * BlinkTextHyphenationBreakSemantics.v
    Formal audit of Chromium Blink Text Hyphenation (core/layout/inline/ & platform/text/)
    against CSS Text Module Level 3 §5.4 (Hyphenation: the 'hyphens' property).
    Agent 150. *)

From Coq Require Import Arith PeanoNat Lia List Bool.
Import ListNotations.

(** ** 1. Data Types and CSS Text 3 §5.4 Modes *)

Inductive HyphensMode : Type :=
  | HyphensNone   (* hyphens: none   *)
  | HyphensManual (* hyphens: manual *)
  | HyphensAuto.  (* hyphens: auto   *)

Record HyphenationConfig : Type := mkConfig {
  min_prefix   : nat;
  min_suffix   : nat;
  hyphen_width : nat
}.

Record WordInput : Type := mkWord {
  word_len     : nat;
  (** Cumulative glyph advance width for prefix of length i *)
  prefix_width : nat -> nat;
  (** Explicit U+00AD (soft hyphen) positions within the word *)
  soft_hyphens : list nat;
  (** Raw dictionary break positions (e.g. from Liang's algorithm) *)
  dict_hyphens : list nat
}.

(** Well-formedness of soft hyphens: strictly inside the word [1 .. word_len - 1] *)
Definition valid_manual_indices (w : WordInput) : Prop :=
  Forall (fun i => 1 <= i /\ i < word_len w) (soft_hyphens w).

(** ** 2. Blink Hyphenation Filtering and Selection Semantics *)

(** Filter predicate for dictionary auto-hyphenation bounds:
    min_prefix <= i <= word_len - min_suffix (and strictly inside word) *)
Definition auto_bounds_b (cfg : HyphenationConfig) (len i : nat) : bool :=
  (1 <=? i) && (i <? len) &&
  (min_prefix cfg <=? i) && (i + min_suffix cfg <=? len).

(** Manual soft-hyphen bounds: strictly inside the word (1 <= i < len) *)
Definition manual_bounds_b (len i : nat) : bool :=
  (1 <=? i) && (i <? len).

(** Geometric fit predicate: prefix_width(i) + hyphen_width <= avail_space *)
Definition fits_in_space_b (cfg : HyphenationConfig) (w : WordInput) (avail i : nat) : bool :=
  prefix_width w i + hyphen_width cfg <=? avail.

(** CSS Text 3 §5.4 & Blink candidate resolution:
    - HyphensNone: no hyphenation break opportunities.
    - HyphensManual: only explicit U+00AD opportunities.
    - HyphensAuto: if explicit U+00AD opportunities exist in the word,
      prioritize them over automatic dictionary resources; otherwise use
      dictionary opportunities filtered by min_prefix and min_suffix. *)
Definition candidate_indices (mode : HyphensMode) (cfg : HyphenationConfig) (w : WordInput) : list nat :=
  let len := word_len w in
  match mode with
  | HyphensNone => []
  | HyphensManual =>
      filter (manual_bounds_b len) (soft_hyphens w)
  | HyphensAuto =>
      let manual_cands := filter (manual_bounds_b len) (soft_hyphens w) in
      match manual_cands with
      | _ :: _ => manual_cands
      | [] => filter (auto_bounds_b cfg len) (dict_hyphens w)
      end
  end.

(** Blink's ShapingLineBreaker / Hyphenator::LastHyphenLocation selects the
    largest valid candidate index that geometrically fits with the hyphen glyph. *)
Fixpoint max_fitting_index (cfg : HyphenationConfig) (w : WordInput) (avail : nat) (cands : list nat) : option nat :=
  match cands with
  | [] => None
  | i :: rest =>
      let best_rest := max_fitting_index cfg w avail rest in
      if fits_in_space_b cfg w avail i then
        match best_rest with
        | None => Some i
        | Some j => Some (Nat.max i j)
        end
      else best_rest
  end.

Definition select_hyphen_break
  (mode : HyphensMode) (cfg : HyphenationConfig) (w : WordInput) (avail : nat) : option nat :=
  max_fitting_index cfg w avail (candidate_indices mode cfg w).

(** ** 3. Core Helper Lemmas *)

Lemma max_fitting_index_in_and_fits :
  forall cfg w avail cands i,
    max_fitting_index cfg w avail cands = Some i ->
    In i cands /\ fits_in_space_b cfg w avail i = true.
Proof.
  intros cfg w avail cands.
  induction cands as [|x rest IH]; intros i Hsel.
  - discriminate Hsel.
  - simpl in Hsel.
    destruct (fits_in_space_b cfg w avail x) eqn:Hfitx.
    + destruct (max_fitting_index cfg w avail rest) as [j|] eqn:Hrest.
      * injection Hsel as Heq. subst i.
        destruct (Nat.max_spec x j) as [[Hlt Hmax] | [Hge Hmax]]; rewrite Hmax.
        -- destruct (IH j eq_refl) as [Hin_j Hfit_j].
           split; [right; exact Hin_j | exact Hfit_j].
        -- split; [left; reflexivity | exact Hfitx].
      * injection Hsel as Heq. subst i.
        split; [left; reflexivity | exact Hfitx].
    + destruct (IH i Hsel) as [Hin_i Hfit_i].
      split; [right; exact Hin_i | exact Hfit_i].
Qed.

Lemma max_fitting_index_maximal :
  forall cfg w avail cands i k,
    max_fitting_index cfg w avail cands = Some i ->
    In k cands ->
    fits_in_space_b cfg w avail k = true ->
    k <= i.
Proof.
  intros cfg w avail cands.
  induction cands as [|x rest IH]; intros i k Hsel Hin Hfitk.
  - contradiction.
  - simpl in Hsel. simpl in Hin.
    destruct Hin as [Heq | Hin_rest].
    + subst x. rewrite Hfitk in Hsel.
      destruct (max_fitting_index cfg w avail rest) as [j|] eqn:Hrest.
      * injection Hsel as Heq. subst i. lia.
      * injection Hsel as Heq. subst i. lia.
    + destruct (fits_in_space_b cfg w avail x) eqn:Hfitx.
      * destruct (max_fitting_index cfg w avail rest) as [j|] eqn:Hrest.
        -- injection Hsel as Heq. subst i.
           assert (Hk_le_j : k <= j) by (eapply IH; eauto).
           lia.
        -- exfalso.
           clear Hsel Hfitx.
           induction rest as [|y r IHr].
           ++ contradiction.
           ++ simpl in Hrest. simpl in Hin_rest.
              destruct Hin_rest as [Hy | Hr].
              ** subst y. rewrite Hfitk in Hrest.
                 destruct (max_fitting_index cfg w avail