# Chromium Blink CSS Custom Properties & `var()` Substitution Audit
**Target:** Chromium Blink Rendering Engine (`third_party/blink/renderer/core/css/`)  
**Specification:** W3C CSS Custom Properties for Cascading Variables Module Level 1  
**Auditor:** Agent 33  

---

## 1. Core Data Structures in Blink CSS Custom Properties

Blink’s implementation of CSS Custom Properties decouples variable parsing from standard property resolution until computed-value time. The core architecture relies on four primary C++ constructs:

### 1.1 `CSSVariableData` (`css_variable_data.h` / `.cc`)
`CSSVariableData` is an immutable, heap-allocated (`GarbageCollected<CSSVariableData>`) representation of a custom property's value.
*   **Memory Layout:** To minimize memory overhead, it stores the raw variable string directly inline using a flexible array member (`charSwitch` / `StringView` backing) alongside a vector of `CSSParserToken`s (or offsets in newer Blink streaming parser iterations).
*   **Flags:**
    *   `is_animation_tainted_`: Boolean flag required by the spec (§ 2.1). If true, this variable cannot be used inside the `animation-tainted` context (e.g., `animation-name` or `@keyframes` fallback chains) and resolves to the guaranteed-invalid value.
    *   `has_font_units_` / `has_root_font_units_` / `has_line_height_units_`: Dependency flags used to invalidate the `ComputedStyle` cache when font metrics change.
    *   `needs_variable_resolution_`: Indicates whether the token stream contains unexpanded `var()` or `env()` references.

### 1.2 `TokenSequence` (`style_cascade.h` / `.cc`)
`TokenSequence` is the mutable workspace used during variable resolution to assemble the final substituted token stream.
*   **Structure:** Contains a `Vector<CSSParserToken>` (or raw string builder in the `CSSParserTokenStream` architecture) and tracks combined metadata (`is_animation_tainted_`, base URL, charset) inherited from all `CSSVariableData` objects appended to it.
*   **Whitespace & Token Pasting:** `TokenSequence::Append` implements the spec's serialization adjacency rules. When appending a token stream to an existing sequence, it checks the trailing token of the current sequence against the leading token of the appended sequence to prevent accidental token pasting (e.g., ensuring an `<ident-token>` followed by an `<ident-token>` has an intervening `/**/` comment or whitespace).

### 1.3 `StyleCascade` & `CascadeResolver` (`style_cascade.h` / `.cc`)
`StyleCascade` replaces the legacy `CSSVariableResolver`. It integrates cascade application and variable resolution into a single pass.
*   **`CascadeMap`:** Maps `CSSPropertyName` (both standard `CSSPropertyID` and `AtomicString` custom property names) to their winning `CascadePriority`.
*   **`CascadeResolver`:** Maintains the state of an active resolution pass:
    *   `Stack` (`Vector<CSSPropertyName>`): Tracks the currently resolving properties to detect dependency cycles.
    *   `cycle_depth_` (`wtf_size_t` / `unsigned`): Records the stack index (depth) of the highest ancestor property implicated in a dependency cycle. If `cycle_depth_ < stack_.size()`, the current resolution is poisoned by a cycle.
    *   `filter_` (`CascadeFilter`): Filters out properties based on context (e.g., rejecting animation-tainted properties when resolving `animation-*`).

---

## 2. The `var()` Substitution and Cycle Detection Algorithm

Blink implements W3C CSS Custom Properties § 2.2 & § 3 via a depth-first search (DFS) with Tarjan-style cycle back-edge propagation on the `CascadeResolver` stack.

### 2.1 Active Resolution Stack & Cycle Detection
When `StyleCascade::Resolve` processes a custom property `--foo`:

1.  **Cycle Check (`DetectCycle`):** Blink searches `resolver.stack_` for `--foo`. 
    *   If `--foo` is found at index $i$, a cycle is detected. Blink sets `resolver.cycle_depth_ = std::min(resolver.cycle_depth_, i)`. `ResolveCustomProperty` immediately returns `nullptr` (representing the *guaranteed-invalid value*).
2.  **Push:** If not in the stack, `--foo` is pushed onto `resolver.stack_` (at index $d = \text{size} - 1$).
3.  **Token Stream Resolution (`ResolveTokensInto`):** Blink iterates over the tokens of `--foo`:
    *   Non-`var()` tokens are appended directly to the local `TokenSequence`.
    *   When a `var()` function token is encountered, `ResolveVarInto` is invoked.
4.  **Cycle Unwinding (`InCycle`):** After attempting to resolve a `var()` target `--bar`, Blink checks `resolver.InCycle()`, defined as:
    $$\text{InCycle}() \iff \text{cycle\_depth\_} < \text{stack\_.size}()$$
    If true, the current property `--foo` is part of an active cycle that reaches an ancestor at or above the current stack frame. Resolution of `--foo` aborts immediately **without** evaluating the `var()` fallback.
5.  **Pop:** When popping `--foo` from `stack_`, if `stack_.size() == cycle_depth_`, the cycle has completely unwound back to its entry point in the DFS tree. Blink resets `cycle_depth_ = kNotFound` ($\infty$). All nodes traversed while `InCycle()` was true have their computed values overwritten with `CSSUnsetValue` / `nullptr` (guaranteed-invalid).

### 2.2 `var()` Resolution and Fallback Substitution (`ResolveVarInto`)
Given `var( <custom-property-name> [, <declaration-value> ]? )`:

1.  **Parse Name:** Consume the `<custom-property-name>` (e.g., `--target`). Skip whitespace.
2.  **Lookup & Resolve Target:** Look up `--target` in `StyleCascade` and recursively call `ResolveCustomProperty(--target)`.
3.  **Cycle Short-Circuit:** If `resolver.InCycle()` is true after the recursive call:
    *   **Crucial Spec Requirement (§ 3):** A property in a cycle *must not* trigger fallback substitution until the entire cycle has resolved to guaranteed-invalid, and even then, any node *inside* the cycle must resolve to guaranteed-invalid.
    *   However, if `--A` (not in a cycle) references `var(--B, fallback)` where `--B` is in a cycle (`--B: var(--B)`), `--B`'s cycle unwinds at `--B`'s frame (`cycle_depth_` resets when popping `--B`). When control returns to `--A`, `resolver.InCycle()` is `false`, and `--B`'s data is `nullptr` (guaranteed-invalid). Thus, `--A` **correctly takes the fallback**!
    *   Conversely, if `--B: var(--C, fallback)` and `--C: var(--B)`, when `--B` evaluates `--C`, `--C` sees `--B` on the stack, sets `cycle_depth_` to `--B`'s index, and returns `nullptr`. In `--B`, `resolver.InCycle()` is `true`. `--B` **aborts without taking the fallback**, ensuring both `--B` and `--C` become guaranteed-invalid.
4.  **Taint Check:** If the resolved `CSSVariableData` is `is_animation_tainted_` and the current property disallows tainted values, treat the data as `nullptr` (invalid).
5.  **Success Path:** If valid `CSSVariableData` is returned (and its token length passes the `kMaxSubstitutionTokens = 65536` DoS check), append it to the `TokenSequence` and skip the fallback tokens.
6.  **Fallback Path:** If data is `nullptr` (unset, guaranteed-invalid, or unregistered initial) and a comma `,` is present:
    *   Consume the comma.
    *   Recursively call `ResolveTokensInto` on the remaining tokens inside the `var(...)` block.
    *   If that recursive fallback evaluation succeeds (and doesn't trigger a cycle), append the resolved fallback to the parent `TokenSequence`.

---

## 3. Universal Syntax and Token Serialization

### 3.1 The `<declaration-value>` Production (Universal Syntax)
Unregistered custom properties (or `@property` registered with `syntax: "*"`) accept the forgiving universal syntax defined in CSS Syntax Level 3:
*   Must contain one or more tokens (empty values like `--foo: ;` are valid per CSS Custom Properties Level 1 § 2, representing an empty token stream, which Blink stores as an empty `CSSVariableData`).
*   **Forbidden Top-Level Tokens:** `<bad-string-token>`, `<bad-url-token>`, unmatched `<)-token>`, `<]-token>`, `<}-token>`, top-level `<semicolon-token>`, and top-level `<delim-token>` with value `!` (unless it forms a valid `!important` suffix at the end of the declaration).
*   Block matching (`()`, `[]`, `{}`) is strictly enforced by `CSSVariableParser::ConsumeUnparsedDeclaration`.

### 3.2 Token Serialization & Adjacency Invariants
When substituting `var()` into a token stream, Blink must preserve token identities upon re-serialization:
*   **Leading/Trailing Whitespace:** Stripped from the custom property value upon initial parsing, and stripped from the `<declaration-value>` fallback after the comma in `var(--x,   fallback  )`.
*   **Comment Eradication & Re-insertion:** Original CSS comments are stripped during lexing, but if substituting `--a: foo` and `--b: bar` into `var(--a)var(--b)` would produce `foobar` (a single `<ident-token>`), `TokenSequence::Append` checks `NeedsInsertedComment(last_token, first_token)` and inserts `/**/` (`<whitespace-token>` or comment serialization) to maintain distinct tokens during subsequent re-parsing.

---

## 4. Mathematical Invariants

Let $\mathcal{V}$ be the finite set of custom property names present in an element's cascade map.

1.  **Invariant 1 (Termination of Resolution):** For any finite cascade map $M$ over $\mathcal{V}$ and finite expression tree $E$, the resolution algorithm terminates in $O(|\mathcal{V}| \cdot |E|)$ steps (when memoized via `ComputedStyle` writing during cascade) or $O(|\mathcal{V}|! \cdot |E|)$ worst-case without memoization. Because Blink writes resolved `CSSVariableData` back to `ComputedStyle` immediately upon popping a non-cycled property from the stack, each property in $\mathcal{V}$ is fully resolved at most once outside of transient cycle exploration.
2.  **Invariant 2 (Cycle Resolution Determinism):** Every property $v \in \mathcal{V}$ that belongs to a Strongly Connected Component (SCC) with at least one edge in the active dependency subgraph (i.e., dependencies actually evaluated before short-circuiting) deterministically resolves to `GuaranteedInvalid` ($\bot$).
3.  **Invariant 3 (Acyclic Chain Convergence):** If the active dependency subgraph reachable from $v \in \mathcal{V}$ is a Directed Acyclic Graph (DAG) and no leaf evaluates to an unhandled $\bot$ without fallback, $v$ resolves in finite steps to a flat `TokenSequence` free of `var()` tokens (provided size $\le 65536$).
4.  **Invariant 4 (Fallback Contextual Validity):** Given `var(v, fb)` evaluated inside property $u$:
    *   If $v$ is in a cycle that includes $u$, `fb` is **ignored**, and $u \mapsto \bot$.
    *   If $v$ is in a self-contained cycle not involving $u$ (nor any ancestor on the active call stack), $v \mapsto \bot$, the cycle state clears upon returning from $v$, and $u$ evaluates `fb`.

---

## 5. Formalization in Rocq / Coq (`BlinkCSSCustomPropertiesSemantics.v`)

The following self-contained Rocq (Coq) formalization models Blink's `StyleCascade` custom property resolution, token trees, fallback semantics, and proves the four core invariants.

```coq
(** * BlinkCSSCustomPropertiesSemantics.v
    Formalization of Chromium Blink's CSS Custom Properties and var() Substitution
    (StyleCascade / CascadeResolver / CSSVariableData) against W3C CSS Custom Properties L1.
*)

From Coq Require Import Lists.List.
From Coq Require Import Arith.PeanoNat.
From Coq Require Import Bool.Bool.
From Coq Require Import Lia.
Import ListNotations.

(** ** 1. Core Syntax and Data Structures *)

(** Custom property identifiers (--foo) represented as natural numbers. *)
Definition VarName := nat.

(** Atomic non-var CSS tokens (identifiers, dimensions, delims, etc.). *)
Definition RawToken := nat.

(** Representation of a parsed CSS token stream containing potential [var()] calls.
    Corresponds to unexpanded [CSSVariableData] in Blink. *)
Inductive ExprToken : Type :=
  | TokRaw : RawToken -> ExprToken
  | TokVar : VarName -> option (list ExprToken) -> ExprToken.

Definition ExprStream := list ExprToken.

(** Resolved flat token sequence (free of [var()] calls).
    Corresponds to resolved [TokenSequence] / [CSSVariableData] in Blink. *)
Definition ResolvedStream := list RawToken.

(** Computed value of a custom property after resolution.
    [GuaranteedInvalid] corresponds to [nullptr] / [CSSUnsetValue] in Blink. *)
Inductive ResolvedValue : Type :=
  | ValValid : ResolvedStream -> ResolvedValue
  | GuaranteedInvalid : ResolvedValue.

(** The StyleCascade map associating custom property names with their parsed declarations. *)
Definition CascadeMap := VarName -> option ExprStream.

(** Active resolution stack tracking currently resolving properties. *)
Definition Stack := list VarName.

(** Check if a variable is currently on the active resolution stack. *)
Definition in_stack (v : VarName) (stk : Stack) : bool :=
  existsb (Nat.eqb v) stk.

(** Measure the depth of the cycle if [v] is in [stk].
    In Blink, [DetectCycle] finds the index from the bottom of the stack.
    Here, we model the boolean condition of whether an active cycle encompasses
    the current frame via an explicit return flag [in_cycle] that unwinds
    until the cycle target frame is popped. *)
Inductive CycleState : Type :=
  | NoCycle : CycleState
  | ActiveCycle : VarName -> CycleState. (* Holds the target VarName that started the cycle *)

(** Result of evaluating an expression stream or variable in Blink's [CascadeResolver]. *)
Definition EvalResult := (ResolvedValue * CycleState)%type.

(** ** 2. Blink var() Substitution and Cycle Detection Algorithm *)

Section BlinkResolver.
  Variable (cascade : CascadeMap).

  (** Fuel-bounded mutual recursion modeling [StyleCascade::ResolveCustomProperty],
      [StyleCascade::ResolveTokensInto], and [StyleCascade::ResolveVarInto].
      Fuel represents the structural bound (stack bound + expression AST size). *)
  Fixpoint resolve_var (fuel : nat) (v : VarName) (stk : Stack) : EvalResult :=
    match fuel with
    | 0 => (GuaranteedInvalid, NoCycle)
    | S fuel' =>
        if in_stack v stk then
          (* Cycle detected! Set cycle target to [v] and return GuaranteedInvalid. *)
          (GuaranteedInvalid