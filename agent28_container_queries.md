### 1. Core Data Structures in Blink Container Queries

Within the Chromium Blink layout engine (`third_party/blink/renderer/core/css/`), Container Queries (W3C CSS Containment Module Level 3) are mediated by a tight coupling between the style resolution pass and the Next-Generation (LayoutNG) layout tree. 

#### `ContainerQueryEvaluator` (`container_query_evaluator.h`)
Owned by a container `Element` (specifically via `ElementRareDataVector`), `ContainerQueryEvaluator` caches the geometric and stylistic state of a container and evaluates dependent `@container` rules.
*   **State Tracking:** Maintains the last known `PhysicalSize` (width and height in `LayoutUnit`), the active `PhysicalAxes` contained by the layout object, and an `EvaluationResult` hash map (`HeapHashMap<Member<const ContainerQuery>, Result>`) to memoize query evaluations across style recalcs.
*   **Invalidation (`ContainerChanged`):** Invoked during `LayoutNGBlockNode::Layout` when the physical dimensions or axis containment of a container mutate. It compares the new `PhysicalSize` against the cached size, computes a `Change` enum (`kNone`, `kNearestContainer`, `kDescendantContainers`), and triggers `StyleEngine::ScheduleContainerQueryRecalc` if cached query results flip boolean states.

#### `ContainerSelector` (`container_selector.h`)
An immutable signature representing the target criteria of a `@container` rule. It is extracted during AST construction (`CSSContainerRule`) and used as a lookup key in `ContainerSelectorCache`.
*   **Fields:**
    *   `AtomicString name_`: The target `container-name` (empty if unnamed).
    *   `unsigned type_Flags`: Bitmask of required `EContainerType` values (`kContainerTypeNormal = 0x0`, `kContainerTypeInlineSize = 0x1`, `kContainerTypeSize = 0x3`), derived automatically by inspecting the media features inside the query (e.g., `inline-size` queries require inline containment; `block-size` or `height` requires full `size` containment).
    *   `LogicalAxes logical_axes_`: Bitmask (`kLogicalAxesNone`, `kLogicalAxesInline`, `kLogicalAxesBlock`, `kLogicalAxesBoth`) required by the query's dimensional features.
    *   `PhysicalAxes physical_axes_`: Bitmask (`kPhysicalAxesNone`, `kPhysicalAxesHorizontal`, `kPhysicalAxesVertical`, `kPhysicalAxesBoth`) required by explicit `width`, `height`, or `orientation` features.
    *   `bool has_style_query_`: Indicates dependency on `style(...)` evaluation.
    *   `bool has_sticky_query_` / `bool has_snap_query_`: State queries (`scroll-state(...)`).

#### `PhysicalAxes` and `LogicalAxes` (`geometry/axis.h`)
Strongly typed bitmasks representing 2D spatial axes. 
*   `PhysicalAxes`: $\mathcal{P}(\{\text{Horizontal}, \text{Vertical}\})$ encoded as `0b00`, `0b01` ($X$), `0b10` ($Y$), `0b11` ($X \cup Y$).
*   `LogicalAxes`: $\mathcal{P}(\{\text{Inline}, \text{Block}\})$.
*   **Coordinate Transformation (`ToPhysicalAxes`):** Blink resolves `LogicalAxes` to `PhysicalAxes` dynamically using the container’s `ComputedStyle::GetWritingMode()`. 
    $$\text{ToPhysicalAxes}(\text{axes}, \text{wm}) = \begin{cases} \text{axes} & \text{if } \text{IsHorizontalWritingMode}(\text{wm}) \\ \text{ Transpose}(\text{axes}) & \text{otherwise} \end{cases}$$
    where $\text{Transpose}(\text{Inline}) = \text{Vertical}$ and $\text{Transpose}(\text{Block}) = \text{Horizontal}$.

#### `ContainerQueryUnit` (`css_primitive_value.h` / `css_to_length_conversion_data.h`)
Container query length units (`cqw`, `cqh`, `cqi`, `cqb`, `cqmin`, `cqmax`) are represented as variants of `CSSPrimitiveValue::UnitType` (`kContainerWidth`, `kContainerHeight`, `kContainerInlineSize`, `kContainerBlockSize`, `kContainerMin`, `kContainerMax`).
*   **Resolution:** Handled by `CSSToLengthConversionData::ContainerSizes`. When resolving a unit on an element $E$, Blink climbs the flat-tree ancestor chain of $E$. 
*   **Axis-Specific Fallback:** Unlike `@container` rule matching (which selects a single container for the entire rule), `cqw` and `cqh` independently search for the nearest ancestor whose `container-type` establishes containment on the *specific* physical or logical axis required by that unit. If no such ancestor exists, it falls back to the **small viewport size** (`svw`, `svh`).

---

### 2. Container Selection Algorithm

In W3C CSS Containment Level 3 § 5.2, the container for a given `@container` rule is resolved by traversing the **flat tree** (accounting for Shadow DOM slot assignments) starting from the parent of the subject element.

#### Blink Implementation (`ContainerQueryEvaluator::FindContainer`)
Given a subject element $E$, a `ContainerSelector` $S$, and a `TreeScope` $T_{\text{scope}}$:

1.  **Required Axes Derivation:**
    Let $A_{\text{req\_phys}}(S)$ be $S.\text{physical\_axes\_}$, and $A_{\text{req\_log}}(S)$ be $S.\text{logical\_axes\_}$.
2.  **Ancestor Traversal:**
    Initialize pointer $P \leftarrow \text{FlatTreeTraversal::ParentElement}(E)$.
    While $P \neq \text{nullptr}$:
3.  **Style & Containment Extraction:**
    Fetch `const ComputedStyle* style = P->GetComputedStyle()`. If `style == nullptr`, $P$ cannot be a container; advance $P \leftarrow \text{FlatTreeTraversal::ParentElement}(P)$.
4.  **Axis Capability Computation:**
    Let $C_{\text{type}} = \text{style->ContainerType()}$.
    Let $W_m = \text{style->GetWritingMode()}$.
    Compute the physical axes provided by $P$:
    $$A_{\text{prov\_phys}}(P) = \begin{cases} \text{Both} & \text{if } C_{\text{type}} = \text{kContainerTypeSize} \\ \text{ToPhysicalAxes}(\text{Inline}, W_m) & \text{if } C_{\text{type}} = \text{kContainerTypeInlineSize} \\ \text{None} & \text{if } C_{\text{type}} = \text{kContainerTypeNormal} \end{cases}$$
    Compute the total physical axes required by $S$ in the context of $P$'s writing mode:
    $$A_{\text{target\_phys}}(S, P) = A_{\text{req\_phys}}(S) \cup \text{ToPhysicalAxes}(A_{\text{req\_log}}(S), W_m)$$
5.  **Containment Sufficiency Check:**
    Verify bitwise inclusion: $A_{\text{target\_phys}}(S, P) \subseteq A_{\text{prov\_phys}}(P)$. If false, $P$ does not establish the required dimensional containment; continue traversal.
6.  **Name Matching (`MatchesContainerName`):**
    If $S.\text{name\_}$ is non-empty:
    *   Inspect `const ScopedCSSNameList* names = style->ContainerName()`.
    *   Verify $\exists n \in \text{names}$ such that $n.\text{GetName}() = S.\text{name\_}$ AND $n.\text{GetTreeScope}()$ is an inclusive ancestor of (or matches) $T_{\text{scope}}$ according to CSS Scoping rules.
    *   If no name matches, continue traversal.
7.  **Termination:**
    Return $P$ as the selected container. If the loop terminates ($P = \text{nullptr}$), return $\text{nullptr}$ (causing the `@container` query to evaluate to `false` / `unknown`).

---

### 3. Size Query Evaluation Against Container Dimensions

Size evaluation is executed by `MediaQueryEvaluator::Eval(const MediaQueryExpNode&, ...)` parameterized by a `MediaValues` instance instantiated from the selected container (`ContainerMediaValues`).

#### `ContainerMediaValues` (`media_values.h`)
Extracts the physical dimensions $(W_c, H_c) \in \mathbb{Q}_{\ge 0} \times \mathbb{Q}_{\ge 0}$ (represented in Blink as fixed-point `LayoutUnit` with $1/64\text{th}$ CSS pixel precision, converted to `double` for media evaluation) of the container's content box, alongside its `WritingMode`, `FontSizes`, and `LineHeight`.

#### Expression Tree Evaluation
A `@container` size query is parsed into an AST of `MediaQueryExpNode` subclasses (`MediaQueryFeatureExpNode`, `MediaQueryNotExpNode`, `MediaQueryAndExpNode`, `MediaQueryOrExpNode`, `MediaQueryUnknownExpNode`).
Because W3C specifications mandate **Three-Valued Logic (Kleene $K_3$)** to handle unknown features or missing axes, Blink evaluates nodes to `KleeneValue` $\in \{\text{kTrue}, \text{kFalse}, \text{kUnknown}\}$:

$$\neg \text{kTrue} = \text{kFalse}, \quad \neg \text{kFalse} = \text{kTrue}, \quad \neg \text{kUnknown} = \text{kUnknown}$$
$$A \land B = \min(A, B), \quad A \lor B = \max(A, B) \quad (\text{under ordering } \text{kFalse} < \text{kUnknown} < \text{kTrue})$$

At the root of the query (`ContainerQueryEvaluator::Eval`), `kTrue` maps to `true`, while both `kFalse` and `kUnknown` collapse to `false`.

#### Dimensional Feature Evaluation (`EvalFeature`)
Let the queried feature be $f \in \{\text{width}, \text{inline-size}, \text{height}, \text{block-size}\}$.
1.  **Axis Validation:** If the container's `PhysicalAxes` do not cover the axis of $f$ (which can occur in complex `or` queries where `ContainerSelector` only mandates the union/intersection of axes, or if `container-type: normal` was matched for a mixed style/size query), `EvalFeature` immediately returns `kUnknown`.
2.  **Value Extraction:**
    $$V_{\text{actual}} = \begin{cases} W_c & \text{if } f = \text{width} \lor (f = \text{inline-size} \land \text{IsHorizontal}(W_m)) \lor (f = \text{block-size} \land \neg\text{IsHorizontal}(W_m)) \\ H_c & \text{if } f = \text{height} \lor (f = \text{block-size} \land \text{IsHorizontal}(W_m)) \lor (f = \text{inline-size} \land \neg\text{IsHorizontal}(W_m)) \end{cases}$$
3.  **Bounds Comparison (`MediaQueryExpBounds`):**
    A feature node contains `MediaQueryExpBounds`, which holds a `left` (`MediaQueryExpComparison`) and `right` (`MediaQueryExpComparison`) bound to support Media Queries Level 4 range syntax (e.g., `300px <= width < 500px`), as well as legacy `min-width` (mapped to $V_{\text{bound}} \le V_{\text{actual}}$) and `max-width` (mapped to $V_{\text{actual}} \le V_{\text{bound}}$).
    Each bound consists of a resolved pixel length $L \in \mathbb{Q}$ and a relational operator $\bowtie \in \{<, \le, =, \ge, >\}$.
    $$\text{Compare}(x, \bowtie, y) = \begin{cases} \text{kTrue} & \text{if } x \bowtie y \text{ holds in } \mathbb{Q} \\ \text{kFalse} & \text{otherwise} \end{cases}$$
    For range bounds $(L_1 \bowtie_1 f \bowtie_2 L_2)$:
    $$\text{EvalBounds}(V_{\text{actual}}, \text{bounds}) = \text{Compare}(L_1, \bowtie_1, V_{\text{actual}}) \land \text{Compare}(V_{\text{actual}}, \bowtie_2, L_2)$$

---

### 4. Mathematical Invariants

1.  **Query Evaluation Determinism:**
    For any fixed flat-tree topology $\mathcal{T}$, element $e \in \mathcal{T}$, container query AST $Q$, and state assignment $\Sigma : \mathcal{T} \to \text{ComputedStyle} \times (\mathbb{Q}_{\ge 0} \times \mathbb{Q}_{\ge 0})$, the evaluation relation $\mathcal{E}(\mathcal{T}, \Sigma, e, Q)$ is a total function mapping to $\mathbb{B}$.
2.  **Monotonicity of Min/Max Container Width Queries:**
    *   **Covariant (`min-width`):** Let $Q_{\text{min}}(w_0)$ represent the feature query $\text{min-width}: w_0$. For any container $c$ with valid horizontal containment and physical widths $W_1, W_2 \in \mathbb{N}$ (representing fixed-point `LayoutUnit` ticks):
        $$W_1 \le W_2 \implies \left( \text{Eval}(Q_{\text{min}}(w_0), W_1) = \text{kTrue} \implies \text{Eval}(Q_{\text{min}}(w_0), W_2) = \text{kTrue} \right)$$
    *   **Contravariant (`max-width`):** Let $Q_{\text{max}}(w_0)$ represent $\text{max-width}: w_0$.
        $$W_1 \le W_2 \implies \left( \text{Eval}(Q_{\text{max}}(w_0), W_2) = \text{kTrue} \implies \text{Eval}(Q_{\text{max}}(w_0), W_1) = \text{kTrue} \right)$$
3.  **Container Tree Acyclicity and Well-Foundedness:**
    Because container selection strictly traverses $\text{ParentElement}(e)$ in the DOM flat tree $\mathcal{T}$, and the flat tree is a finite directed acyclic graph (specifically, a tree), the ancestor relation $\prec_{\mathcal{T}}$ is strictly well-founded. Furthermore, because size containment (`container-type: size | inline-size`) enforces layout containment (`contain: layout size`), the geometric dimensions $(W_c, H_c)$ of an ancestor $c$ are computed **independently** of the style and layout of any descendant $e \prec_{\mathcal{T}} c$, preventing cyclic style-layout feedback loops during single-pass interleaving.

---

### 5. Rocq / Coq Formalization (`BlinkContainerQuerySemantics.v`)

The following self-contained Rocq (Coq) script formalizes the Blink data structures, coordinate transformations, Kleene $K_3$ logic, the flat-tree container selection algorithm, range/bound evaluation, and proves the core