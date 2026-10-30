### Audit Report: Agent 102 — Blink Block-Level Margin Collapsing vs. CSS 2.1 §8.3.1

**Scope**: Formal audit of Chromium Blink LayoutNG margin collapsing semantics for block-level headers (`<h1>`–`<h6>`) and adjacent block/table formatting contexts (`<table>`) against the W3C CSS 2.1 §8.3.1 specification.

---

### 1. Core Data Structures in Chromium Blink (LayoutNG)

In Blink's LayoutNG architecture ( alongside legacy `LayoutBlockFlow::MarginInfo`), vertical margin collapsing is decoupled from immediate layout geometry computation via an accumulator state pattern passed down and across the box tree.

#### 1.1 `NGMarginStrut` (`MarginStrut`)
Located in `third_party/blink/renderer/core/layout/ng/ng_margin_strut.h`, `MarginStrut` is the foundational algebraic accumulator for adjoining vertical margins before they are resolved into a BFC (Block Formatting Context) block-offset.

* **Fields**:
  * `LayoutUnit positive_margin`: Tracks the running supremum of adjoining non-negative margins ($\ge 0$). Initialized to `0`.
  * `LayoutUnit negative_margin`: Tracks the running infimum (most negative) of adjoining negative margins ($\le 0$). Initialized to `0`.
  * `bool is_quirky_container_start`: Flag governing Quirks Mode margin collapsing overrides at the top of a container (e.g., `<body>` or `<td>`).
* **Core Methods**:
  * `Append(LayoutUnit value, bool is_quirky)`:
    * If `value < 0`: `negative_margin = std::min(negative_margin, value);`
    * If `value > 0`: `positive_margin = std::max(positive_margin, value);`
  * `Sum() const -> LayoutUnit`:
    * Computes the resolved scalar displacement: `return positive_margin + negative_margin;` (using `LayoutUnit` saturating fixed-point arithmetic).

#### 1.2 `BlockLayoutAlgorithm` (`NGBlockLayoutAlgorithm`)
Located in `third_party/blink/renderer/core/layout/ng/ng_block_layout_algorithm.h`, this class orchestrates block-level layout by maintaining an `NGPreviousInflowPosition` struct across sequential inflow children:

```cpp
struct NGPreviousInflowPosition {
  LayoutUnit bfc_block_offset;
  LayoutUnit logical_block_offset;
  NGMarginStrut margin_strut;
  bool self_collapsing_child_had_clearance;
};
```
When laying out a child box (such as an `<h1>` or `<table>`), `BlockLayoutAlgorithm::HandleInflow()` extracts the child's computed `margin-block-start`, appends it to the incoming `margin_strut` from the previous sibling, resolves the BFC offset if the child is not self-collapsing (e.g., has non-zero border, padding, height, or establishes a new BFC), and emits a fresh `margin_strut` seeded with the child's `margin-block-end`.

#### 1.3 `MarginInfo` (Legacy / State Tracking Concept)
In legacy Blink (`LayoutBlockFlow::MarginInfo`) and conceptually mirrored in LayoutNG's `BfcOffset` resolution states, `MarginInfo` tracks boundary conditions:
* `can_collapse_with_children_`: Whether the parent container has top/bottom borders or padding that prevent child margins from escaping the parent box.
* `at_before_side_of_block_`: Tracks if the current margin strut is still adjoining the parent's top edge (determining whether the parent moves down vs. the child moving down relative to the parent).
* `determined_margin_before_quirk_`: Propagates quirky margin collapse suppression across anonymous blocks.

---

### 2. Collapsing Rules: Adjacent Headers and Tables (CSS 2.1 §8.3.1)

Headers (`<h1>` through `<h6>`) are standard block-level elements (`display: block`) participating in their parent's Block Formatting Context. Tables (`<table>`, `display: table`) generate a principal block-level table wrapper box that participates in the same outer BFC while establishing an independent table formatting context inside.

#### 2.1 Adjacent Headers (`h1` bottom collapsing with `h2` top)
1. **Exit `h1`**: `h1` finishes layout. Assuming it has non-zero content height ($H_{h1} > 0$), it is not self-collapsing. It emits an outgoing `MarginStrut` $S_1$ initialized with its bottom margin $m_{\text{bot}}(h_1)$:
   $$S_1.\text{Append}(m_{\text{bot}}(h_1))$$
2. **Enter `h2`**: Before resolving `h2`'s vertical position, `BlockLayoutAlgorithm` takes $S_1$ and appends `h2`'s top margin $m_{\text{top}}(h_2)$:
   $$S_2 = S_1.\text{Append}(m_{\text{top}}(h_2))$$
3. **Resolution**: Since `h2` is an in-flow block with non-zero block size (or non-empty inline formatting context), it collapses the strut via $S_2.\text{Sum}()$, placing `h2`'s border-box top edge at that offset.

#### 2.2 Header Bottom Collapsing with Table Top (`h1` $\to$ `table`)
Per CSS 2.1 §8.3.1 and §17.4:
* The principal table wrapper box is a block-level box. Its top and bottom margins collapse with adjoining margins of adjacent in-flow block-level siblings.
* While a `<table>` establishes a new formatting context internally (so its *own* top margin never collapses with the margins of its internal `<caption>`, `<thead>`, or `<tr>` children), its *external* top margin $m_{\text{top}}(\text{table})$ is completely adjoining with the preceding `h1`'s bottom margin $m_{\text{bot}}(h_1)$.
* Thus, `BlockLayoutAlgorithm::HandleNewFormattingContext()` (or `HandleInflow()` depending on whether floats are present) appends $m_{\text{top}}(\text{table})$ to the incoming `MarginStrut` from `h1` and resolves the strut via `.Sum()` immediately prior to placing the table wrapper box.

#### 2.3 The Exact Algebraic Collapse Formula
For a collection of $k$ adjoining margins $M = \{m_1, m_2, \dots, m_k\}$ accumulated into a `MarginStrut`:
Let $M^+ = \{m \in M \mid m \ge 0\} \cup \{0\}$ and $M^- = \{m \in M \mid m \le 0\} \cup \{0\}$.

The collapsed margin $\mathcal{C}(M)$ is defined by CSS 2.1 §8.3.1 and implemented in `NGMarginStrut::Sum()` as:
$$\mathcal{C}(M) = \max_{m \in M^+} (m) - \max_{m \in M^-} (|m|) = \max(M^+) + \min(M^-)$$

For two adjacent margins $m_1 = m_{\text{bot}}(h_1)$ and $m_2 = m_{\text{top}}(\text{next})$:
$$\mathcal{C}(m_1, m_2) = \max(0, m_1, m_2) + \min(0, m_1, m_2)$$

---

### 3. Mathematical Invariants

Let $\oplus : \mathbb{Z} \times \mathbb{Z} \to \mathbb{Z}$ denote binary margin collapsing, where $m_1 \oplus m_2 = \max(0, m_1, m_2) + \min(0, m_1, m_2)$.
More generally, over the state space of `MarginStrut` $\mathcal{S} = \{(p, n) \in \mathbb{Z} \times \mathbb{Z} \mid p \ge 0 \land n \le 0\}$, let strut combination be $(p_1, n_1) \sqcup (p_2, n_2) = (\max(p_1, p_2), \min(n_1, n_2))$ and evaluation be $\text{eval}(p, n) = p + n$.

1. **Non-Negative Bounding Invariant**:
   For any $m_1, m_2 \ge 0$, $n_1 = n_2 = 0$. Thus $m_1 \oplus m_2 = \max(m_1, m_2)$.
   Since $\min(m_1, m_2) \le \max(m_1, m_2) \le \max(m_1, m_2)$, the collapsed margin satisfies:
   $$\min(m_1, m_2) \le \mathcal{C}(m_1, m_2) \le \max(m_1, m_2)$$
   *(Specifically, it equals the upper bound $\max(m_1, m_2)$).*

2. **Commutativity**:
   $$(p_1, n_1) \sqcup (p_2, n_2) = (\max(p_1, p_2), \min(n_1, n_2)) = (\max(p_2, p_1), \min(n_2, n_1)) = (p_2, n_2) \sqcup (p_1, n_1)$$
   The order in which margins are appended to a `MarginStrut` does not affect the strut state or `.Sum()`.

3. **Associativity (over `MarginStrut` states)**:
   $$((p_1, n_1) \sqcup (p_2, n_2)) \sqcup (p_3, n_3) = (p_1, n_1) \sqcup ((p_2, n_2) \sqcup (p_3, n_3))$$
   *Audit Note*: While $\sqcup$ on `MarginStrut` pairs is strictly associative (enabling self-collapsing intermediate blocks to merge struts associatively), the flattened scalar operation $\oplus$ on $\mathbb{Z}$ is **not** associative when mixing signs (e.g., $(10 \oplus -5) \oplus 8 = 5 \oplus 8 = 8$, whereas $\text{eval}(\text{strut}(10, -5, 8)) = \max(10, 8) + \min(0, -5) = 5$). Blink preserves CSS 2.1 compliance precisely because it delays `.Sum()` evaluation by passing the two-component `MarginStrut` $(p, n)$ across self-collapsing elements rather than folding to a single scalar prematurely.

4. **Idempotence**:
   $$(p, n) \sqcup (p, n) = (\max(p, p), \min(n, n)) = (p, n)$$

---

### 4. Exact Cursor Position Advancement

During block layout of non-self-collapsing elements (such as non-empty headers and tables), the layout cursor (`logical_block_offset` / `cursor_y`) tracks the bottom border-edge of the previously placed box, accompanied by the active `MarginStrut` $S$.

When placing box $i$ with top margin $m_{\text{top}, i}$, block border-box size $B_i > 0$ ($\text{border}_{\text{top}} + \text{padding}_{\text{top}} + \text{content\_height} + \text{padding}_{\text{bot}} + \text{border}_{\text{bot}}$), and bottom margin $m_{\text{bot}, i}$:

1. **Accumulate Top Margin**:
   $$S_{\text{resolved}} = \text{Append}(S_{\text{in}}, m_{\text{top}, i})$$
2. **Compute Collapsed Margin**:
   $$\text{collapsed\_margin} = \text{Sum}(S_{\text{resolved}}) = S_{\text{resolved}}.p + S_{\text{resolved}}.n$$
3. **Box Border-Top Placement (`y_pos`)**:
   $$y_{\text{box}, i} = \text{cursor\_y} + \text{collapsed\_margin}$$
4. **Cursor Advancement (`cursor_y'`)**:
   $$\text{cursor\_y}' = y_{\text{box}, i} + \text{block\_size}_i = \text{cursor\_y} + \text{collapsed\_margin} + B_i$$
5. **Emit New MarginStrut**:
   $$S_{\text{out}} = \text{Append}(\text{EmptyStrut}, m_{\text{bot}, i})$$

---

### 5. Formalization in Rocq / Coq (`BlinkHeaderMarginCollapsingSemantics.v`)

The following complete, self-contained Rocq (Coq) formalization encodes `MarginStrut`, block layout state transitions for headers and tables, and proves all required algebraic and cursor advancement invariants using `ZArith` and `Lia`.

```coq
(** * BlinkHeaderMarginCollapsingSemantics.v
    Formal Audit of Chromium Blink Margin Collapsing (CSS 2.1 §8.3.1)
    Agent 102 Formal Verification Module *)

From Coq Require Import ZArith.
From Coq Require Import Lists.List.
From Coq Require Import Bool.Bool.
From Coq Require Import Micromechanics.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Data Structures: MarginStrut and Box Models *)

(** [MarginStrut] mirrors blink::NGMarginStrut.
    Invariant: [pos_margin >= 0] and [neg_margin <= 0]. *)
Record MarginStrut : Type := mkMarginStrut {
  pos_margin : Z;
  neg_margin : Z
}.

Definition wf_strut (s : MarginStrut) : Prop :=
  s.(pos_margin) >= 0 /\ s.(neg_margin) <= 0.

Definition empty_strut : MarginStrut :=
  mkMarginStrut 0 0.

Lemma empty_strut_wf : wf_strut empty_strut.
Proof.
  unfold wf_strut, empty_strut; simpl; lia.
Qed.

(** [strut_append] mirrors NGMarginStrut::Append(LayoutUnit value) *)
Definition strut_append (s : MarginStrut) (m : Z) : MarginStrut :=
  if m <? 0 then
    mkMarginStrut s.(pos_margin) (Z.min s.(neg_margin) m)
  else
    mkMarginStrut (Z.max s.(pos_margin) m) s.(neg_margin).

(** [strut_merge] merges two MarginStruts across self-collapsing boxes *)
Definition strut_merge (s1 s2 : MarginStrut) : MarginStrut :=
  mkMarginStrut (Z.max s1.(pos_margin) s2.(pos_margin))
                (Z.min s1.(neg_margin) s2.(neg_margin)).

(** [strut_sum] mirrors NGMarginStrut::Sum()
    Computes max(positive margins) - max(|negative margins|)
    which equals pos_margin + neg_margin. *)
Definition strut_sum (s : MarginStrut) : Z :=
  s.(pos_margin) + s.(neg_margin).

(** Binary margin collapse for two adjacent margins m1 and m2 *)
Definition