### 1. Theoretical Foundations & Semantic Soundness

#### 1.1 Semantic Framework Selection: Stratified Denotational/Monadic Semantics via Interaction Trees
To simultaneously support structural induction, equational reasoning, partial evaluation, and extraction to native code, a single flat semantic layer is insufficient. We require a **stratified semantic architecture** in Coq/Rocq:

1. **Low-Level Imperative Semantics (Deep Embedding via ITrees):** 
   Use **Interaction Trees (ITrees)** (Xia et al., POPL 2020) to represent the raw semantics of the ingested C++ AST. ITrees are coinductive data structures representing computations that interact with an environment via uninterpreted events:
   ```coq
   Variant MemE : Type -> Type :=
     | Load (p : ptr) : MemE val
     | Store (p : ptr) (v : val) : MemE unit.

   Variant ControlE : Type -> Type :=
     | EarlyReturn (v : val) : ControlE void
     |Break : ControlE void.

   Definition BlinkM (E : Type -> Type) (R : Type) := itree (MemE +' ControlE +' E) R.
   ```
   **Justification:** Unlike raw small-step operational semantics, ITrees are a *denotational* domain that forms a monad, supports compositional equational reasoning via weak bisimulation ($\approx$, `eutt` — equivalence up to tau), and directly handles potentially non-terminating loops via the `iter` combinator without upfront termination proofs. Unlike big-step semantics, ITrees distinguish non-termination from stuck states (Undefined Behavior) and are natively executable via extraction.

2. **Mid-Level Functional-Imperative Spec (Shallow Monadic Embedding):**
   By interpreting away the `MemE` and `ControlE` events over a localized state record (representing the `FlexLine` and `wtf::Vector<FlexItem>`), we lift the ITree into a pure **State-Exception-Fuel Monad**:
   ```coq
   Definition LayoutM (S E A : Type) : Type :=
     S -> nat (* fuel *) -> (Result E A * S).
   ```
3. **High-Level Pure Specification (Total Functional):**
   Once termination is discharged (by proving that the C++ loop variants strictly decrease, e.g., the number of unfrozen `FlexItem`s in `ResolveFlexibleLengths` is bounded by `items.size()`), we eliminate the `fuel` parameter to yield a pure, total Gallina function suitable for algebraic specialization.

```
[Clang C++20 AST] 
       │ (Clight-style Ingestion / cpp2v)
       ▼
[Deeply Embedded AST + ITree Semantics]  (Handles pointers, UBs, unstructured control flow)
       │ (State/Control Event Interpretation + Frame Rule Discharge)
       ▼
[Shallow Monadic Spec (LayoutM)]         (Pure state transformation, fuel-bounded loops)
       │ (Termination Proof: Unfrozen items strictly decrease)
       ▼
[Total Pure Gallina Function]            (Target for Partial Evaluation & WPT Execution)
```

#### 1.2 Bridging the C++20 Imperative-Functional Gap

##### Mutation, Pointers, and Aliasing
Blink's layout engine relies heavily on mutating references (`FlexItem&`, `LayoutUnit&`) and contiguous stack/arena-allocated arrays (`wtf::Vector<FlexItem, 8>`). 
* **The Trick:** In Blink's `FlexibleBoxAlgorithm`, pointers into `FlexLine::line_items_` do not alias arbitrary heap memory; they are strictly scoped to the `FlexLine` struct lifetime. 
* **Formalization:** Model `wtf::Vector<T>` as a pure Coq `list T` (or an indexed array `Fin.t n -> T`). A C++ mutable reference `FlexItem& item` inside a loop (`for (FlexItem& item : line_items_)`) is lifted via **Functional Lenses** (getters/setters satisfying round-trip laws) or state-monadic indexed updates (`modify_at (idx : nat) (f : FlexItem -> FlexItem)`). Discharging pointer aliasing requires a localized **Separation Logic pass (via Iris/BRiCk)** at the ITree level to prove that `&item` is disjoint from the `FlexLine` scalar fields (`remaining_free_space_`, `total_flex_grow_`), allowing us to soundly erase memory addresses in the `LayoutM` layer.

##### `LayoutUnit` Fixed-Point Arithmetic
Blink's `LayoutUnit` (`third_party/blink/renderer/platform/geometry/layout_unit.h`) is a 32-bit signed saturating fixed-point number with 6 fractional bits (`kFixedPointDenominator = 64`).
* **Formalization:** We must *not* abstract `LayoutUnit` to mathematical rationals ($\mathbb{Q}$) or reals ($\mathbb{R}$), because Flexbox layout stability depends on exact clamping, saturation, and sub-pixel quantization errors (e.g., `LayoutUnit::FromFloatCeil`, `LayoutUnit::Clamp`).
* We formalize `LayoutUnit` using CompCert's 32-bit machine integers (`Int.int`) wrapped in a record, faithfully mirroring `base::ClampAdd` and `base::ClampSub`:
  ```coq
  Record LayoutUnit := mkLayoutUnit { raw_val : Int32.int }.
  Definition kFixedPointDenominator : Z := 64.
  Definition kIntMaxForLayoutUnit : Z := (2^31 - 1) / kFixedPointDenominator.

  Definition Saturate (z : Z) : Int32.int :=
    Int32.repr (Z.max (-2147483648) (Z.min 2147483647 z)).

  Definition LayoutUnit_Add (a b : LayoutUnit) : LayoutUnit :=
    mkLayoutUnit (Saturate (Int32.signed a.(raw_val) + Int32.signed b.(raw_val))).

  Definition LayoutUnit_Mul (a b : LayoutUnit) : LayoutUnit :=
    (* Mirrors Blink's int64_t intermediate cast *)
    let prod := (Int32.signed a.(raw_val) * Int32.signed b.(raw_val)) / kFixedPointDenominator in
    mkLayoutUnit (Saturate prod).
  ```

##### IEEE-754 Floating-Point Fallbacks (`double` / `float`)
In `ResolveFlexibleLengths`, `total_flex_grow_` and `total_weighted_flex_shrink_` are accumulated in `double`, and the proportional share of free space is computed as:
$$\text{extra\_space} = \text{remaining\_free\_space} \times \frac{\text{flex\_factor}}{\text{total\_flex\_factor}}$$
before converting back via `LayoutUnit::FromDoubleRound`.
* **Formalization:** Use **Flocq** (`Coq.Reals` / `Flocq.IEEE754.BinarySingleNaN`), which is already integrated into CompCert. `double` is modeled as `binary64` (`b64_plus`, `b64_div`, `b64_mult` with rounding mode `mode_NE` — round to nearest, ties to even).
* **Determinism Guarantee:** C++20 leaves contraction of floating-point expressions (e.g., FMA — Fused Multiply-Add) implementation-defined (`#pragma STDC FP_CONTRACT`). Blink compiles with `-ffp-contract=off` (or deterministic IEEE semantics on V8/Blink targets). Our Flocq model enforces strict IEEE-754 binary64 step-by-step rounding without FMA contraction, matching Clang's default x86_64/ARM64 emission for Blink.

##### Early Returns, `break`, and `continue`
C++ loops with multiple exits (e.g., returning `false` early in `ResolveFlexibleLengths` when `sum_hypothetical_main_size` overflows or when `total_flex_factor == 0`) are modeled using a **Control-Flow Monad Transformer** (`ExceptT ReturnVal (State LayoutState)`). Inside loop bodies, `break` and `continue` are captured by a sum type:
```coq
Variant LoopControl (A B : Type) :=
  | LoopContinue (s : A)
  | LoopBreak (res : B).
```
This allows syntactic 1-to-1 translation of C++ statements into monadic bind chains without restructuring the control flow graph (CFG) prior to verification.

---

### 2. Architecture for Translation & Equivalence

#### 2.1 Automated Ingestion Pipeline: Rejecting LLVM IR in Favor of Clang AST
Translating via **LLVM bitcode (Vellvm)** is an anti-pattern for Blink C++20 verification. By the time Clang emits LLVM IR, `LayoutUnit` overloaded operators are inlined, `wtf::Vector` abstractions are shattered into raw `getelementptr` byte offsets, C++ references are lowered to raw pointers, and loop structures are flattened into unstructured basic blocks with $\phi$-nodes. Reconstructing high-level structural invariants from LLVM IR is intractable.

Instead, we build the pipeline on **Clang LibTooling + BedRock's `cpp2v` (BRiCk)**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Chromium Build System (GN / Ninja)                                      │
│  └── Generates compile_commands.json for third_party/blink/renderer/... │
└───────────────────┬─────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Phase 1: Clang AST Slicer & Normalizer (Clang LibTooling)               │
│  ├── Parses C++20 AST with full template instantiation                  │
│  ├── Isolates target methods (e.g., FlexLine::ResolveFlexibleLengths)   │
│  └── Stubs out non-semantic Blink infra (DCHECK, TRACE_EVENT, Oilpan)   │
└───────────────────┬─────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Phase 2: cpp2v / BRiCk Frontend                                         │
│  └── Translates Clang AST directly into Coq Deep Embedding (Lang.cpp)   │
└───────────────────┬─────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Phase 3: Verified Lifting & Equivalence Engine (Coq / Rocq)             │
│  ├── Level 0: BRiCk C++ Semantics (Separation Logic over C++ Memory)    │
│  ├── Level 1: ITree / Monadic Functional Spec (Auto-generated via Ltac2)│
│  └── Level 2: Pure Gallina Spec (Target for Specialization & Extraction)│
└─────────────────────────────────────────────────────────────────────────┘
```

1. **AST Slicing & Macro Sanitization:** Blink code is littered with `DCHECK(...)`, `SECURITY_DCHECK(...)`, and Oilpan garbage collection macros (`DISALLOW_NEW()`, `Member<T>`). We run a custom Clang AST frontend action using `compile_commands.json` generated by Chromium's `gn gen out/Default --export-compile-commands`. We map `DCHECK(cond)` to an explicit formal assertion node `Assert(cond)` in the AST (enabling us to *prove* that Blink's runtime assertions never fire!) and strip telemetry macros (`TRACE_EVENT0`).
2. **AST-to-Coq Emission (`cpp2v`):** `cpp2v` translates the Clang AST into a deeply embedded Coq representation that faithfully preserves C++20 value categories (`lvalue`, `xvalue`, `prvalue`), struct layouts, and destructor scopes.

#### 2.2 Defining and Proving Semantic Equivalence
To prove that our pure Gallina specification $F_{\text{spec}}$ is equivalent to the deeply embedded C++ function $P_{\text{cpp}}$, we use a **Two-Stage Refinement Strategy**:

##### Stage A: C++ AST to Monadic Spec via Separation Logic Refinement (BRiCk / Iris)
We define an abstraction relation (Representation Predicate in Separation Logic) $\mathcal{R}_{\text{FlexLine}}$ that links the C++ heap/stack state $\sigma_{\text{cpp}}$ to the Coq record `fl : FlexLine_Model`:
$$\mathcal{R}_{\text{FlexLine}}(\text{ptr}, \text{fl}) \triangleq \text{ptr} \mapsto_{\text{FlexLine}} \{ \text{line\_items} : \vec{p}_{\text{items}}, \text{main\_axis\_extent} : \text{fl.extent}, \dots \} * \Asterisk_{i=0}^{n-1} \mathcal{R}_{\text{FlexItem}}(\vec{p}_{\text{items}}[i], \text{fl.items}[i])$$

We then prove a **Total Correctness Hoare Triple** (which implies forward simulation in deterministic C++):
$$\forall \text{fl}_0, \quad \{ \mathcal{R}_{\text{FlexLine}}(\text{this}, \text{fl}_0) \} \quad \text{FlexLine::ResolveFlexibleLengths}(\text{this}) \quad \{ v.\, \exists \text{fl}_1,\, \mathcal{R}_{\text{FlexLine}}(\text{this}, \text{fl}_1) \wedge (v, \text{fl}_1) = F_{\text{monadic}}(\text{fl}_0) \}$$
*Automation:* Because `ResolveFlexibleLengths` performs no dynamic graph manipulation, we can automate 90% of this proof using **Ltac2 symbolic execution tactics** that step through the C++ AST and synthesize the corresponding `LayoutM` monadic binds on the fly.

##### Stage B: Monadic Spec to Pure Gallina Spec via Equational Refinement
For loops, $F_{\text{monadic}}$ uses a `while` combinator bounded by fuel $k$. We prove equivalence to the pure structural recursion $F_{\text{spec}}$ by establishing a well-founded measure $\mu(\text{fl})$:
$$\mu(\text{fl}) = \text{count}(\lambda \text{item}.\, \neg \text{item.frozen}, \text{fl.items})$$
In `ResolveFlexibleLengths`, every iteration of the `while (true)` loop either:
1. Breaks out immediately (`remaining_free_space == 0` or `total_flex_factor == 0`), or
2. Freezes at least one item (`violations` are clamped and frozen), or
3. Freezes *all* remaining items if no clamping violation occurred.

Thus, $\mu(\text{fl})$ strictly decreases on every non-breaking iteration, proving that fuel $k = |\text{fl.items}| + 1$ is sufficient and exact:
$$\forall \text{fl},\, \text{ fuel} \ge |\text{fl.items}| + 1 \implies F_{\text{monadic}}(\text{fl}, \text{fuel}) = \text{Ok}(F_{\text{spec}}(\text{fl}))$$

---

### 3. Executability & Dual-Role Specification

#### 3.1 Reconciling Proof Ergonomics with Execution Speed
A naive specification optimized for proof ease (e.g., using unary `nat`, Peano arithmetic, or axiomatized reals) will time out or OOM when extracted. Conversely, low-level bit-blasted code is painful for induction. We resolve this via **Refinement Types and Typeclasses (CoqEAL / Momentous Refinement)**:

1. **Computable Types by Default:** The specification uses `Z` (binary integers), CompCert's `Int32.int` (wrapped over `Z`), and Flocq's `binary64` (which computes in Coq via `vm_compute` / `native_compute` using binary integer mantissas and exponents).
2. **Separation of Control and Data:** We express loops using a well-founded recursion combinator (`Function ... {measure ...}` or `Equations`) where the computational content is pure tail-recursion, and the proof obligations (the decreasing measure) are placed in `Prop`. During extraction (or `vm_compute`), Coq's extraction mechanism completely erases all `Prop` terms, leaving zero-overhead tail-recursive loops.
3. **Avoidance of Axiom Poisoning:** To guarantee `vm_compute` and extraction never get stuck on uninhabited axioms, we ban `Classical_Prop.classic` and `FunctionalExtensionality` inside `Type`/`Set` definitions. All decidability checks (e.g., `LayoutUnit_lt_dec a b`) return computable `bool`s coupled with `reflect` lemmas (`Bool.reflect (a < b) (ltb a b)`), mengikuti the **SSReflect** methodology.

#### 3.2 Extraction Pipeline & WPT / Reftest Integration
Instead of extracting to OCaml/Haskell and dealing with foreign function interface (FFI) marshaling overhead and GC pauses inside Chromium, we use a **Dual-Target Extraction Pipeline**:

```
                  ┌──────────────────────────────────────────┐
                  │ Verified Pure Gallina Spec (Coq / Rocq)  │
                  └───────────┬──────────────────┬───────────┘
                              │                  │
        [CertiCoq / C-Backend]│                  │[Coq OCaml Extraction / Native]
                              ▼                  ▼
       ┌───────────────────────────────┐  ┌────────────────────────────────┐
       │ Verified C/Rust Object (.o)   │  │ Standalone Layout CLI Runner   │
       │ Linked into Blink C++ Binary  │  │ (JSON WPT Test Vector Harness) │
       └──────────────┬────────────────┘  └────────────────────────────────┘
                      │
                      ▼
       ┌───────────────────────────────┐
       │ Differential Shadow Execution │
       │ Inside Chromium Content Shell │
       │ (Runs full WPT & Reftests)    │
       └───────────────────────────────┘
```

1. **In-Tree Differential Shadow Execution (The Gold Standard for Browser Verification):**
   Using **CertiCoq** (which compiles Gallina directly to CompCert Clight/C) or **Coq-to-Rust extraction (via `coq-of-rust` / Crane)**, we compile our verified `ResolveFlexibleLengths_Spec` into a static library `libverified_flex.a` and link it directly into Chromium's `content_shell` target via `BUILD.gn`.
2. **The Shadow Hook:** In `third_party/blink/renderer/core/layout/flex/flexible_box_algorithm.cc`, we inject a shadow-execution wrapper:
   ```cpp
   bool FlexLine::ResolveFlexibleLengths() {
   #if BUILDFLAG(ENABLE_VERIFIED_LAYOUT_SHADOW)
     // 1. Serialize pre-state of FlexLine to C ABI struct
     VerifiedFlexLine c_state = MarshalToVerified(*this);
     // 2. Execute extracted Coq code
     bool verified_ret = coq_ResolveFlexibleLengths(&c_state);
   #endif

     // 3. Execute original C++ implementation
     bool orig_ret = ResolveFlexibleLengths_Original();

   #if BUILDFLAG(ENABLE_VERIFIED_LAYOUT_SHADOW)
     // 4. Assert bit-exact equivalence across the entire WPT suite!
     CHECK_EQ(orig_ret, verified_ret);
     AssertFlexLineStateBitExact(*this, c_state);
   #endif
     return orig_ret;
   }
   ```
3. **Why this works for WPT:** Running WPT (`third_party/blink/web_tests/external/wpt/css/css-flexbox/`) requires a full HTML parser, CSS cascade engine, font metrics (`HarfBuzz`), and painting pipeline. You *cannot* run WPT against a standalone Flexbox model in isolation without mocking the entire browser. By linking the extracted spec *into* `content_shell` in shadow mode (or replacement mode), we run all 2,000+ WPT Flexbox tests and Chromium reftests natively, verifying both our formal model and our boundary assumptions against real-world DOM trees.

---

### 4. Step-by-Step Specialization & Partial Evaluation (Staging)

To scale step-by-step specialization (e.g., specializing `ResolveFlexibleLengths` for `gap = 0`, `sign = PositiveFlexibility`, `items.size() = 3`, and fixed `min/max` constraints), manual lemma-by-lemma rewriting does not scale. We need a principled **Verified Partial Evaluation and Staging Architecture** inside Coq.

#### 4.1 Semantic Design for Specialization: Intensional Staging vs. Extensional Rewriting
There are two complementary ways to architect the specification for specialization:

1. **Extensional Equational Specialization (via Typeclass-Driven Rewriting & MetaCoq):**
   Keep the specification as a standard pure Gallina function:
   ```coq
   Definition ResolveFlexibleLengths (cfg : FlexConfig) (items : list FlexItem) : list FlexItem := ...
   ```
   We define a **Specialization Relation**:
   ```coq
   Definition SpecializesTo {A B} (f_gen : A -> B) (P : A -> Prop) (f_spec : A -> B) : Prop :=
     forall x, P x -> f_gen x = f_spec x.
   ```
   To automate the synthesis of `f_spec` given a predicate `P` (e.g., `P cfg := cfg.(gap) = LayoutUnit 0 /\ cfg.(flex_sign) = Positive`), we build a **Verified Partial Evaluator using MetaCoq (Template-Coq)** or **Ltac2**:
   * **Step 1 (Unfolding & $\beta\iota$-reduction):** Substitute known constants from `P` into `f_gen`.
   * **Step 2 (Dead-Branch Elimination):** When encountering `if LayoutUnit_ltb free_space 0 then ... else ...`, use the context hypothesis `free_space >= 0` (from `PositiveFlexibility`) to rewrite the condition to `false` and reduce the `if` expression.
   * **Step 3 (Loop Unrolling / Bounds Specialization):** When `items` has a statically known length (e.g., a 3-column layout template `items = [i1; i2; i3]`), the fuel $k = 4$ is a concrete numeral `S (S (S (S O)))`. Simplifying the recursion unrolls the fixed-point solver into a straight-line sequence of branches.
   * **Step 4 (Algebraic Identity Simplification):** Apply verified ring/field/saturation identities for `LayoutUnit`:
     $$\text{LayoutUnit\_Add}(x, \text{LayoutUnit } 0) = x$$
     $$\text{ClampSizeToMinAndMax}(x, 0, \text{kMaxLayoutUnit}) = \text{LayoutUnit\_Max}(x, 0)$$

2. **Intensional Staged Computation (Two-Level Type Theory / 2LTT in Coq):**
   When we want to *compile* a CSS layout template (e.g., a reusable UI component with static CSS rules and dynamic text content) into a fast residual layout function (First Futamura Projection), we structure the semantics using a **Binding-Time Divided Signature**:
   * **Static (Compile-Time) Parameters ($\mathcal{S}$):** `flex-direction`, `flex-wrap`, number of items $N$, static `flex-grow`/`flex-shrink` constants, presence of `min-width`/`max-width` constraints (`Option LayoutUnit`), `gap` (if specified in `px`).
   * **Dynamic (Run-Time) Parameters ($\mathcal{D}$):** `container_main_size : Code LayoutUnit`, item `flex_base_content_size : Code LayoutUnit`.

   Using **Deeply Embedded Residual Code (`Expr`)** with a verified denotational semantics $\llbracket \cdot \rrbracket$:
   ```coq
   (* Staged Layout Specification *)
   Definition Staged_ClampSize 
     (static_min : option LayoutUnit) 
     (static_max : option LayoutUnit) 
     (dyn_val : Expr LayoutUnit) : Expr LayoutUnit :=
     let e1 := match static_min with
               | Some m => E_Max dyn_val (E_Const m)
               | None => dyn_val
               end in
     match static_max with
     | Some M => E_Min e1 (E_Const M)
     | None => e1
     end.

   Theorem Staged_ClampSize_Sound : forall s_min s_max d_val env,
     eval env (Staged_ClampSize s_min s_max d_val) = 
     ClampSizeToMinAndMax (eval env d_val) s_min s_max.
   ```
   **Why this is powerful:** Notice that in `Staged_ClampSize`, the `match` on `static_min` and `static_max` happens at *specialization time* (in the meta-language). If an item has `max-width: none` (represented as `None`), the residual expression `Expr LayoutUnit` contains *zero* branches for the max bound! The soundness theorem `Staged_ClampSize_Sound` proves once and for all that *every* specialized residual AST produced by the staging engine is semantically identical to the general unspecialized specification.

---

### 5. Concrete Roadmap & Pitfalls

#### 5.1 Major Hazards in Blink's Codebase & Mitigation Strategies

| Hazard in Chromium Blink | Concrete Manifestation in `core/layout/` | Formal Mitigation Strategy |
| :--- | :--- | :--- |
| **1. Cyclical Dependencies & Intrinsic Sizing Callbacks** | `FlexLayoutAlgorithm` calls `BuildFlexItems`, which queries `ComputeMinMaxSizes` or invokes `Layout()` recursively on orthogonal children (e.g., a vertical grid inside a horizontal flexbox) to find `flex_base_content_size`. | **Compositional Oracle Cutting (Assume-Guarantee):** Do *not* monolithically verify the entire mutual recursion of `BlockNode::Layout` on Day 1. Parameterize the Flexbox specification by an abstract **Child Sizing Oracle** (`ChildLayoutOracle : NodeId -> ConstraintSpace -> LayoutResult`) or pre-computed `FlexItem` inputs. Verify the algorithmic core assuming the oracle is pure and deterministic, then discharge the oracle compositionally via a global DOM-tree depth measure. |
| **2. `LayoutUnit` Overflow & Underflow Corner Cases** | `LayoutUnit::Max()` (`33,554,431.984375px`) is used as a sentinel for "unconstrained/infinite" space (`kIndefiniteSize = LayoutUnit(-1)`). Arithmetic on sentinels without prior checks causes silent saturation bugs. | **Refinement Types for Sentinels:** In the high-level spec, lift raw `LayoutUnit` values that may be `-1` (indefinite) or `LayoutUnit::Max()` into an explicit algebraic data type (`IndefiniteOrDefinite LayoutUnit`), and prove via the C++ refinement relation that Blink's sentinel checks (`if (size == kIndefiniteSize)`) accurately guard all arithmetic operations. |
| **3. Floating-Point Non-Determinism & Precision Loss** | Accumulating `total_flex_grow_` in `float`/`double` and multiplying by `remaining_free_space_.ToDouble()` can behave differently if the C++ compiler reorders operations or uses 80-bit x87 registers vs 64-bit SSE2/NEON. | **Strict IEEE-754 Pinning:** Chromium builds on modern 64-bit platforms exclusively use SSE2 (x86_64) or NEON (ARM64) for `float`/`double`. By using Flocq's `binary32`/`binary64` with strict AST evaluation order, we match hardware execution bit-for-bit. We explicitly prove absence of `NaN` propagation by establishing preconditions that input `flex_grow` $\ge 0$ and $< \infty$. |
| **4. Oilpan GC (`HeapVector`, `Member<T>`) & Stack Lifetime (`STACK_ALLOCATED()`)** | Blink uses Oilpan (`cppgc`) for garbage-collected layout objects (`LayoutBlock`, `PhysicalFragment`) and `STACK_ALLOCATED()` for algorithms (`FlexLayoutAlgorithm`). | **Lifetime Erasure via Read-Only Framing:** Layout algorithms in Blink NG (`LayoutNG`) were specifically architected to take immutable inputs (`BlockNode`, `ConstraintSpace`) and produce immutable outputs (`PhysicalBoxFragment`). Mutability is strictly confined to `STACK_ALLOCATED()` builder objects (`FlexLine`, `BoxFragmentBuilder`). This allows us to treat the Oilpan heap as a **read-only environment** during a single layout pass, avoiding the need to formalize Oilpan's garbage collector! |
| **5. Undefined Behavior (UB) in C++ Containers** | Out-of-bounds indexing on `wtf::Vector`, uninitialized fields in `FlexItem`, or signed integer overflow outside `LayoutUnit`. | **BRiCk / Clight Safety Obligations:** The C++-to-ITree translation emits explicit `angelic/demonic UB` events for signed overflow and out-of-bounds array access. Proving refinement to the pure Gallina spec *forces* the verifier to discharge all array bounds and initialization checks. |

#### 5.2 Pragmatic Step-by-Step Engineering Pipeline

##### Phase 1: The Pure Core & Shadow Harness (Months 1–3)
* **Target:** `FlexItem::ClampSizeToMinAndMax`, `FlexLine::ResolveFlexibleLengths`, and `FlexLine::FreezeViolations` (`flexible_box_algorithm.cc`).
* **Action:**
  1. Formalize `LayoutUnit` (exact 32-bit saturating fixed-point) and Flocq `binary64` wrappers in Coq/Rocq.
  2. Build the **Shadow Execution Harness** in Chromium: extract the Coq spec of `ResolveFlexibleLengths` to C (via CertiCoq or a clean C printer for the first iteration), link it into `content_shell`, and run the entire WPT `css-flexbox` test suite.
  3. **Milestone:** Zero discrepancies between C++ and extracted Coq across all WPT Flexbox tests. (This immediately validates your semantics of `LayoutUnit` and float rounding before investing in heavy C++ AST proofs).

##### Phase 2: Automated C++ AST Ingestion & Equivalence Proofs (Months 4–6)
* **Target:** Automated verification of the Phase 1 C++ functions against the Gallina spec.
* **Action:**
  1. Set up the Clang LibTooling pass + `cpp2v` (BRiCk) on `flexible_box_algorithm.cc` using Chromium's `compile_commands.json`.
  2. Define the Separation Logic representation predicates ($\mathcal{R}_{\text{FlexLine}}$, $\mathcal{R}_{\text{FlexItem}}$).
  3. Write Ltac2 symbolic execution automation to prove that the `cpp2v` AST refines the monadic `LayoutM` specification, and discharge the termination measure for `ResolveFlexibleLengths`.
  4. **Milestone:** Machine-checked proof in Coq that the exact C++20 AST compiled by Clang in Chromium refines the pure Gallina spec, with zero unverified transcription steps.

##### Phase 3: Verified Staging & Partial Evaluation Framework (Months 7–9)
* **Target:** Automated specialization of Flexbox layout paths.
* **Action:**
  1. Implement the MetaCoq / Staged Computation framework over the pure Gallina spec.
  2. Prove the master **Specialization Soundness Theorem** (`SpecializesTo` preservation under dead-branch elimination, loop unrolling for fixed item counts, and `LayoutUnit` algebraic identities).
  3. Generate specialized C++ layout fast-paths for common DOM templates (e.g., 1D navigation bars, fixed-count card grids with `gap: 0` and `flex-shrink: 0`) and benchmark them inside Blink.
  4. **Milestone:** Verified generation of specialized C++ fast-paths with machine-checked equivalence to the general Flexbox algorithm.

##### Phase 4: Scaling Up to `FlexLayoutAlgorithm` & Cross-Axis Alignment (Months 10–12)
* **Target:** `FlexLayoutAlgorithm::ConstructAndAppendFlexItems`, `GiveItemsFinalPositionAndSize`, and `PlaceFlexItems` (`flex_layout_algorithm.cc`).
* **Action:**
  1. Introduce the **Compositional Child Sizing Oracle** to cleanly abstract `BlockNode::Layout` and `ComputeMinMaxSizes` calls.
  2. Formalize `ConstraintSpace` and `PhysicalBoxFragment` immutability invariants (leveraging Blink's `LayoutNG` functional architecture).
  3. Extend the shadow execution harness and `cpp2v` equivalence pipeline to cover the end-to-end `FlexLayoutAlgorithm::Layout()` method.
  4. **Milestone:** Full formal specification and verified equivalence of Chromium Blink's `LayoutNG` Flexbox engine.