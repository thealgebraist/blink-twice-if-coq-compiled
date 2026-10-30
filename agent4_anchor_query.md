Here is the architectural audit of Chromium Blink’s CSS `anchor-size()` evaluation engine against the W3C CSS Anchor Positioning Level 1 Specification (§4.2), complete with a formal verification model in Rocq (Coq).

---

### 1. Core Data Structures in Blink Anchor Queries

Blink’s LayoutNG architecture implements `anchor-size()` resolution by propagating anchor geometry upwards through the fragment tree and evaluating queries during the formatting of out-of-flow (OOF) positioned elements.

```
[PhysicalFragment Tree] 
       │ (Propagate during Layout)
       ▼
[PhysicalAnchorQuery] ──(Transform to Logical)──► [LogicalAnchorQuery]
       │                                                   │
       └──────────────────────┬────────────────────────────┘
                              ▼
                    [AnchorEvaluatorImpl] ◄─── [CalculationExpressionNode]
```

#### `AnchorKey` (`third_party/blink/renderer/core/layout/anchor_query.h`)
The lookup identifier for an anchor element within a query map.
```cpp
using AnchorKey = std::variant<const ScopedCSSName*, const LayoutObject*>;
```
* **Role**: Disambiguates explicit CSS author-defined anchor names (`--my-anchor`, scoped to a tree-scope via `ScopedCSSName`) from implicit anchors (resolved via DOM/layout relationships, keyed directly by `const LayoutObject*`).

#### `PhysicalAnchorQuery` & `LogicalAnchorQuery` (`anchor_query_map.h`)
Containers mapping `AnchorKey` instances to anchor fragments (`PhysicalAnchorReference` / `LogicalAnchorReference`).
* **`PhysicalAnchorQuery`**: Stores physical coordinates (`PhysicalRect` consisting of `LayoutUnit x, y, width, height`) relative to the containing block's physical coordinate space. Propagated upwards across `NGPhysicalBoxFragment` instances during layout.
* **`LogicalAnchorQuery`**: Constructed on-demand for an OOF containing block by converting the accumulated `PhysicalAnchorQuery` into the containing block's `WritingModeConverter` space.
* **`AnchorReference`**: Contains the bounding `PhysicalRect`, a pointer to the `LayoutObject`, and a singly-linked list of DOM/tree-order references to correctly resolve duplicate `anchor-name` declarations (last-in-tree-order wins).

#### `AnchorEvaluatorImpl` (`anchor_evaluator_impl.h`)
Inherits from `Length::AnchorEvaluator` (defined in `platform/geometry/calculation_expression_node.h`). This bridges the platform-level CSS `calc()` engine with the core layout engine.
* **Key Fields**:
  * `const LogicalAnchorQuery* anchor_query_`: The primary lookup map for the current containing block.
  * `const ScopedCSSName* default_anchor_`: The querying element's `position-anchor` property.
  * `WritingModeConverter container_converter_`: Converts physical fragments into the querying element's logical coordinate system.
  * `PhysicalSize available_size_`: Used for percentage resolutions inside fallbacks.
  * `bool is_y_axis_` / `bool is_right_or_bottom_`: Context flags validating query contexts and tracking dependencies.

---

### 2. Evaluation of `anchor-size(target-anchor, size-axis, fallback-length)`

In Blink, `anchor-size()` is never evaluated as a standalone CSS value; it is parsed into a `CalculationExpressionAnchorQueryNode` inside a `CalculationValue` (`calc()`), enabling direct participation in mathematical expressions (e.g., `calc(anchor-size(--a width, 20px) * 2)`).

#### Execution Trace
1. **Entry Point**: During `OutOfFlowLayoutPart::CalculateOffset()`, Blink computes the element's `inset` and `size` properties (`width`, `height`, `min-width`, etc.). When `MinimumValueForLength(length, available_size, anchor_evaluator)` encounters a `Length::kCalculated`, it evaluates the expression tree, invoking `AnchorEvaluatorImpl::Evaluate()`.
2. **Mode Validation**: `AnchorEvaluatorImpl::Evaluate()` checks if its internal `Mode` allows `anchor-size()`. If an `anchor-size()` node is evaluated inside an inset property (`top`, `left`, etc.), `AllowAnchorSize()` returns `false`, immediately returning `std::nullopt` to trigger fallback substitution.
3. **Target Resolution**: `AnchorEvaluatorImpl::ResolveAnchorReference(target_anchor)` is invoked:
   * If `target-anchor` is omitted, it uses `default_anchor_` (from `position-anchor`).
   * Looks up the `AnchorKey` in `LogicalAnchorQuery`.
   * Validates **Acceptable Anchor Element** criteria (W3C §2.1): checks containing block hierarchy, tree-order visibility, and skipping of fragments inside `display: none` or fragmentation contexts that follow the querying element.
4. **Axis Mapping (`AnchorSizeValue`)**: If a valid `LogicalAnchorReference` is found, `EvaluateAnchorSize()` extracts the `PhysicalSize` of the anchor's bounding box and resolves the requested axis:
   * **`kWidth` / `kHeight`**: Directly returns `physical_size.width` or `physical_size.height`.
   * **`kBlock` / `kInline`**: Evaluates against the **querying element’s** `WritingDirectionMode` (`container_converter_`). If the querying element is `horizontal-tb`, `kInline` maps to `width`; if `vertical-rl`, `kInline` maps to `height`.
   * **`kSelfBlock` / `kSelfInline`**: Evaluates against the **target anchor element’s** `WritingDirectionMode` (retrieved via `anchor_reference->GetLayoutObject()->StyleRef().GetWritingDirection()`).
5. **Fallback Resolution**: If `EvaluateAnchorSize()` returns `std::nullopt`, `CalculationExpressionAnchorQueryNode::Evaluate()` evaluates its fallback child `CalculationExpressionNode` instead. If no fallback was specified in CSS, the node defaults to `0px` (`LayoutUnit(0)`).

---

### 3. Circular Dependency Detection and Fallback Substitution

W3C CSS Anchor Positioning §2.1 & §4.2 mandate that layout cannot have cyclic dependencies. Blink enforces acyclicity via **Structural Staging** in `OutOfFlowLayoutPart` rather than dynamic runtime graph cycle detection (like Tarjan’s algorithm).

#### Structural Staging & Tree-Order Invariants
1. **In-Flow Precedence**: In-flow elements are laid out completely before OOF elements are processed by `OutOfFlowLayoutPart`. An in-flow anchor cannot depend on an OOF element's `anchor-size()` because `anchor-size()` is only valid on OOF positioned elements (`position: absolute` or `fixed`).
2. **OOF Tree-Order Stagings**: When an OOF element $B$ queries an OOF anchor $A$, $A$ is only present in the `LogicalAnchorQuery` if $A$ precedes $B$ in tree order **and** belongs to an equal or deeper containing block level that has already been laid out.
3. **Implicit Layout Cycle Prevention**:
   * **Cross-Property Queries (Inset $\leftarrow$ Size)**: Within a single element, `width`/`height` (where `anchor-size()` is valid) are evaluated **before** `top`/`bottom`/`left`/`right` (where `anchor()` is valid) during `ComputeOutOfFlowInsets` and `ComputeOutOfFlowSize`.
   * **Intrinsic Size Cycles**: If an element $A$ is an anchor for $B$, and $B$ attempts to affect $A$'s size (impossible for OOF $B$ unless $A$ is a scroll container clamping $B$), Blink snapshots the `LogicalAnchorQuery` **before** laying out OOF descendants that do not contribute to intrinsic sizes.
   * **Scrollable Containing Blocks (`AnchorScrollData`)**: Sizing queries do not depend on scroll offsets (`anchor-size()` only reads box dimensions, which are invariant under scrolling), eliminating scroll-induced layout cycles for size queries.

---

### 4. Mathematical Invariants, Edge Cases, and Divergences

#### Mathematical Invariants
1. **Non-Negativity Invariant**:
   $$\forall q \in \text{Query}, \text{Eval}(q) \ge 0 \quad (\text{at used-value time for sizing properties})$$
   While an interior `CalculationExpressionAnchorQueryNode` with a negative fallback `anchor-size(--a width, -50px)` can evaluate to $-50\text{px}$ inside an intermediate `calc()` tree (e.g., `calc(100px + anchor-size(--a width, -50px)) = 50px`), the final used value of any sizing property (`width`, `height`, `min-width`, etc.) is clamped to $\max(0, \text{val})$ by `LayoutUnit` clamping in `BoxLayoutAlgorithm`.
2. **Deterministic Fallback Substitution**:
   $$\text{Lookup}(\text{env}, \text{key}) = \bot \implies \text{Eval}(\text{Query}(\text{key}, \text{axis}, fb)) = \text{Eval}(fb)$$
3. **Acyclic Resolution**: The relation $x \prec y$ ("$y$ resolves `anchor-size()` against $x$") forms a strict partial order (irreflexive, asymmetric, transitive) over the set of `LayoutObject` instances.

#### Edge Cases & Spec Divergences
1. **Fragmented Anchors (Multicol / Printing)**:
   * *W3C Spec*: The size of a fragmented anchor is the size of the axis-aligned bounding box of all its fragments.
   * *Blink Implementation*: `PhysicalAnchorQuery::SetFromFragment()` unions the physical rects (`PhysicalRect::UniteEvenIfEmpty`) of fragments belonging to the same `AnchorKey`. *Edge Case*: If an anchor fragment has $0\times0$ size (e.g., collapsed empty box at a column break), `UniteEvenIfEmpty` preserves its coordinates, which may inflate the bounding box across column gaps even though the fragment has no visual paint footprint.
2. **Fixed-Position Fixed-point Iterations**:
   * In `OutOfFlowLayoutPart::LayoutOOFsInMulticol()`, Blink iterates OOF layout passes when new anchors are discovered. If an OOF element's `anchor-size()` causes a multicol container to add columns, shifting previous anchors, Blink caps layout passes (typically at 2 passes) rather than diverging infinitely, sacrificing exact fixed-point convergence for termination.
3. **`LayoutUnit` Fixed-Point Saturation**:
   * Blink represents lengths as `LayoutUnit` (32-bit signed integer with 6 fractional bits, $1/64\text{th}$ pixel precision, `kMaxLayoutUnit` $\approx 3.35 \times 10^7\text{px}$). W3C CSS Values & Units specifies theoretical IEEE-754 float semantics. Extreme `anchor-size()` dimensions saturate at `LayoutUnit::Max()` rather than following floating-point infinity/overflow rules.
4. **Display Locks (`content-visibility: auto/hidden`)**:
   * If a target anchor is inside a locked subtree (`DisplayLockUtilities::IsInLockedSubtree`), Blink skips adding its fragments to `PhysicalAnchorQuery` or rejects it in `AnchorEvaluatorImpl`, correctly triggering the fallback, though W3C Anchor Positioning leaves interaction with `content-visibility` partially under-specified.

---

### 5. Formal Verification in Rocq (Coq): `BlinkAnchorSizeSemantics.v`

The following self-contained Rocq 8.18+ script formalizes Blink's `anchor-size()` semantics, axis resolution, `calc()` integration, structural acyclicity, and proves the core layout invariants.

```coq
(** * BlinkAnchorSizeSemantics.v
    Formalization of Chromium Blink's CSS Anchor Size Query Engine
    against W3C CSS Anchor Positioning Level 1 §4.2. *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.Arith.PeanoNat.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Geometry and Writing Modes *)

(** Blink represents lengths in LayoutUnit (1/64th pixel fixed-point).
    We model LayoutUnit as Z. *)
Definition LayoutUnit := Z.

Record PhysicalSize := mkPhysicalSize {
  phys_width  : LayoutUnit;
  phys_height : LayoutUnit
}.

(** Well-formed physical fragments in Blink always have non-negative dimensions. *)
Definition wf_physical_size (s : PhysicalSize) : Prop :=
  phys_width s >= 0 /\ phys_height s >= 0.

Inductive WritingMode :=
  | HorizontalTB
  | VerticalRL
  | VerticalLR
  | SidewaysRL
  | SidewaysLR.

Definition is_horizontal (wm : WritingMode) : bool :=
  match wm with
  | HorizontalTB => true
  | _ => false
  end.

(** ** 2. Anchor Keys, References, and Queries *)

Definition ScopedCSSName := nat.
Definition LayoutObjectId := nat.

Inductive AnchorKey :=
  | KeyNamed (name : ScopedCSSName)
  | KeyImplicit (id : LayoutObjectId).

Scheme Equality for AnchorKey.

Record AnchorReference := mkAnchorRef {
  ref_id           : LayoutObjectId;
  ref_tree_order   : nat;
  ref_size         : PhysicalSize;
  ref_writing_mode : WritingMode
}.

(** W3C §4.2 <anchor-size> axis keywords *)
Inductive AnchorSizeAxis :=
  | AxisWidth
  | AxisHeight
  | AxisBlock
  | AxisInline
  | AxisSelfBlock
  | AxisSelfInline.

(** Blink's CalculationExpressionNode AST for sizing expressions *)
Inductive CalcExpr :=
  | CalcConst (v : LayoutUnit)
  | CalcAdd (e1 e2 : CalcExpr)
  | CalcMax (e1 e2 : CalcExpr)
  | CalcAnchorSize (target : option AnchorKey)
                   (axis : AnchorSizeAxis)
                   (fallback : option CalcExpr).

(** Context representing Blink's AnchorEvaluatorImpl state *)
Record AnchorEvaluatorEnv := mkEnv {
  self_id           : LayoutObjectId;
  self_tree_order   : nat;
  self_writing_mode : WritingMode;
  default_anchor    : option AnchorKey;
  allow_anchor_size : bool; (** False when evaluating inset properties like 'top' *)
  anchor_query_map  : list (AnchorKey * AnchorReference)
}.

(** ** 3. Evaluation Semantics *)

(** Lookup in LogicalAnchorQuery: returns the reference if it exists and
    strictly precedes the querying element in layout tree order (enforcing acyclicity). *)
Fixpoint lookup_anchor (k : AnchorKey) (self_order : nat)
                       (m : list (AnchorKey * AnchorReference)) : option AnchorReference :=
  match m with
  | [] => None
  | (k', ref) :: rest =>
      if AnchorKey_beq k k' then
        if Nat.ltb (ref_tree_order ref) self_order then Some ref
        else lookup_anchor k self_order rest
      else lookup_anchor k self_order rest
  end.

(** Resolve explicit or default target anchor key *)
Definition resolve_target_key (env : AnchorEvaluatorEnv) (target : option AnchorKey) : option AnchorKey :=
  match target with
  | Some k => Some k
  | None => default_anchor env
  end.

(** Axis projection matching AnchorEvaluatorImpl::EvaluateAnchorSize *)
Definition project_axis (axis : AnchorSizeAxis)
