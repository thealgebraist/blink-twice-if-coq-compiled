### 1. Core Data Structures in Blink Table Sections

In Chromium’s Blink LayoutNG engine (`third_party/blink/renderer/core/layout/table/`), table section layout and ordering are governed by the following structures:

*   **`TableTypes` & Section Roles (`EAtRule` / `EDisplay`)**:
    *   `EDisplay::kTableHeaderGroup` (`<thead>` / `display: table-header-group`)
    *   `EDisplay::kTableRowGroup` (`<tbody>` / `display: table-row-group`)
    *   `EDisplay::kTableFooterGroup` (`<tfoot>` / `display: table-footer-group`)
*   **`NGTableGroupedChildren` (`TableGroupedChildren`)**:
    Constructed during the initialization of `TableLayoutAlgorithm`. It iterates through the direct DOM box children of the `LayoutTable` and partitions them into ordered buckets:
    *   `header`: `BlockNode` (nullable `std::optional<BlockNode>`). Stores the *first* encountered `table-header-group`. Subsequent header groups are demoted to `bodies`.
    *   `bodies`: `HeapVector<BlockNode>`. Stores all `table-row-group` boxes and any excess header/footer groups in exact DOM source order.
    *   `footer`: `BlockNode` (nullable `std::optional<BlockNode>`). Stores the *first* encountered `table-footer-group`. Subsequent footer groups are demoted to `bodies`.
    *   `captions`: `HeapVector<BlockNode>`.
*   **`NGTableSectionLayoutAlgorithm` (`TableSectionLayoutAlgorithm`)**:
    Responsible for laying out an individual section (`<thead>`, `<tbody>`, or `<tfoot>`). It consumes pre-computed column geometries (`NGTableTypes::ColumnLocations`) and row metrics (`NGTableTypes::Row` vector) produced during the table's grid- measurement phase, computing exact physical/logical block offsets for each `<tr>` (`TableRowLayoutAlgorithm`) inside the section.

---

### 2. Section Ordering and Stacking Algorithm (CSS 2.1 §17.5)

Per CSS 2.1 §17.2 and §17.5, regardless of where `<thead>` and `<tfoot>` appear in the DOM tree (e.g., HTML4 legacy pattern `<thead>...<tfoot>...<tbody>`), the visual stacking along the block-progression axis is normalized by `NGTableGroupedChildrenIterator`:

1.  **DOM Partitioning Pass (`TableGroupedChildren::TableGroupedChildren`)**:
    For each child $c_i$ in DOM order $i \in [0, n-1]$:
    *   If $\text{display}(c_i) = \text{kTableHeaderGroup}$:
        If `header` is unset, $\text{header} \leftarrow c_i$; else `bodies.push_back`($c_i$).
    *   If $\text{display}(c_i) = \text{kTableFooterGroup}$:
        If `footer` is unset, $\text{footer} \leftarrow c_i$; else `bodies.push_back`($c_i$).
    *   If $\text{display}(c_i) = \text{kTableRowGroup}$:
        `bodies.push_back`($c_i$).

2.  **Visual Iteration Pass (`NGTableGroupedChildrenIterator`)**:
    When `TableLayoutAlgorithm::Layout()` iterates over sections to compute row baselines, distribute block size, and emit physical fragments, the iterator yields nodes strictly in the sequence:
    $$\mathcal{V} = [\text{header}] \mathbin{+\!+} \text{bodies} \mathbin{+\!+} [\text{footer}]$$
    (omitting empty optional slots).

---

### 3. Cumulative Block Offset Tracking

Let $S_0, S_1, \dots, S_{m-1}$ be the non-empty sections yielded by the visual iterator $\mathcal{V}$, where each section $S_k$ contains $r_k \ge 1$ rows. Let:
*   $B_{\text{start}}$ be the table's initial block border/padding offset (`border_padding.block_start`).
*   $v$ be the vertical border-spacing (`border_spacing.block_size`). Note: in `border-collapse: collapse`, $v = 0$ and borders are shared/halved into the padding box.

#### Section Block Offset Accumulation
For the $k$-th visual section $S_k$:
$$\text{offset}(S_k) = B_{\text{start}} + v + \sum_{j=0}^{k-1} \left( \text{block\_size}(S_j) + v \right)$$

#### Intra-Section Row Block Offset Accumulation
Within `TableSectionLayoutAlgorithm::Layout()`, each section $S_k$ starts its local coordinate system at block offset $0$. For row $i \in [0, r_k - 1]$ inside $S_k$:
$$\text{local\_offset}(R_{k,i}) = \sum_{p=0}^{i-1} \left( \text{block\_size}(R_{k,p}) + v \right)$$
$$\text{block\_size}(S_k) = \left( \sum_{p=0}^{r_k - 1} \text{block\_size}(R_{k,p}) \right) + \max(0, r_k - 1) \cdot v$$
The table-relative block offset of row $R_{k,i}$ is therefore:
$$\text{table\_offset}(R_{k,i}) = \text{offset}(S_k) + \text{local\_offset}(R_{k,i})$$

---

### 4. Mathematical Invariants

1.  **Visual Role Monotonicity**:
    Assigning canonical rank $\text{rank}(\text{Header}) = 0$, $\text{rank}(\text{Body}) = 1$, $\text{rank}(\text{Footer}) = 2$ to the effective role of each section in the visual layout list $\mathcal{V}$, for all visual indices $a < b$:
    $$\text{rank}(\mathcal{V}[a]) \le \text{rank}(\mathcal{V}[b])$$
2.  **Uniqueness of Active Header and Footer**:
    At most one section in $\mathcal{V}$ has effective role $\text{Header}$, and at most one has effective role $\text{Footer}$.
3.  **Order Preservation of Body Sections**:
    The subsequence of sections with effective role $\text{Body}$ in $\mathcal{V}$ is order-isomorphic to the sequence of all DOM sections excluding the first header and first footer.
4.  **Block Offset Monotonicity**:
    Since $\forall S_k, \text{block\_size}(S_k) \ge 0$ and $v \ge 0$, for all $0 \le a < b < m$:
    $$\text{offset}(S_a) \le \text{offset}(S_b)$$
    (Strictly monotonic $\text{offset}(S_a) < \text{offset}(S_b)$ whenever $v > 0$ or $\text{block\_size}(S_a) > 0$).
5.  **Conservation of Total Block Size**:
    For $m \ge 1$ non-empty sections, the total grid block extent $H_{\text{grid}}$ satisfies:
    $$H_{\text{grid}} = B_{\text{start}} + B_{\text{end}} + (m + 1)v + \sum_{k=0}^{m-1} \text{block\_size}(S_k)$$

---

### 5. Rocq / Coq Formalization (`BlinkTableSectionLayoutSemantics.v`)

```coq
(** * BlinkTableSectionLayoutSemantics.v
    Formal verification of Chromium Blink's TableGroupedChildren and
    TableSectionLayoutAlgorithm ordering and block-offset invariants
    against CSS 2.1 Section 17.5. *)

From Coq Require Import Arith Lia List Bool.
Import ListNotations.

(** ** 1. Core Data Structures *)

Inductive SectionRole : Type :=
  | RoleHeader : SectionRole (* display: table-header-group *)
  | RoleBody   : SectionRole (* display: table-row-group *)
  | RoleFooter : SectionRole (* display: table-footer-group *).

Record RawSection : Type := mkRawSection {
  sec_id         : nat;
  sec_dom_role   : SectionRole;
  sec_row_sizes  : list nat; (* Block sizes of rows in this section *)
}.

Record PositionedSection : Type := mkPositionedSection {
  psec_id         : nat;
  psec_eff_role   : SectionRole; (* Effective layout role after demotion *)
  psec_offset     : nat;         (* Block offset relative to table top *)
  psec_block_size : nat;         (* Computed block size of the section *)
}.

(** Visual rank mapping for CSS 2.1 §17.5 ordering verification *)
Definition role_rank (r : SectionRole) : nat :=
  match r with
  | RoleHeader => 0
  | RoleBody   => 1
  | RoleFooter => 2
  end.

(** ** 2. Blink TableGroupedChildren Partitioning Algorithm *)

Record GroupedChildren : Type := mkGroupedChildren {
  gc_header : option RawSection;
  gc_bodies : list RawSection;
  gc_footer : option RawSection;
}.

Definition empty_grouped : GroupedChildren :=
  mkGroupedChildren None [] None.

(** Mirrors Blink's TableGroupedChildren constructor:
    First header goes to gc_header; subsequent headers demote to gc_bodies.
    First footer goes to gc_footer; subsequent footers demote to gc_bodies. *)
Definition insert_section (g : GroupedChildren) (s : RawSection) : GroupedChildren :=
  match sec_dom_role s with
  | RoleHeader =>
      match gc_header g with
      | None   => mkGroupedChildren (Some s) (gc_bodies g) (gc_footer g)
      | Some _ => mkGroupedChildren (gc_header g) (gc_bodies g ++ [s]) (gc_footer g)
      end
  | RoleBody =>
      mkGroupedChildren (gc_header g) (gc_bodies g ++ [s]) (gc_footer g)
  | RoleFooter =>
      match gc_footer g with
      | None   => mkGroupedChildren (gc_header g) (gc_bodies g) (Some s)
      | Some _ => mkGroupedChildren (gc_header g) (gc_bodies g ++ [s]) (gc_footer g)
      end
  end.

Definition group_dom_sections (dom : list RawSection) : GroupedChildren :=
  fold_left insert_section dom empty_grouped.

(** Mirrors NGTableGroupedChildrenIterator: yields Header, then Bodies, then Footer
    annotated with their effective layout role. *)
Definition visual_section_sequence (g : GroupedChildren) : list (RawSection * SectionRole) :=
  let h := match gc_header g with Some s => [(s, RoleHeader)] | None => [] end in
  let b := map (fun s => (s, RoleBody)) (gc_bodies g) in
  let f := match gc_footer g with Some s => [(s, RoleFooter)] | None => [] end in
  h ++ b ++ f.

(** ** 3. Block Size & Cumulative Offset Computation *)

(** Computes the block size of a section given its row sizes and vertical border-spacing [v]. *)
Fixpoint compute_section_block_size (rows : list nat) (v : nat) : nat :=
  match rows with
  | [] => 0
  | [r] => r
  | r :: rest => r + v + compute_section_block_size rest v
  end.

(** Accumulates section offsets along the block axis.
    [curr_offset] starts at (border_padding_block_start + v). *)
Fixpoint layout_sections_loop
  (secs : list (RawSection * SectionRole))
  (curr_offset : nat)
  (v : nat) : list PositionedSection :=
  match secs with
  | [] => []
  | (s, eff_role) :: rest =>
      let bsize := compute_section_block_size (sec_row_sizes s) v in
      let psec := mkPositionedSection (sec_id s) eff_role curr_offset bsize in
      psec :: layout_sections_loop rest (curr_offset + bsize + v) v
  end.

Definition layout_table_sections
  (dom : list RawSection)
  (border_start : nat)
  (v : nat) : list PositionedSection :=
  let grouped := group_dom_sections dom in
  let ordered := visual_section_sequence grouped in
  layout_sections_loop ordered (border_start + v) v.

(** ** 4. Formal Invariants and Proofs *)

(** Invariant 4.1: Visual Role Monotonicity (Header <= Body <= Footer) *)
Inductive RoleMonotonic : list (RawSection * SectionRole) -> Prop :=
  | RM_Nil  : RoleMonotonic []
  | RM_One  : forall x, RoleMonotonic [x]
  | RM_Cons : forall x y l,
      role_rank (snd x) <= role_rank (snd y) ->
      RoleMonotonic (y :: l) ->
      RoleMonotonic (x :: y :: l).

Lemma role_monotonic_app_body_footer :
  forall bodies f_opt,
    RoleMonotonic
      (map (fun s => (s, RoleBody)) bodies ++
       match f_opt with Some s => [(s, RoleFooter)] | None => [] end).
Proof.
  induction bodies as [| b rest IH]; intros f_opt; simpl.
  - destruct f_opt; constructor.
  - destruct rest as [| b2 rest2]; simpl in *.
    + destruct f_opt; simpl; repeat constructor; lia.
    + constructor.
      * simpl; lia.
      * apply IH.
Qed.

Theorem visual_sequence_is_role_monotonic :
  forall (g : GroupedChildren),
    RoleMonotonic (visual_section_sequence g).
Proof.
  intros [h bodies f]. unfold visual_section_sequence. simpl.
  destruct h as [h_sec |]; simpl.
  - Remember (map (fun s => (s, RoleBody)) bodies ++
              match f with Some s => [(s, RoleFooter)] | None => [] end) as tail_list.
    destruct bodies as [| b rest]; simpl in Heqtail_list.
    + destruct f as [f_sec |]; subst tail_list; repeat constructor; simpl; lia.
    + subst tail_list. simpl. constructor.
      * simpl. lia.
      * apply role_monotonic_app_body_footer.
  - apply role_monotonic_app_body_footer.
Qed.

(** Invariant 4.2: Permutation / Count Preservation of Sections *)
Lemma insert_section_count :
  forall g s,
    let g' := insert_section g s in
    (match gc_header g' with Some _ => 1 | None => 0 end +
     length (gc_bodies g') +
     match gc_footer g' with Some