### 1. Core Data Structures in Blink HTML Parser (`third_party/blink/renderer/core/html/parser/`)

#### `HTMLStackItem` (`html_stack_item.h`)
An Oilpan-managed (`GarbageCollected<HTMLStackItem>`) wrapper representing an element on the stack of open elements or active formatting elements. It caches parsing-critical properties to avoid repeatedly querying the DOM node across the Oilpan heap boundary.

```cpp
class HTMLStackItem : public GarbageCollected<HTMLStackItem> {
  Member<ContainerNode> node_;
  AtomicString token_local_name_;
  AtomicString namespace_uri_;
  Vector<Attribute> token_attributes_;
  HTMLTag tag_; // Fast enum dispatch for HTML tags
};
```
* **Role in §13.2.6**: Represents entries in the "stack of open elements" (§13.2.4.2). Caches the token's original attributes and namespace so that operations like * adoption agency algorithm* and *foster parenting* can inspect element identity in $O(1)$ time without dereferencing the underlying `Element`'s attribute collection.

#### `HTMLElementStack` (`html_element_stack.h`)
Manages the parser's stack of open elements. Implemented as a singly-linked list of `ElementRecord` nodes (from top/current node to bottom/root `html` node) to optimize push/pop and mid-stack removals required by the Adoption Agency Algorithm.

```cpp
class HTMLElementStack {
 public:
  class ElementRecord : public GarbageCollected<ElementRecord> {
    Member<HTMLStackItem> item_;
    Member<ElementRecord> next_;
  };
 private:
  Member<ElementRecord> top_;
  Member<ContainerNode> root_node_;     // Cached <html>
  Member<Element> head_element_;        // Cached <head>
  Member<Element> body_element_;        // Cached <body>
  unsigned stack_depth_;
};
```
* **Scope Markers**: Implements the specification's "has an element in [specific] scope" algorithms (`InScope`, `InListItemScope`, `InTableScope`, `InButtonScope`, `InSelectScope`) by traversing `ElementRecord::next_` until the target tag or a scope-marker boundary (e.g., `applet`, `caption`, `html`, `table`, `td`, `th`, `marquee`, `object`, `template`, SVG `foreignObject`/`desc`/`title`, MathML `mi`/`mo`/`mn`/`ms`/`mtext`/`annotation-xml`) is encountered.

#### `HTMLConstructionSite` (`html_construction_site.h`)
Encapsulates the mutation state machine that translates tree builder transitions (`HTMLTreeBuilder`) into concrete DOM mutations. To prevent synchronous re-entrant script execution (e.g., custom element reactions or mutation events) during critical parser transitions, it queues mutations into a `TaskQueue`.

```cpp
struct HTMLConstructionSiteTask {
  enum Operation {
    kInsert,
    kInsertText,
    kInsertAlreadyParsedChild,
    kReparent,
    kTakeAllChildren
  };
  Operation operation;
  Member<ContainerNode> parent;
  Member<Node> next_child; // Non-null if foster parenting
  Member<Node> child;
  unsigned self_closing : 1;
};

class HTMLConstructionSite {
  Member<Document> document_;
  Member<ContainerNode> attachment_root_;
  HTMLElementStack open_elements_;
  HTMLFormattingElementList active_formatting_elements_;
  HeapVector<HTMLConstructionSiteTask, 1> task_queue_;
  HTMLContentPolicy policy_;
  bool redirect_attach_to_foster_parent_;
};
```
* **Foster Parenting (§13.2.6.1)**: When `redirect_attach_to_foster_parent_` is active (e.g., parsing character tokens or non-table elements inside `InTableMode`), `FindFosterSite(HTMLConstructionSiteTask&)` locates the innermost `table` on `open_elements_`, resolves its parent as `task.parent`, and sets the `table` itself as `task.next_child`, ensuring insertion occurs immediately *before* the table in the DOM tree.
* **Text Coalescing**: Adjacent character tokens are merged in `pending_text_` before flushing an `kInsertText` task, ensuring maximal contiguous `Text` nodes as mandated by §13.2.6.1 ("insert a character").

#### `ContainerNode` (`third_party/blink/renderer/core/dom/container_node.h`)
The base DOM class for any `Node` capable of holding children (`Document`, `DocumentFragment`, `Element`). Uses an intrusive doubly-linked list over `Node` pointers.

```cpp
class CORE_EXPORT ContainerNode : public Node {
  Member<Node> first_child_;
  Member<Node> last_child_;
};
// Inside Node (node.h):
class CORE_EXPORT Node : public EventTarget {
  Member<ContainerNode> parent_or_shadow_host_node_;
  Member<Node> previous_;
  Member<Node> next_;
};
```
* **Execution**: `ExecuteTask()` on `HTMLConstructionSite` invokes `ContainerNode::ParserAppendChild()` or `ContainerNode::ParserInsertBefore()`, which directly mutates `first_child_`, `last_child_`, `previous_`, `next_`, and `parent_or_shadow_host_node_` while bypassing DOM spec pre-insertion validation overhead already guaranteed by the HTML parser's state machine.

---

### 2. Formal AST Representation for the Core HTML Subset

We define an algebraic Abstract Syntax Tree (AST) over the target subset: `Document`, `html`, `head`, `body`, headers (`h1`–`h6`), tables (`table`, `thead`, `tbody`, `tfoot`, `tr`, `th`, `td`), and `Text` nodes.

$$\begin{aligned}
\text{Level} &\quad \ell ::= 1 \mid 2 \mid 3 \mid 4 \mid 5 \mid 6 \\
\text{SectionTag} &\quad \sigma ::= \mathsf{THead} \mid \mathsf{TBody} \mid \mathsf{TFoot} \\
\text{CellTag} &\quad \gamma ::= \mathsf{TH} \mid \mathsf{TD} \\
\text{Tag} &\quad \tau ::= \mathsf{HTML} \mid \mathsf{Head} \mid \mathsf{Body} \mid \mathsf{H}(\ell) \mid \mathsf{Table} \mid \mathsf{Section}(\sigma) \mid \mathsf{TR} \mid \mathsf{Cell}(\gamma) \\
\text{Node} &\quad n ::= \mathsf{Element}(\tau, [n]) \mid \mathsf{Text}(s) \qquad (s \in \Sigma^+) \\
\text{Document} &\quad d ::= \mathsf{Doc}([n])
\end{aligned}$$

#### Concrete AST Instance Mapping
For a standard compliant document containing a header and a table:
```html
<!DOCTYPE html>
<html>
  <head></head>
  <body>
    <h1>Title</h1>
    <table>
      <tbody>
        <tr><th>Col</th><td>Val</td></tr>
      </tbody>
    </table>
  </body>
</html>
```
The Blink `HTMLTreeBuilder` transitions through `kInitialMode` $\to$ `kBeforeHtmlMode` $\to$ `kBeforeHeadMode` $\to$ `kInHeadMode` $\to$ `kAfterHeadMode` $\to$ `kInBodyMode` $\to$ `kInTableMode` $\to$ `kInTableBodyMode` $\to$ `kInRowMode` $\to$ `kInCellMode`, yielding the exact AST term:

$$\begin{aligned}
\mathsf{Doc}\big([ \mathsf{Element}(\mathsf{HTML}, [ &\mathsf{Element}(\mathsf{Head}, []), \\
&\mathsf{Element}(\mathsf{Body}, [ \\
&\quad \mathsf{Element}(\mathsf{H}(1), [\mathsf{Text}(\text{"Title"})]), \\
&\quad \mathsf{Element}(\mathsf{Table}, [ \\
&\quad\quad \mathsf{Element}(\mathsf{Section}(\mathsf{TBody}), [ \\
&\quad\quad\quad \mathsf{Element}(\mathsf{TR}, [ \\
&\quad\quad\quad\quad \mathsf{Element}(\mathsf{Cell}(\mathsf{TH}), [\mathsf{Text}(\text{"Col"})]), \\
&\quad\quad\quad\quad \mathsf{Element}(\mathsf{Cell}(\mathsf{TD}), [\mathsf{Text}(\text{"Val"})]) \\
&\quad\quad\quad ]) \\
&\quad\quad ]) \\
&\quad ]) \\
&]) ]) ]\big)
\end{aligned}$$

*Note on Implicit `tbody` Generation*: Per §13.2.6.4.9 ("in table" insertion mode), encountering a `<tr>` token directly inside `<table>` triggers the `ClearStackBackToTableContext` routine, synthesizes an implicit `<tbody>` start token, pushes it onto `HTMLElementStack`, switches to `kInTableBodyMode`, and reprocesses the `<tr>` token. Thus, well-formed parser outputs canonicalize direct `<tr>` children of `<table>` into `<tbody>` sections (unless foster-parented or script-mutated).

---

### 3. Node Hierarchy Validation & §13.2.6 Enforcement Mechanics

The HTML Living Standard §13.2.6 enforces hierarchy constraints dynamically via `HTMLElementStack` scope checks and insertion mode transitions:

| Parent Context | Permitted Children in Target Subset | Blink Enforcement Mechanism (§13.2.6) |
| :--- | :--- | :--- |
| `Document` | Exactly one `Element(HTML, ...)` | `kBeforeHtmlMode` creates `<html>` if missing and transitions to `kBeforeHeadMode`. Subsequent `<html>` tokens merge attributes onto `open_elements_.RootNode()`. |
| `HTML` | `[Element(Head, ...); Element(Body, ...)]` | `kBeforeHeadMode` inserts `<head>`; `kAfterHeadMode` inserts `<body>` on any non-head token and switches to `kInBodyMode`. |
| `H(1..6)` | `Text(s)` only (no nested `H(1..6)` or `Table`) | In `kInBodyMode` (`ProcessStartTagForInBody`), if a start tag `h1`–`h6` is seen while `open_elements_.Top()` is `h1`–`h6`, the parser logs a parse error and calls `open_elements_.Pop()` before inserting the new heading. Encountering `<table>` when in scope of an open element does not pop `h1`–`h6` automatically unless restricted to valid content models; in our strict validated subset, `H(l)` is restricted strictly to inline `Text`. |
| `Table` | `Element(Section(_), ...)` or `Element(TR, ...)` | In `kInTableMode`, `<thead>`, `<tbody>`, `<tfoot>` push to stack and switch to `kInTableBodyMode`. `<tr>` synthesizes `<tbody>`. Any misplaced `Text` or `H(l)` triggers `FosterParent()` (`redirect_attach_to_foster_parent_ = true`), ejecting the node above the `<table>` into `Body` or `Cell`. |
| `Section(_)` | `Element(TR, ...)` | In `kInTableBodyMode`, `<tr>` pushes to stack and switches to `kInRowMode`. `<th>`/`<td>` synthesizes an implicit `<tr>`. Non-table tokens delegate to `kInTableMode` and get foster-parented out. |
| `TR` | `Element(Cell(TH\|TD), ...)` | In `kInRowMode`, `<th>`/`<td>` pushes to stack, switches to `kInCellMode`, and inserts a scope marker into `active_formatting_elements_`. A new `<tr>` or section tag pops the current `<tr>` via `ClearStackBackToTableRowContext()`. |
| `Cell(TH\|TD)` | Flow content: `Text(s)`, `H(1..6)`, nested `Table` | `kInCellMode` delegates standard tokens to `kInBodyMode`. Because `th` and `td` are in `kTableScopeMarker`, a nested `<table>` inside a cell establishes a fresh table scope without closing the outer cell, whereas a `<th>`, `<td>`, `<tr>`, or `<tbody>` token closes the current cell (`CloseTheCell()`) when in table scope. |

---

### 4. Mathematical Invariants

#### Invariant 1: Structural Inductive Well-Formedness ($\mathsf{WF}_{\text{Doc}}$)
A document tree $d = \mathsf{Doc}(ns)$ satisfies $\mathsf{WF}_{\text{Doc}}(d)$ iff it is derived by the following mutually inductive judgment system:

$$\frac{\mathsf{WF}_{\text{Head}}(h) \quad \mathsf{WF}_{\text{Body}}(b)}{\mathsf{WF}_{\text{Doc}}(\mathsf{Doc}([\mathsf{Element}(\mathsf{HTML}, [h, b])]))} \quad (\text{WF-Doc})$$

$$\frac{}{\mathsf{WF}_{\text{Head}}(\mathsf{Element}(\mathsf{Head}, []))} \quad (\text{WF-Head}) \qquad \frac{\forall n \in ns,\ \mathsf{WF}_{\text{Flow}}(n)}{\mathsf{WF}_{\text{Body}}(\mathsf{Element}(\mathsf{Body}, ns))} \quad (\text{WF-Body})$$

$$\frac{s \neq \epsilon}{\mathsf{WF}_{\text{Inline}}(\mathsf{Text}(s))} \quad (\text{WF-Text}) \qquad \frac{\ell \in \{1..6\} \quad \forall n \in ns,\ \mathsf{WF}_{\text{Inline}}(n)}{\mathsf{WF}_{\text{Flow}}(\mathsf{Element}(\mathsf{H}(\ell), ns))} \quad (\text{WF-Header})$$

$$\frac{\mathsf{WF}_{\text{Inline}}(n)}{\mathsf{WF}_{\text{Flow}}(n)} \quad (\text{WF-Flow-Inline}) \qquad \frac{\forall n \in ns,\ \mathsf{WF}_{\text{TableChild}}(n)}{\mathsf{WF}_{\text{Flow}}(\mathsf{Element}(\mathsf{Table}, ns))} \quad (\text{WF-Table})$$

$$\frac{\sigma \in \{\mathsf{THead}, \mathsf{TBody}, \mathsf{TFoot}\} \quad \forall r \in rs,\ \mathsf{WF}_{\text{Row}}(r)}{\mathsf{WF}_{\text{TableChild}}(\mathsf{Element}(\mathsf{Section}(\sigma), rs))} \quad (\text{WF-Section}) \qquad \frac{\mathsf{WF}_{\text{Row}}(r)}{\mathsf{WF}_{\text{TableChild}}(r)} \quad (\text{WF-Table-Row})$$

$$\frac{\forall c \in cs,\ \mathsf{WF}_{\text{Cell}}(c)}{\mathsf{WF}_{\text{Row}}(\mathsf{Element}(\mathsf{TR}, cs))} \quad (\text{WF-Row}) \qquad \frac{\gamma \in \{\mathsf{TH}, \mathsf{TD}\} \quad \forall n \in ns,\ \mathsf{WF}_{\text{Flow}}(n)}{\mathsf{WF}_{\text{Cell}}(\mathsf{Element}(\mathsf{Cell}(\gamma), ns))} \quad (\text{WF-Cell})$$

#### Invariant 2: Tree Acyclicity and Unique Parentage
In Blink's pointer-based DOM (`ContainerNode`), let $\mathcal{N}$ be the finite set of allocated `Node` objects. Define the child relation $u \prec v$ iff $v$ is reachable from $u.\mathtt{first\_child\_}$