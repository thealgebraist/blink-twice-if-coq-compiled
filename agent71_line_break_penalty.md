### 1. Core Data Structures in Blink Line Breaking

In Chromium’s Blink rendering engine (specifically within the `InlineLayoutAlgorithm` / LayoutNG pipeline), line breaking is resolved over a flattened sequence of `InlineItem` instances stored in `InlineNodeData`. The behavior is governed by the `white-space`, `word-break`, `line-break`, `overflow-wrap`, and `text-wrap` properties as specified in **CSS Text Module Level 3 §5**.

#### `LineBreaker` (`third_party/blink/renderer/core/layout/inline/line_breaker.h`)
The `LineBreaker` class acts as a stateful scanner and width-accumulator that iterates over the `InlineItem` list to produce a `LineInfo` representing a single formatted line.
*   **`LineBreakerMode`**: Enumerates the operational phase: `kContent` (actual layout), `kMinContent` (computing intrinsic minimum width where every soft break opportunity is taken), or `kMaxContent` (computing intrinsic maximum width where no soft breaks are taken).
*   **`item_index_` & `offset_`**: Track the current cursor position within the `InlineItemsData` text buffer (UTF-16 `String` backed by `HarfBuzzShaper` runs).
*   **`current_width_` (`LayoutUnit`)**: Fixed-point representation (typically $1/64\text{th}$ of a CSS pixel) of the inline advance accumulated from the line's start to the current cursor.
*   **`available_width_` (`LayoutUnit`)**: The inline size constraint of the current line box, adjusted for floats and indents.
*   **`LazyLineBreakIterator`**: Wraps ICU’s `icu::BreakIterator` implementing Unicode Standard Annex #14 (UAX #14) tailored by CSS `line-break` (`auto`, `loose`, `normal`, `strict`, `anywhere`) and `word-break` (`normal`, `break-all`, `keep-all`).

#### `BreakOpportunity` & `InlineItemResult`
While scanning, `LineBreaker` evaluates candidate break points, materializing them into `InlineItemResult` structures and tracking the optimal break point found so far via an internal state struct (`BreakOpportunity` / `LineBreakCandidate`):
*   **`item_index` (`unsigned`) & `text_offset` (`unsigned`)**: The exact DOM/text coordinates of the break.
*   **`inline_size` (`LayoutUnit`)**: The total inline advance of the line if broken at this candidate, inclusive of trailing hangable whitespace adjustments and hyphenation advances.
*   **`can_break_after` (`bool`)**: Set by querying `LazyLineBreakIterator` and CSS rules.
*   **`is_hyphenated` (`bool`)**: Indicates whether breaking here requires inserting a visible hyphen glyph (via `Hyphenation` dictionary or U+00AD Soft Hyphen).
*   **`break_type`**: Categorizes the break according to CSS Text Level 3 §5:
    *   `kNormal`: Standard UAX #14 break opportunity (e.g., U+0020 Space).
    *   `kHyphen`: Soft hyphen or auto-hyphenation point.
    *   `kOverflow` / `kEmergency`: Unbreakable cluster boundary used only when `overflow-wrap: anywhere | break-word` is triggered to prevent line box overflow.
    *   `kForced`: Mandatory break (e.g., U+000A LF, `<br>`).

#### `LineBreakPenaltyConfig` & `ScoreLineBreaker` (`score_line_breaker.h`)
When CSS `text-wrap: pretty` (an extension building upon CSS Text 3 §5 and formalized in CSS Text 4) is active, Blink invokes `ScoreLineBreaker` alongside `LineBreakCandidateContext`. This replaces greedy line-by-line consumption with a paragraph-level penalty minimization pass. `LineBreakPenaltyConfig` (encapsulated as `ScoreLineBreaker` constants and `LineInfo` heuristics) defines the weights:
*   `kLastLinePenalty`: Penalty multiplier for leaving an isolated short word (typographic widow/orphan at the paragraph end).
*   `kHyphenPenalty`: Base penalty added when a candidate relies on `is_hyphenated == true`.
*   `kConsecutiveHyphenPenalty`: Additional penalty when consecutive lines terminate with hyphens.
*   `kShortLinePenalty`: Demerit applied when the line fill ratio falls below a structural threshold.

---

### 2. Penalty Formulation

Let a paragraph (or block of consecutive lines between forced breaks) be tokenized into a sequence of $N$ candidate break opportunities $B = (b_0, b_1, \dots, b_N)$, where $b_0$ is the start of the paragraph and $b_N$ is the mandatory break at the end of the block. Each $b_i$ has an associated cumulative inline advance $x(b_i) \in \mathbb{Q}_{\ge 0}$, a trailing overhang/hyphenation width adjustment $\delta(b_i) \in \mathbb{Q}$, and a break classification $t(b_i) \in \{\text{Normal}, \text{Hyphen}, \text{Overflow}, \text{Forced}\}$.

A **line** $L_k = (b_{i_{k-1}}, b_{i_k})$ spans from break $b_{i_{k-1}}$ to $b_{i_k}$ (with $0 = i_0 < i_1 < \dots < i_m = N$). The realized width of line $L_k$ is:
$$w(L_k) = x(b_{i_k}) - x(b_{i_{k-1}}) + \delta(b_{i_k})$$

Let $W_k > 0$ be the available inline width for line $k$. The **badness** (or base demerit) $D(L_k)$ of line $L_k$ measures the deviation from the target width $W_k$:

$$r(L_k) = \begin{cases} 
\frac{W_k - w(L_k)}{W_k} & \text{if } w(L_k) \le W_k \\
\infty & \text{if } w(L_k) > W_k \land t(b_{i_k}) \neq \text{Overflow}
\end{cases}$$

For the final line $L_m$ of a paragraph, standard ragged-right layout permits $w(L_m) \ll W_m$ without incurring standard whitespace stretching demerits, provided it does not create a single-word typographic orphan. Thus, the line demerit $D(L_k)$ is formulated as:

$$D(L_k) = \begin{cases} 
\alpha_{\text{space}} \cdot \left(r(L_k)\right)^2 & \text{if } k < m \text{ and } w(L_k) \le W_k \\
0 & \text{if } k = m \text{ and } w(L_m) \le W_m \\
P_{\text{overflow}} + \alpha_{\text{over}} \cdot \left(w(L_k) - W_k\right)^2 & \text{if } w(L_k) > W_k \text{ (Emergency/Overflow break)}
\end{cases}$$
where $\alpha_{\text{space}}, \alpha_{\text{over}}, P_{\text{overflow}} \in \mathbb{R}_{\ge 0}$ are scaling constants with $P_{\text{overflow}} \gg \alpha_{\text{space}}$.

#### Specific Penalty Terms
1.  **Hyphenation Penalty ($P_{\text{hyphen}}$)**:
    $$P_{\text{hyphen}}(L_k, L_{k-1}) = \mathbb{I}(\text{is\_hyphen}(b_{i_k})) \cdot \left( C_{\text{hyphen}} + \mathbb{I}(\text{is\_hyphen}(b_{i_{k-1}})) \cdot C_{\text{consec\_hyphen}} \right)$$
    where $\mathbb{I}$ is the indicator function, $C_{\text{hyphen}} \ge 0$, and $C_{\text{consec\_hyphen}} \ge 0$.

2.  **Orphan / Short-Last-Line Penalty ($P_{\text{orphan}}$)**:
    In CSS Text / Blink `ScoreLineBreaker`, an inline "orphan" (often termed a *widow* in traditional page layout, or a *runt* in line breaking) occurs when the final line $L_m$ contains only a single word or has a width smaller than a minimum fraction $\theta_{\text{min}} \in (0, 1)$ of $W_m$ while $m > 1$:
    $$P_{\text{orphan}}(L_m, m) = \begin{cases} 
    C_{\text{orphan}} \cdot \left(1 - \frac{w(L_m)}{\theta_{\text{min}} W_m}\right) & \text{if } m > 1 \land w(L_m) < \theta_{\text{min}} W_m \\
    C_{\text{single\_word}} & \text{if } m > 1 \land (i_m - i_{m-1} = 1) \\
    0 & \text{otherwise}
    \end{cases}$$

#### Total Paragraph Cost $C$
For a valid break sequence $\Pi = (i_0, i_1, \dots, i_m)$, the total cost $C(\Pi)$ is:
$$C(\Pi) = \sum_{k=1}^{m} \left( D(L_k) + P_{\text{hyphen}}(L_k, L_{k-1}) \right) + P_{\text{orphan}}(L_m, m)$$
(with $L_0 = \emptyset$ and $\text{is\_hyphen}(b_{i_{-1}}) = \text{false}$).

---

### 3. Dynamic Programming vs. Greedy Selection of Break Points

Blink implements two distinct algorithms depending on `text-wrap`:

#### A. Greedy Selection (`text-wrap: wrap` — CSS Text Level 3 §5 Default)
`LineBreaker::NextLine` executes a single-pass greedy scan from the previous line's end index $i_{k-1}$:
1.  Initialize `best_candidate = None`.
2.  Advance through `InlineItem`s, accumulating `current_width`.
3.  At each candidate break $b_j$ ($j > i_{k-1}$):
    *   Compute $w = x(b_j) - x(b_{i_{k-1}}) + \delta(b_j)$.
    *   If $w \le W_k$: update `best_candidate = b_j` (in greedy mode, a later legal break that fits *always* dominates an earlier break, effectively setting $C_{\text{hyphen}} = 0$ and minimizing $W_k - w$ locally).
    *   If $w > W_k$:
        *   If `best_candidate != None`, commit `best_candidate` and terminate the line.
        *   If `best_candidate == None` (the very first unbreakable unit exceeds $W_k$):
            *   If `overflow-wrap: anywhere` or `break-word` is enabled, split at the finest grapheme cluster boundary $b_{\text{emerg}}$ that fits within $W_k$.
            *   Otherwise, continue scanning until the *first* legal break opportunity $b_j$ (even though $w > W_k$), commit $b_j$ as an overflowing line, and terminate.

**Time Complexity**: $\mathcal{O}(N)$ per paragraph. Does not backtrack across lines; thus $P_{\text{orphan}}$ cannot influence line $L_{m-1}$.

#### B. Dynamic Programming (`text-wrap: pretty` — `ScoreLineBreaker`)
To optimize $C(\Pi)$ globally (specifically over the last $K=4$ lines of a paragraph block in Blink to bound latency), `ScoreLineBreaker` uses a Knuth-Plass style Dynamic Programming recurrence.

Let $DP[j][h]$ denote the minimum cumulative cost of breaking the prefix of candidates $b_0 \dots b_j$, where $h \in \{0, 1\}$ indicates whether break $b_j$ is hyphenated (needed only if consecutive hyphen penalties are active; if state is purely determined by $b_j$'s intrinsic `is_hyphenated` flag, the state space simplifies to $DP[j]$). Since `is_hyphenated` is a static property of candidate $b_j$, the state is simply $DP[j]$:

$$DP[0] = 0$$
$$DP[j] = \min_{0 \le i < j \text{ s.t. } \text{Valid}(i, j)} \left\{ DP[i] + D(b_i, b_j) + P_{\text{hyphen}}\big((b_i, b_j), b_i\big) + \mathbb{I}(j = N) \cdot P_{\text{orphan}}\big((b_i, b_N), \text{lines}(i)+1\big) \right\}$$

Where $\text{Valid}(i, j)$ holds iff:
1. $w(b_i, b_j) \le W$, **OR**
2. $j = i + 1$ and $w(b_i, b_{i+1}) > W$ (an unavoidable overflow segment where no intermediate break exists).

**Tie-Breaking & Determinism**: If two predecessor indices $i_1 < i_2$ yield identical minimum scores ($DP[i_1] + \text{cost}(i_1, j) == DP[i_2] + \text{cost}(i_2, j)$), Blink deterministically prefers $i_1$ (or $i_2$, fixed by strict `<` vs `<=` comparison in the loop over active candidates). Standard implementation uses strict `<` when iterating $i$ in increasing order, thereby preferring the *earlier* break point (longer current line, fewer total lines) on exact ties.

---

### 4. Mathematical Invariants

1.  **Width Bound Invariant (Non-Overflow Legal Breaks)**:
    For every selected line $L_k = (b_{i_{k-1}}, b_{i_k})$ in the output partition $\Pi$:
    $$\text{If } t(b_{i_k}) \neq \text{Overflow} \land (i_k > i_{k-1} + 1), \text{ then } w(b_{i_{k-1}}, b_{i_k}) \le W_k.$$
    *Meaning*: A line only exceeds the available width $W_k$ if it consists of a single indivisible atomic segment ($i_k = i_{k-1} + 1$) whose intrinsic width exceeds $W_k$. It is strictly illegal to include more than one breakable token on a line that overflows $W_k$.

2.  **Cost Non-Negativity Invariant**:
    For all valid partitions $\Pi$ and valid configurations $\mathcal{C}$ (where $\alpha_{\text{space}}, C_{\text{hyphen}}, C_{\text{orphan}}, P_{\text{overflow}} \ge 0$):
    $$C(\Pi) \ge 0$$
    Furthermore, the DP transition cost $\text{step\_cost}(i, j) \ge 0$ for all $0 \le i < j \le N$, ensuring monotonicity along any path in the DAG of break