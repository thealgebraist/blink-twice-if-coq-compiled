### 1. Core Data Structures in Chromium Blink

In Chromium's Blink rendering engine (`third_party/blink/renderer/core/css/counter_style.h` and `counter_style.cc`), CSS Counter Styles Level 3 (§2 & §3) are represented by the `CounterStyle` class, which wraps resolved style rules (`StyleRuleCounterStyle`) and maintains state for cycle detection and symbol generation.

#### `CounterStyleSystem` Enumeration
Blink categorizes the counter generation algorithms via `CounterStyleSystem`:
*   `kCyclic`: Cycles through a provided list of symbols (`symbols`).
*   `kFixed`: Uses a finite sequence of symbols starting at a `first_symbol_value` (defaulting to 1), falling back once exhausted.
*   `kSymbolic`: Repeats symbols progressively per pass ($1\times$ on pass 1, $2\times$ on pass 2, etc.).
*   `kAlphabetic`: Bijective base-$N$ numbering system without a zero digit (digits map to $1 \dots N$).
*   `kNumeric`: Standard positional base-$N$ numbering system (digits map to $0 \dots N-1$).
*   `kAdditive`: Sign-value notation using ordered pairs of `(weight, symbol)` (`additive-symbols`).
*   `kExtends`: Resolved during style cascade/registration into one of the concrete systems above before counter generation occurs.

#### `CounterStyle` Class Anatomy
```cpp
class CORE_EXPORT CounterStyle final : public GarbageCollected<CounterStyle> {
  // Core properties resolved from @counter-style descriptors:
  CounterStyleSystem system_;
  Vector<String> symbols_;
  Vector<std::pair<unsigned, String>> additive_symbols_; // Sorted descending by weight
  Vector<std::pair<int, int>> range_; // Inclusive [low, high] bounds
  
  String prefix_;
  String suffix_;
  
  // Fallback handling
  AtomicString fallback_name_;
  Member<const CounterStyle> fallback_style_;
  
  // Negative sign and Pad descriptors
  String negative_prefix_;
  String negative_suffix_;
  int pad_length_;
  String pad_symbol_;
  
  mutable bool is_in_fallback_ = false; // Cycle detection flag during evaluation
};
```

---

### 2. Representation Generation Algorithms

Blink separates the generation of the *initial representation* (`GenerateInitialRepresentation`) from sign/padding decoration (`GenerateRepresentation`). When a system uses a negative sign (`kSymbolic`, `kAlphabetic`, `kNumeric`, `kAdditive`), Blink operates on the absolute value $\text{abs}(v)$ and prepends/appends the `negative` descriptor later.

#### A. Cyclic System (`CyclicAlgorithm`)
*   **Spec Reference**: CSS Counter Styles Level 3 §3.1.1.
*   **Domain**: $(-\infty, \infty)$. Does not use a negative sign.
*   **Algorithm**: Given $N = \text{symbols.size()} \ge 1$ and counter value $v \in \mathbb{Z}$:
    $$\text{index}_{0} = ((v - 1) \bmod N + N) \bmod N$$
    *(Note: The spec defines 1-based indexing $I_1 = ((v - 1) \bmod N) + 1$ where $\bmod$ is the Euclidean modulo returning values in $[0, N-1]$. In C++, `%` is truncated division remainder, so Blink normalizes negative remainders into $[0, N-1]$).*
*   **Output**: `symbols_[index_0]`.

#### B. Alphabetic System (`AlphabeticAlgorithm`)
*   **Spec Reference**: CSS Counter Styles Level 3 §3.1.4.
*   **Domain**: Strictly positive integers $[1, \infty)$ for initial representation (negative values pass $|v|$ and set the negative flag; $0$ is outside the implicit domain and triggers fallback).
*   **Algorithm**: Bijective base-$N$ conversion where $N = \text{symbols.size()} \ge 2$:
    1. Initialize empty buffer $S$.
    2. While $v > 0$:
       a. $v \leftarrow v - 1$
       b. Prepend `symbols_[v % N]` to $S$.
       c. $v \leftarrow \lfloor v / N \rfloor$
    3. Return $S$ (if length exceeds `kCounterLengthLimit`, Blink returns an empty string to trigger fallback and prevent OOM).

#### C. Additive System (`AdditiveAlgorithm`)
*   **Spec Reference**: CSS Counter Styles Level 3 §3.1.6.
*   **Domain**: Non-negative integers $[0, \infty)$ for initial representation.
*   **Precondition**: `additive_symbols_` is a list of tuples $(w_i, s_i)$ with $w_0 > w_1 > \dots > w_k \ge 0$ (strictly descending weights in Blink after parsing/deduplication).
*   **Algorithm**:
    1. If $v = 0$:
       a. If there exists a tuple with $w_k = 0$, return $s_k$.
       b. Otherwise, fail (return empty string $\implies$ triggers fallback).
    2. Initialize empty buffer $S$ and remaining value $R = v$.
    3. For each $(w_i, s_i)$ in `additive_symbols_` where $w_i > 0$:
       a. Let $\text{reps} = \lfloor R / w_i \rfloor$.
       b. Append $\text{reps}$ copies of $s_i$ to $S$.
       c. $R \leftarrow R \bmod w_i$.
       d. If $R = 0$, break.
    4. If $R > 0$ after exhausting all tuples, representation fails (triggers fallback).
    5. Return $S$.

---

### 3. Range Verification and Fallback Invocation

Before running the system algorithm (and when the algorithm fails to produce a representation), Blink executes fallback resolution:

1. **Range Check (`RangeContains(int value)`)**:
   * If `range_` is explicitly specified, check if $\exists [\text{low}, \text{high}] \in \text{range\_}$ such that $\text{low} \le v \le \text{high}$.
   * If `range_` is `auto`, Blink enforces the implicit system bounds:
     * `kCyclic`, `kNumeric`, `kFixed`: $[-\infty, \infty]$ (bounded by `INT_MIN` / `INT_MAX`).
     * `kSymbolic`, `kAlphabetic`: $[1, \infty)$.
     * `kAdditive`: $[0, \infty)$.
   * If $v$ is outside the range, immediately invoke `GenerateFallbackRepresentation(value)`.

2. **Algorithmic Failure**:
   * `kFixed`: Fails if $v < \text{first\_symbol\_value}$ or $v \ge \text{first\_symbol\_value} + N$.
   * `kAdditive`: Fails if $R > 0$ at termination, or $v = 0$ with no weight-$0$ tuple.
   * Length bounds: In `kSymbolic` or `kAdditive`, if the required symbol repetitions exceed Blink's internal safety cap (`kCounterLengthLimit`), it aborts and falls back.

3. **Cycle Detection in Fallback**:
   * Counter styles may form a cycle in their `fallback` descriptors (e.g., `A -> B -> A`).
   * Blink sets `is_in_fallback_ = true` on the current `CounterStyle` frame before recursing into `fallback_style_->GenerateRepresentation(value)`.
   * If `fallback_style_->is_in_fallback_` is already `true`, Blink breaks the cycle by delegating directly to the predefined `decimal` counter style (`GetDecimal() -> kNumeric` with digits `'0'..'9'`).

---

### 4. Mathematical Invariants

1. **Cyclic Indexing Boundedness**:
   $$\forall v \in \mathbb{Z}, N \in \mathbb{Z}^+ : 0 \le ((v - 1) \bmod_{\text{E}} N) < N$$
   where $\bmod_{\text{E}}$ is Euclidean modulo. Consequently, the 1-based spec index $I_1 = ((v - 1) \bmod_{\text{E}} N) + 1$ strictly satisfies $1 \le I_1 \le N$, guaranteeing memory-safe array access without out-of-bounds reads.

2. **Bijective Alphabetic Uniqueness**:
   For base $N \ge 2$, the alphabetic algorithm establishes a bijection between $\mathbb{Z}^+$ and non-empty finite sequences over $\{0, \dots, N-1\}$:
   $$\text{val}([d_k, d_{k-1}, \dots, d_0]) = \sum_{i=0}^{k} (d_i + 1) N^i$$
   Because each digit weight is shifted into $[1, N]$ instead of $[0, N-1]$, leading zeros cannot exist, making the representation of every $v \ge 1$ unique and unambiguous.

3. **Termination and Determinism**:
   * **Alphabetic**: Since $N \ge 2$ and $v \ge 1$, the step $v' = \lfloor (v - 1) / N \rfloor$ strictly decreases $v$ ($0 \le v' < v$), guaranteeing termination in $\lfloor \log_N((N-1)v + 1) \rfloor$ steps.
   * **Additive**: Iterates over a finite list of tuples; inner division/modulo reduces $R$ deterministically in $O(1)$ arithmetic steps per tuple.
   * **Fallback**: Since the set of defined `@counter-style` rules in a document is finite and visited nodes are marked via `is_in_fallback_`, fallback traversal is a finite simple path terminating either at a valid representation or at `decimal` (which is total over $\mathbb{Z}$).

---

### 5. Rocq / Coq Formalization (`BlinkCounterStyleSystemsSemantics.v`)

The following self-contained Rocq (Coq) formalization models the core counter style systems, range checking, fallback cycle protection, and proves the key mathematical invariants.

```coq
(** * BlinkCounterStyleSystemsSemantics.v
    Formalization of Chromium Blink CSS Counter Styles Level 3 (§2 & §3) *)

From Coq Require Import ZArith List String Bool Lia PeanoNat.
Import ListNotations.
Open Scope Z_scope.

(** ** 1. Core Data Structures *)

Definition Symbol := nat. (* Abstract representation of a String symbol *)

Inductive CounterStyleSystem : Type :=
  | SysCyclic (symbols : list Symbol)
  | SysFixed (first_val : Z) (symbols : list Symbol)
  | SysSymbolic (symbols : list Symbol)
  | SysAlphabetic (symbols : list Symbol)
  | SysNumeric (symbols : list Symbol)
  | SysAdditive (tuples : list (Z * Symbol)).

Definition RangeBound := (Z * Z)%type.

Record CounterStyle : Type := mkCounterStyle {
  cs_name : nat;
  cs_system : CounterStyleSystem;
  cs_explicit_range : option (list RangeBound);
  cs_fallback : nat (* Index/ID of fallback style *)
}.

(** ** 2. Range Semantics *)

Definition in_explicit_ranges (v : Z) (ranges : list RangeBound) : bool :=
  existsb (fun b => (fst b <=? v) && (v <=? snd b)) ranges.

Definition in_auto_range (v : Z) (sys : CounterStyleSystem) : bool :=
  match sys with
  | SysCyclic _ | SysNumeric _ | SysFixed _ _ => true
  | SysSymbolic _ | SysAlphabetic _ => 1 <=? v
  | SysAdditive _ => 0 <=? v
  end.

Definition range_contains (cs : CounterStyle) (v : Z) : bool :=
  match cs_explicit_range cs with
  | Some ranges => in_explicit_ranges v ranges
  | None => in_auto_range v (cs_system cs)
  end.

(** ** 3. Representation Generation Algorithms *)

(** *** 3.1 Cyclic System *)
(** Spec: index_1 = ((v - 1) mod N) + 1. Zero-based: (v - 1) mod N.
    Coq's Z.modulo is Euclidean when the divisor is positive. *)
Definition cyclic_index_0 (v : Z) (N : Z) : Z :=
  (v - 1) mod N.

Definition generate_cyclic (v : Z) (symbols : list Symbol) : option (list Symbol) :=
  let N := Z.of_nat (length symbols) in
  if N <=? 0 then None
  else
    let idx := Z.to_nat (cyclic_index_0 v N) in
    match nth_error symbols idx with
    | Some s => Some [s]
    | None => None
    end.

(** *** 3.2 Alphabetic System (Bijective Base-N) *)
Fixpoint alphabetic_loop (fuel : nat) (v : Z) (N : Z) (symbols : list Symbol) (acc : list Symbol) : option (list Symbol) :=
  match fuel with
  | O => None
  | S fuel' =>
      if v <=? 0 then Some acc
      else
        let v' := v - 1 in
        let digit_idx := Z.to_nat (v' mod N) in
        match nth_error symbols digit_idx with
        | Some s => alphabetic_loop fuel' (v' / N) N symbols (s :: acc)
        | None => None
        end
  end.

Definition generate_alphabetic (v : Z) (symbols : list Symbol) : option (list Symbol) :=
  let N := Z.of_nat (length symbols) in
  if (N <? 2) || (v <=? 0) then None
  else alphabetic_loop (Z.to_nat v + 1)%nat v N symbols [].

(** Pure mathematical bijective base-N encoding into digit indices [0 .. N-1] *)
Fixpoint bijective_encode_fuel (fuel : nat) (v : Z) (N : Z) : list Z :=
  match fuel with
  | O => []
  | S fuel' =>
      if v <=? 0 then []
      else
        let v' := v - 1 in
        bijective_encode_fuel fuel' (v' / N) N ++ [v' mod N]
  end.

(** Inverse decoding: sum of (d_i + 1) * N^i *)
Fixpoint bijective_decode (digits : list Z) (N : Z) : Z :=
  match digits with
  | [] => 0
  | d :: rest => bijective_decode rest N (* Wait: fold left from MSB to LSB *)
  end.

Definition bijective_decode_msb (digits : list Z) (N : Z) : Z :=
  fold_left (fun acc d => acc * N + (d + 1)) digits 0.

(** *** 3.3 Additive System *)
Fixpoint repeat_symbol (n : nat) (s : Symbol) : list Symbol :=
  match n with
  | O => []
  | S n' => s :: repeat_symbol n' s
  end.

Fixpoint additive_loop (