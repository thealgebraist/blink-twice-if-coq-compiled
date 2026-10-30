## 1. Core Data Structures in Blink Counter Styles

In Chromium Blink (`third_party/blink/renderer/core/css/`), CSS Counter Styles Level 3 is implemented primarily through `CounterStyle`, `CounterStyleMap`, and `StyleRuleCounterStyle`. These classes translate parsed CSS descriptors (`@counter-style`) into a localized state machine capable of mapping 32-bit signed integers (`int`) to `WTF::String` representations.

### `CounterStyleSystem` (Enumeration)
Represented by `CounterStyleSystem` in `counter_style.h`:
*   `kCyclic`: Cycles infinitely through a provided list of symbols.
*   `kFixed`: Maps a contiguous range of integers starting at `first_symbol_value_` to a finite list of symbols, falling back outside this range.
*   `kSymbolic`: Cycles through symbols, doubling, tripling, etc., the symbol length on each subsequent pass.
*   `kAlphabetic`: Treats symbols as digits in a bijective base-$N$ numbering system (1-indexed, no zero digit).
*   `kNumeric`: Treats symbols as digits in a standard positional base-$N$ numbering system (0-indexed, includes zero).
*   `kAdditive`: Greedily decompositions an integer using value-symbol pairs (`additive-symbols`) ordered by descending weight.
*   `kExtends`: Unresolved state during AST construction (`StyleRuleCounterStyle`), resolved to one of the above concrete systems during `CounterStyle::Create` via `CounterStyleMap`.
*   *Internal Predefined Systems*: Blink also defines internal enum variants for complex, non-descriptor-expressible rules: `kSimpChineseInformal`, `kSimpChineseFormal`, `kTradChineseInformal`, `kTradChineseFormal`, `kKoreanHangulFormal`, `kKoreanHanjaInformal`, `kKoreanHanjaFormal`, `kJapaneseInformal`, `kJapaneseFormal`, `kEthiopicNumeric`, `kHebrew`, `kArmenian`, `kLowerArmenian`, `kGeorgian`.

### `CounterStyle` (Class)
Allocated via Oilpan (`GarbageCollected<CounterStyle>`), this class represents an immutable, resolved counter style instance.
*   `name_` (`AtomicString`): The identifier of the counter style.
*   `system_` (`CounterStyleSystem`): The resolved calculation algorithm.
*   `symbols_` (`Vector<String>`): The sequence of symbols used by `kCyclic`, `kFixed`, `kSymbolic`, `kAlphabetic`, and `kNumeric`.
*   `additive_weights_` (`Vector<int>`) and `additive_symbols_` (`Vector<String>`): Parallel vectors storing the descending non-negative integer weights and their corresponding strings for `kAdditive`.
*   `first_symbol_value_` (`int`): Used exclusively by `kFixed` (defaults to 1).
*   `range_` (`Vector<std::pair<int, int>>`): Closed intervals $[min_i, max_i]$ defining the domain of the counter style. If empty during parsing, it is populated with the system's default range per the W3C specification (`Infinite` bounds are represented by `std::numeric_limits<int>::min()` and `max()`).
*   `prefix_` (`String`), `suffix_` (`String`): Strings prepended/appended to the final representation (outside of `GenerateRepresentation`).
*   `pad_length_` (`int`), `pad_symbol_` (`String`): Minimum number of grapheme clusters required, and the padding string used to fill the deficit.
*   `negative_prefix_` (`String`), `negative_suffix_` (`String`): Wrapping strings applied when generating a representation for a negative value in a sign-using system.
*   `fallback_name_` (`AtomicString`): The identifier of the fallback style (defaults to `"decimal"`).
*   `fallback_style_` (`Member<const CounterStyle>`): Resolved pointer to the fallback `CounterStyle` instance.
*   `speak_as_` (`CounterStyleSpeakAs`) & `speak_as_style_` (`Member<const CounterStyle>`): Accessibility/speech synthesis resolution.
*   `is_in_fallback_` (`mutable bool`): Re-entrancy guard used during runtime fallback cycle detection.
*   `has_invalidation_ (`bool`)`: Tracks whether the style depends on unresolved references.

### `CounterStyleMap` (Class)
Managed per `TreeScope` (Document or ShadowRoot) and globally for UA rules (`GetUACounterStyleMap()`).
*   `counter_styles_` (`HeapHashMap<AtomicString, Member<CounterStyle>>`): Maps style names to resolved `CounterStyle` instances.
*   `tree_scope_` (`Member<const TreeScope>`): Null for the UA map; points to the owning `Document` or `ShadowRoot` for author maps.
*   **Resolution Lifecycle**: `CounterStyleMap::ResolveCounterStyles()` iterates over registered styles, resolving `kExtends` chains and linking `fallback_style_` pointers by traversing parent `TreeScope` maps up to the UA map.

---

## 2. Counter Integer String Generation Algorithm

The core generation pipeline in Blink is `CounterStyle::GenerateRepresentation(int value)` which invokes `GenerateInitialRepresentation(int value)` and applies negative signs and padding. Prefix and suffix are applied by the caller (e.g., `LayoutCounter`).

### Constants & Bounds
*   `kCounterLengthLimit`: Blink enforces a hard cap on generated symbol lengths (specifically in `kSymbolic` and `kAdditive`) to prevent OOM DoS attacks. In `counter_style.cc`, `kMaxCounterLength` is defined as `1000` (or bounded by `pad_length` limits).
*   **Integer Bounds**: `std::numeric_limits<int>::min()` ($-2^{31}$) to `std::numeric_limits<int>::max()` ($2^{31}-1$).

### Step-by-Step Pipeline: `GenerateRepresentation(int value)`

1.  **Range Check**:
    *   Iterate through `range_`. If $\neg \exists (low, high) \in \text{range\_}$ such that $low \le value \le high$, immediately delegate to `GenerateFallbackRepresentation(value)`.
2.  **Sign Handling & Magnitude Extraction**:
    *   Determine if the system `UsesNegativeSign()`: returns `true` for `kSymbolic`, `kAlphabetic`, `kNumeric`, `kAdditive`, and specialized CJK/historical systems; `false` for `kCyclic` and `kFixed`.
    *   If `value < 0` and `UsesNegativeSign()` is `true`:
        *   Compute unsigned magnitude: `unsigned_value = value == INT_MIN ? 2147483648U : static_cast<unsigned>(-value)`.
    *   Else:
        *   Pass `value` directly (for `kCyclic` and `kFixed`, negative values are processed natively; for others, `value >= 0`).
3.  **Initial Representation (`GenerateInitialRepresentation`)**:
     Let $N = \text{symbols\_}.size()$.
    *   **`kCyclic`**:
        *   Index calculation: $idx = (value - 1) \pmod N$.
        *   In C++, since `%` can yield negative results for negative dividends:
            ```cpp
            int index = (value - 1) % N;
            if (index < 0) index += N;
            return symbols_[index];
            ```
    *   **`kFixed`**:
        *   Let $first = \text{first\_symbol\_value\_}$.
        *   Calculate offset: $\text{index} = \text{base::CheckSub}(value, first)$. (Uses safe math to prevent signed overflow).
        *   If $\text{index}$ overflows, or $\text{index} < 0$, or $\text{index} \ge N$, return `String()` (triggers fallback).
        *   Return `symbols_[index]`.
    *   **`kSymbolic`**:
        *   Requires $value > 0$. If $value == 0$, return `String()` (triggers fallback).
        *   Let $u = \text{unsigned\_value} - 1$.
        *   Symbol index: $idx = u \pmod N$.
        *   Repetition count: $count = \lfloor u / N \rfloor + 1$.
        *   **DoS Guard**: If $count > \text{kCounterLengthLimit}$ (or `count * symbols_[idx].length()` exceeds safety limits), return `String()` (triggers fallback).
        *   Return `symbols_[idx]` repeated $count$ times.
    *   **`kAlphabetic`**:
        *   Requires $value > 0$. If $value == 0$, return `String()` (triggers fallback). Requires $N \ge 2$.
        *   Let $u = \text{unsigned\_value}$.
        *   Initialize empty buffer $S$.
        *   Loop while $u > 0$:
            *   $u \leftarrow u - 1$
            *   Prepend `symbols_[u % N]` to $S$.
            *   $u \leftarrow \lfloor u / N \rfloor$
        *   Return $S$.
    *   **`kNumeric`**:
        *   Requires $N \ge 2$.
        *   If $value == 0$, return `symbols_[0]`.
        *   Let $u = \text{unsigned\_value}$.
        *   Initialize empty buffer $S$.
        *   Loop while $u > 0$:
            *   Prepend `symbols_[u % N]` to $S$.
            *   $u \leftarrow \lfloor u / N \rfloor$
        *   Return $S$.
    *   **`kAdditive`**:
        *   If $value == 0$:
            *   If the last tuple in `additive_weights_` has weight $0$, return its corresponding symbol.
            *   Otherwise, return `String()` (triggers fallback).
        *   Let $u = \text{unsigned\_value}$.
        *   Initialize empty buffer $S$, and $length = 0$.
        *   For each $(weight_i, sym_i)$ in `additive_tuples`:
            *   If $weight_i == 0$, continue (or break, as weights are sorted descending).
            *   $reps = \lfloor u / weight_i \rfloor$.
            *   If $reps > 0$:
                *   $length \leftarrow length + reps$.
                *   **DoS Guard**: If $length > \text{kCounterLengthLimit}$, return `String()` (triggers fallback).
                *   Append $sym_i$ repeated $reps$ times to $S$.
                *   $u \leftarrow u \pmod{weight_i}$.
            *   If $u == 0$, break.
        *   If $u > 0$ (remainder could not be represented), return `String()` (triggers fallback).
        *   Return $S$.
4.  **Fallback Check**:
    *   If `initial_rep.IsNull()` (generation failed), return `GenerateFallbackRepresentation(value)`.
5.  **Padding Application**:
    *   Compute grapheme cluster length of `initial_rep`: $L_{init} = \text{NumGraphemeClusters}(initial\_rep)$.
    *   If `value < 0` and `UsesNegativeSign()`:
        *   $L_{init} \leftarrow L_{init} + \text{NumGraphemeClusters}(negative\_prefix\_) + \text{NumGraphemeClusters}(negative\_suffix\_)$.
    *   If $L_{init} < \text{pad\_length\_}$:
        *   Let $diff = \text{pad\_length\_} - L_{init}$.
        *   Prepend `pad_symbol_` repeated $diff$ times to `initial_rep`. (Note: W3C spec states padding is added by repeating `pad_symbol` $diff$ times regardless of how many grapheme clusters `pad_symbol` itself contains).
6.  **Negative Sign Application**:
    *   If `value < 0` and `UsesNegativeSign()`:
        *   Return `negative_prefix_ + initial_rep + negative_suffix_`.
    *   Else:
        *   Return `initial_rep`.

---

## 3. Fallback Resolution Mechanism

Fallback occurs under four conditions:
1.  **Range Violation**: `value` is outside the intervals in `range_`.
2.  **Domain Violation**: `value <= 0` in `kSymbolic` or `kAlphabetic`, or `value < 0` in `kFixed` when `first_symbol_value_` doesn't cover it.
3.  **Unrepresentable Value**: In `kFixed`, `value >= first_symbol_value_ + N`. In `kAdditive`, $u > 0$ after exhausting all weights, or $value = 0$ with no weight-0 tuple.
4.  **Implementation Limit**: Symbol length exceeds `kCounterLengthLimit`.

### Cycle Detection & Termination
Blink resolves fallback styles during `CounterStyleMap::ResolveCounterStyles()` and executes them dynamically in `CounterStyle::GenerateFallbackRepresentation(int value)`.

*   **Dynamic Cycle Detection**:
    `CounterStyle` maintains a `mutable bool is_in_fallback_ = false;`.
    When `GenerateFallbackRepresentation(int value)` is called on style $A$:
    ```cpp
    if (fallback_style_->IsInFallback()) {
      // Cycle detected! Break cycle by jumping directly to UA 'decimal'.
      return GetDecimalCounterStyle().GenerateRepresentation(value);
    }
    base::AutoReset<bool> in_fallback_scope(&is_in_fallback_, true);
    return fallback_style_->GenerateRepresentation(value);
    ```
*   **TreeScope Resolution**:
    When looking up `fallback_name_`, `CounterStyleMap::FindCounterStyle` searches the local `TreeScope` (e.g., ShadowRoot). If not found, it walks up `ParentTreeScope()` to the `Document`, and finally queries `GetUACounterStyleMap()`. If the named fallback style does not exist anywhere, it links directly to the UA `"decimal"` style.
*   **Ultimate Termination (`decimal`)**:
    The UA `"decimal"` counter style is defined with:
    *   `system`: `kNumeric`
    *   `symbols`: `["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]`
    *   `range`: `[-INT_MAX, INT_MAX]` (i.e., `auto`, which covers all integers).
    Because `kNumeric` with 10 symbols and an infinite range can represent every 32-bit signed integer without hitting length limits (max length is 10 digits + 1 sign < `kCounterLengthLimit`), `"decimal"` is guaranteed to succeed and terminate the recursion.

---

## 4. Mathematical Invariants, Edge Cases, and W3C Gaps

### Mathematical Invariants
1.  **Total Function**: $\forall S \in \text{CounterStyle}, \forall v \in [-2^{31}, 2^{31}-1]$, `GenerateRepresentation(S, v)` terminates and returns a valid non-null `String`.
2.  **Deterministic Generation**: Given an immutable `CounterStyleMap` state, `GenerateRepresentation(S, v)` is a pure mathematical function (the `mutable is_in_fallback_` state is strictly scoped to the call stack via `base::AutoReset` and restored upon exit).
3.  **Bounded Fallback Depth**: Let $K$ be the total number of registered `CounterStyle` instances across the `