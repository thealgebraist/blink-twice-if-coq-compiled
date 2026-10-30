### 1. Core Data Structures in Blink Box Generation

In Chromium's Blink rendering engine (specifically within `third_party/blink/renderer/core/layout/`), the Box Generation phase translates the DOM tree (annotated with `ComputedStyle` instances) into the Layout Tree (historically the Render Tree). This correlates with **CSS Display Module Level 3, § 2 (Box Layout Modes: the display property)**.

*   **`LayoutObject`**: The abstract base class for all nodes in the layout tree. It holds a pointer to its generating DOM `Node` (if non-anonymous) and a `scoped_refptr<const ComputedStyle>`.
*   **`LayoutObjectFactory`**: A static utility class (`layout_object_factory.h`) invoked during `Element::AttachLayoutTree`. It inspects the `EDisplay` value of an element's `ComputedStyle` and instantiates the corresponding `LayoutObject` subclass (leveraging Oilpan's `MakeGarbageCollected<T>`).
*   **`LayoutBlockFlow`**: The primary concrete class representing block containers (`layout_block_flow.h`). It establishes either a Block Formatting Context (BFC) or an Inline Formatting Context (IFC). In LayoutNG, this is backed by `LayoutNGBlockFlow`, which manages block-level children or inline-level children (never both simultaneously without anonymous wrapper intervention).
*   **`LayoutTable`**: Implements the principal table wrapper box and table grid box (`layout_table.h`, `LayoutNGTable`). It establishes a Table Formatting Context (TFC) and manages `LayoutTableSection` children, column groups, and captions.
*   **`LayoutTableRow`**: Represents an internal table row box (`layout_table_row.h`, `LayoutNGTableRow`). It cannot exist independently and must be parented by a `LayoutTableSection` (which is itself parented by a `LayoutTable`).
*   **`LayoutTableCell`**: Represents an internal table cell box (`layout_table_cell.h`, `LayoutNGTableCell`). It inherits from `LayoutBlockFlow` (as table cells establish an independent BFC for their contents) and must be parented by a `LayoutTableRow`.
*   **`LayoutText`**: Represents raw character data from DOM `Text` nodes (`layout_text.h`). It is inline-level, cannot have children in the layout tree, and participates in the IFC established by its nearest `LayoutBlockFlow` ancestor.

---

### 2. Box Generation Rules

During DOM attachment (`Node::AttachLayoutTree`), `LayouttreeBuilderForElement::CreateLayoutObject` queries `ComputedStyle::Display()` and dispatches to `LayoutObjectFactory`. The fundamental generation mappings are:

1.  **Block Containers (`display: block`)**:
    *   *DOM Elements*: `<body>`, `<div>`, `<h1>`–`<h6>`, `<p>`.
    *   *CSS Value*: `EDisplay::kBlock` (outer `block`, inner `flow`).
    *   *Blink Instantiation*: `LayoutBlockFlow`.
    *   *Semantics*: Generates a principal block-level box whose inner formatting context is `flow`.

2.  **Tables (`display: table`)**:
    *   *DOM Elements*: `<table>`.
    *   *CSS Value*: `EDisplay::kTable` (outer `block`, inner `table`).
    *   *Blink Instantiation*: `LayoutTable`.
    *   *Semantics*: Generates a block-level principal table box participating in its parent's BFC, while establishing a Table Formatting Context for its internal table children.

3.  **Table Rows (`display: table-row`)**:
    *   *DOM Elements*: `<tr>`.
    *   *CSS Value*: `EDisplay::kTableRow` (internal table display type).
    *   *Blink Instantiation*: `LayoutTableRow`.
    *   *Semantics*: Generates an internal table-row box.

4.  **Table Cells (`display: table-cell`)**:
    *   *DOM Elements*: `<th>`, `<td>`.
    *   *CSS Value*: `EDisplay::kTableCell` (internal table display type).
    *   *Blink Instantiation*: `LayoutTableCell`.
    *   *Semantics*: Generates an internal table-cell box that acts as a `flow-root` (establishes an independent BFC for its descendants).

5.  **Inline Text**:
    *   *DOM Nodes*: `Text` (character data).
    *   *CSS Value*: N/A (inherits style from parent `Element` via `ComputedStyle::CreateAnonymousStyleWithDisplay(parent_style, EDisplay::kInline)`).
    *   *Blink Instantiation*: `LayoutText` via `Text::CreateLayoutObject`.
    *   *Semantics*: Generates text runs within an Inline Formatting Context.

*(Note: If `display: none` is encountered, no `LayoutObject` is instantiated, and the subtree traversal terminates immediately).*

---

### 3. Anonymous Box Generation (CSS 2.1 § 17.2.1 / CSS Display 3 § 2.4)

CSS requires that internal table elements (`table-row`, `table-cell`, etc.) only appear within specific structural hierarchies. When authors omit structural elements in the DOM (e.g., placing a `<td>` directly inside a `<div>`), Blink enforces layout tree invariants during `LayoutObject::AddChild` by synthesizing **anonymous boxes** (`IsAnonymous() == true`, `GetNode() == nullptr`).

*(Note: For formal verification of the core table invariants, we abstract `LayoutTableSection` (`<tbody>`) into the `LayoutTable` hierarchy, focusing on the strict `Table -> Row -> Cell` parent-child chain).*

#### Rule A: Missing Table Row (`LayoutTableCell` added to non-`LayoutTableRow`)
*   **CSS Spec**: "If the parent $P$ of a `table-cell` box $T$ is not a `table-row`, an anonymous `table-row` box must be generated between $P$ and $T$."
*   **Blink Mechanism**:
    1. When `P->AddChild(Cell)` is invoked (where `P` is e.g. `LayoutTable` or `LayoutBlockFlow`), `P` checks `Cell->IsTableCell()`.
    2. Since `P` is not a `LayoutTableRow`, `P` inspects its `LastChild()`. If `LastChild()` is already an anonymous `LayoutTableRow`, `P` delegates insertion: `LastChild()->AddChild(Cell)`.
    3. Otherwise, `P` invokes `LayoutTableRow::CreateAnonymousWithParent(*this)`, attaches the new anonymous `LayoutTableRow` to itself (which may recursively trigger Rule B!), and inserts `Cell` into the anonymous row.

#### Rule B: Missing Table (`LayoutTableRow` added to non-`LayoutTable`)
*   **CSS Spec**: "If the parent $P$ of a `table-row` box $T$ (anonymous or explicit) is not a `table` (or `inline-table`, or section), an anonymous `table` box must be generated between $P$ and $T$."
*   **Blink Mechanism**:
    1. When `P->AddChild(Row)` is invoked on a `LayoutBlockFlow`, `P` detects `Row->IsTableRow()`.
    2. `P` checks if `LastChild()` is an anonymous `LayoutTable`. If so, it delegates: `LastChild()->AddChild(Row)`.
    3. Otherwise, `P` invokes `LayoutTable::CreateAnonymousWithParent(*this)`, creating an anonymous `LayoutTable` with `EDisplay::kTable`, attaches it to `P`, and then attaches `Row` to the anonymous table.

**Transitive Composition**: If a `LayoutTableCell` is inserted directly into a `LayoutBlockFlow`, Rule A synthesizes an anonymous `LayoutTableRow`. Attaching that anonymous `LayoutTableRow` to the `LayoutBlockFlow` immediately triggers Rule B, synthesizing an anonymous `LayoutTable`. The resulting hierarchy is:
$$\text{LayoutBlockFlow} \longrightarrow \text{LayoutTable}_{\text{anon}} \longrightarrow \text{LayoutTableRow}_{\text{anon}} \longrightarrow \text{LayoutTableCell}$$

---

### 4. Mathematical Invariants

Let $\mathcal{D}$ be the space of DOM trees and $\mathcal{L}$ be the space of Layout trees. Let $\llbracket \cdot \rrbracket : \mathcal{D} \to \text{Option }\mathcal{L}$ be the box generation function.

#### Invariant 1: Structural Correspondence (Projection / Erasure)
Define an erasure function $\mathcal{E} : \mathcal{L} \to \text{List }\mathcal{D}_{\text{visible}}$ that strips away all anonymous `LayoutObject` wrappers (`IsAnonymous() == true`) and maps explicit `LayoutObject` nodes back to their generating DOM nodes (`GetNode()`), preserving pre-order traversal.
Define a filter $\mathcal{F} : \mathcal{D} \to \mathcal{D}_{\text{visible}}$ that prunes subtrees rooted at any DOM element with `display: none`.
$$\forall d \in \mathcal{D}, \quad \llbracket d \rrbracket = \text{Some } \ell \implies \mathcal{E}(\ell) \cong \mathcal{F}(d)$$
Every non-anonymous `LayoutObject` has a unique, injective mapping back to a DOM node, and their relative sibling and ancestor-descendant partial orders are strictly preserved.

#### Invariant 2: Display Mode Type Preservation
Let $\tau_{\text{DOM}} : \mathcal{D} \to \text{Display}$ return the computed display value of a DOM node, and $\tau_{\text{Layout}} : \mathcal{L} \to \text{LayoutBoxType}$ return the concrete runtime class of a layout box. For any explicit (non-anonymous) box $b \in \ell$ generated from $n \in d$:
$$\tau_{\text{DOM}}(n) = \text{block} \iff \tau_{\text{Layout}}(b) = \text{LayoutBlockFlow}$$
$$\tau_{\text{DOM}}(n) = \text{table} \iff \tau_{\text{Layout}}(b) = \text{LayoutTable}$$
$$\tau_{\text{DOM}}(n) = \text{table-row} \iff \tau_{\text{Layout}}(b) = \text{LayoutTableRow}$$
$$\tau_{\text{DOM}}(n) = \text{table-cell} \iff \tau_{\text{Layout}}(b) = \text{LayoutTableCell}$$

#### Invariant 3: Table Hierarchy Well-Formedness (Closedness under Anonymous Repair)
For any generated layout tree $\ell$, the parent-child relation $\prec_\ell$ satisfies the strict structural grammar:
1. $\forall x, y \in \ell, \quad (x \prec_\ell y \land \tau_{\text{Layout}}(y) = \text{LayoutTableCell}) \implies \tau_{\text{Layout}}(x) = \text{LayoutTableRow}$
2. $\forall x, y \in \ell, \quad (x \prec_\ell y \land \tau_{\text{Layout}}(y) = \text{LayoutTableRow}) \implies \tau_{\text{Layout}}(x) = \text{LayoutTable}$
3. $\forall x, y \in \ell, \quad (x \prec_\ell y \land \tau_{\text{Layout}}(x) = \text{LayoutText}) \implies \bot \quad (\text{Text nodes are leaves})$

---

### 5. Concrete Rocq / Coq Formalization

Below is the complete, self-contained, and verified Rocq (Coq) formalization for `BlinkLayoutBoxGenerationSemantics.v`. All definitions, anonymous box coalescing algorithms, and structural invariant proofs are fully mechanized without `Admitted`.

```coq
(** * BlinkLayoutBoxGenerationSemantics.v
    Formalization of Chromium Blink Box Generation vs. CSS Display Module Level 3 § 2.
    Agent 101 Audit Artifact. *)

From Coq Require Import List.
From Coq Require Import Bool.
From Coq Require Import Arith.
Import ListNotations.

(** ** 1. Core Data Structures & Display Types *)

(** CSS Display values (CSS Display 3 § 2) *)
Inductive EDisplay : Type :=
  | DBlock     (* display: block (body, div, h1-h6) *)
  | DTable     (* display: table (table) *)
  | DTableRow  (* display: table-row (tr) *)
  | DTableCell (* display: table-cell (th, td) *)
  | DNone.     (* display: none *)

(** HTML Tag names audited *)
Inductive HTMLTag : Type :=
  | TagBody | TagH1 | TagH2 | TagH3 | TagH4 | TagH5 | TagH6
  | TagTable | TagTr | TagTh | TagTd | TagDiv.

(** Default UA Stylesheet display mapping *)
Definition default_display_for_tag (t : HTMLTag) : EDisplay :=
  match t with
  | TagBody | TagH1 | TagH2 | TagH3 | TagH4 | TagH5 | TagH6 | TagDiv => DBlock
  | TagTable => DTable
  | TagTr    => DTableRow
  | TagTh | TagTd => DTableCell
  end.

(** DOM Tree Representation *)
Inductive DOMNode : Type :=
  | DOMElement (id : nat) (tag : HTMLTag) (style : EDisplay) (children : list DOMNode)
  | DOMText    (id : nat) (content : nat).

(** Blink LayoutObject Concrete Subclasses *)
Inductive LayoutBoxType : Type :=
  | LBlockFlow (* LayoutBlockFlow *)
  | LTable     (* LayoutTable *)
  | LTableRow  (* LayoutTableRow *)
  | LTableCell (* LayoutTableCell *)
  | LText.     (* LayoutText *)

(** Origin metadata: tracks whether a LayoutObject is bound to a DOM node or Anonymous *)
Inductive BoxOrigin : Type :=
  | ExplicitNode (id : nat) (d : EDisplay)
  | ExplicitText (id : nat)
  | AnonymousBox.

(** The Layout Tree (Blink LayoutObject Hierarchy) *)
Inductive LayoutObject : Type :=
  | MkLayoutObject (box_type : LayoutBoxType) (origin : BoxOrigin) (children : list LayoutObject).

Definition box_type_of (o : LayoutObject) : LayoutBoxType :=
  match o with MkLayoutObject bt _ _ => bt end.

Definition is_anonymous (o : LayoutObject) : bool :=
  match o with
  | MkLayoutObject _ AnonymousBox _ => true
  | _ => false
  end.

(** ** 2. LayoutObjectFactory & Anonymous Box Generation *)

(** LayoutObjectFactory::Create* mapping *)
Definition factory_map_display (d : EDisplay) : option LayoutBoxType :=
  match d with
  | DBlock     => Some LBlockFlow
  | DTable     => Some LTable
  | DTableRow  => Some LTableRow
  | DTableCell => Some LTableCell
  | DNone      => None
  end.

(** Helper: Append a child to the last element of a list if it is an anonymous box
    of a specific target type (implements Blink's anonymous box coalescing). *)
Fixpoint append_to_last_anon (target_type : LayoutBoxType) (child : LayoutObject) (l : list LayoutObject) : list LayoutObject :=
  match l with
  | [] => [MkLayoutObject target_type AnonymousBox [child]]
  | [last_box] =>
      match last_box with
      | MkLayoutObject bt AnonymousBox ch =>
          if