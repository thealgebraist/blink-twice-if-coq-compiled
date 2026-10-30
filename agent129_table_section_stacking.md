### 1. Section Visual Ordering & DOM Normalization
Per HTML Living Standard §4.9.5 (`tbody`), §4.9.6 (`thead`), §4.9.7 (`tfoot`), and CSS 2.1 §17.5 (Visual layout of table contents), a table's internal section boxes are laid out in a canonical visual order regardless of their lexical order in the DOM tree:
1. **Header (`<thead>`)**: If present, the first `thead` element is formatted at the top of the table grid (below top captions).
2. **Bodies (`<tbody>`)**: All `tbody` sections (including implicit bodies generated via anonymous wrapper boxes around bare `tr` elements) are formatted sequentially in their relative DOM tree order.
3. **Footer (`<tfoot>`)**: If present, the first `tfoot` element is formatted at the bottom of the table grid (above bottom captions), even if it precedes `tbody` elements in the DOM.

In Chromium Blink (`third_party/blink/renderer/core/layout/table/table_layout_algorithm.cc` and `NGTableChildIterator` / `TableChildIterator`), children of `LayoutTable` are iterated by categorizing sections into `kThead`, `kTbody`, and `kTfoot` buckets, yielding a normalized layout sequence $S = [s_0, s_1, \dots, s_{n-1}]$ where all `kThead` precede `kTbody`, which precede `kTfoot`. Empty sections (containing 0 rows or 0 height in some collapsed configurations) are handled according to Blink's non-empty section filtering during layout offset emission.

---

### 2. Section Vertical Stacking Offset Calculation
Let $S = [s_0, s_1, \dots, s_{n-1}]$ be the ordered sequence of non-empty table sections produced by the section iterator, where each section $s_k$ has a computed layout block-size (height) $H_k \ge 0$. Let:
* $B_{\text{top}} \ge 0$ be the table's top border + top padding (or collapsed border edge).
* $B_{\text{bottom}} \ge 0$ be the table's bottom border + bottom padding.
* $v \ge 0$ be the vertical component of `border-spacing` ($v = 0$ when `border-collapse: collapse`).

The vertical offset $Y_k$ (block-start offset relative to the table grid box) for section $s_k$ ($0 \le k < n$) is defined inductively:
$$Y_0 = B_{\text{top}} + v$$
$$Y_{k+1} = Y_k + H_k + v \quad \text{for } 0 \le k < n - 1$$

In explicit closed form:
$$Y_k = B_{\text{top}} + (k + 1)v + \sum_{i=0}^{k-1} H_i$$

The total intrinsic block-size of the table grid box $H_{\text{table}}$ (excluding external captions) for $n > 0$ sections is:
$$H_{\text{table}} = Y_{n-1} + H_{n-1} + v + B_{\text{bottom}} = B_{\text{top}} + B_{\text{bottom}} + (n + 1)v + \sum_{i=0}^{n-1} H_i$$
(For $n = 0$, $H_{\text{table}} = B_{\text{top}} + B_{\text{bottom}}$).

---

### 3. Core Invariants
1. **Section Visual Order Preservation**: For any input DOM list of table sections, after Blink section normalization, every `Thead` precedes every `Tbody`, every `Tbody` precedes every `Tfoot`, and the relative order among sections of the same kind is strictly preserved (stable partition).
2. **Section Vertical Disjointness (Monotonicity & Non-Overlapping)**: For any two section indices $i < j$, the vertical interval $[Y_i, Y_i + H_i]$ precedes $[Y_j, Y_j + H_j]$ with a separation of at least $(j - i)v \ge 0$:
   $$Y_i + H_i \le Y_j$$
   When $v > 0$, the intervals $[Y_i, Y_i + H_i]$ and $[Y_j, Y_j + H_j]$ are strictly disjoint ($Y_i + H_i < Y_j$).
3. **Total Table Height Decomposition**: The final table grid block-size equals the sum of border/padding edges, all section heights $\sum H_k$, and $(n + 1)$ vertical border-spacing intervals.

---

### 4. Formal Verification in Rocq/Coq (`BlinkTableSectionStackingSemantics.v`)

```coq
(** * BlinkTableSectionStackingSemantics.v
    Formal audit of Chromium Blink Table Section Stacking
    against HTML §4.9.5-4.9.7 and CSS 2.1 §17.5. *)

From Coq Require Import List Arith Lia Bool.
Import ListNotations.

(** ** 1. Section Kinds and DOM Normalization *)

Inductive SectionKind : Type :=
  | KThead
  | KTbody
  | KTfoot.

Record TableSection : Type := mkSection {
  sec_id     : nat;
  sec_kind   : SectionKind;
  sec_height : nat
}.

Definition is_thead (s : TableSection) : bool :=
  match sec_kind s with KThead => true | _ => false end.

Definition is_tbody (s : TableSection) : bool :=
  match sec_kind s with KTbody => true | _ => false end.

Definition is_tfoot (s : TableSection) : bool :=
  match sec_kind s with KTfoot => true | _ => false end.

(** Blink's TableChildIterator orders all thead sections, then tbody, then tfoot,
    preserving relative DOM order within each category. *)
Definition normalize_sections (dom_sections : list TableSection) : list TableSection :=
  filter is_thead dom_sections ++
  filter is_tbody dom_sections ++
  filter is_tfoot dom_sections.

(** Kind rank: Thead (0) <= Tbody (1) <= Tfoot (2) *)
Definition kind_rank (k : SectionKind) : nat :=
  match k with
  | KThead => 0
  | KTbody => 1
  | KTfoot => 2
  end.

Inductive SortedByRank : list TableSection -> Prop :=
  | SBR_nil  : SortedByRank []
  | SBR_cons : forall x l,
      Forall (fun y => kind_rank (sec_kind x) <= kind_rank (sec_kind y)) l ->
      SortedByRank l ->
      SortedByRank (x :: l).

Lemma filter_kind_rank_eq : forall f r l,
  (forall s, f s = true -> kind_rank (sec_kind s) = r) ->
  Forall (fun s => kind_rank (sec_kind s) = r) (filter f l).
Proof.
  intros f r l H. induction l as [|x xs IH]; simpl; auto.
  destruct (f x) eqn:E; auto.
  constructor; [apply H; exact E | exact IH].
Qed.

Lemma sorted_by_rank_app : forall l1 l2 r,
  SortedByRank l1 ->
  SortedByRank l2 ->
  Forall (fun x => kind_rank (sec_kind x) <= r) l1 ->
  Forall (fun y => r <= kind_rank (sec_kind y)) l2 ->
  SortedByRank (l1 ++ l2).
Proof.
  intros l1 l2 r HS1 HS2 HF1 HF2.
  induction HS1 as [|x l1' Hx HS1' IH]; simpl; auto.
  inversion HF1 as [|? ? Hxr HF1']; subst.
  constructor.
  - apply Forall_app; split; [exact Hx |].
    eapply Forall_impl; [| exact HF2].
    intros y Hy. lia.
  - apply IH; exact HF1'.
Qed.

Lemma filter_const_sorted : forall f r l,
  (forall s, f s = true -> kind_rank (sec_kind s) = r) ->
  SortedByRank (filter f l).
Proof.
  intros f r l H.
  assert (HF : Forall (fun s => kind_rank (sec_kind s) = r) (filter f l))
    by (apply filter_kind_rank_eq; exact H).
  induction (filter f l) as [|x xs IH]; constructor.
  - inversion HF as [|? ? Hx Hxs]; subst.
    eapply Forall_impl; [| exact Hxs].
    intros y Hy. lia.
  - inversion HF; subst; apply IH; auto.
Qed.

(** *** Theorem 1: Section Visual Order Invariant *)
Theorem normalize_sections_sorted : forall dom_sections,
  SortedByRank (normalize_sections dom_sections).
Proof.
  intros dom_sections. unfold normalize_sections.
  assert (H0 : forall s, is_thead s = true -> kind_rank (sec_kind s) = 0).
  { intros s Hs. destruct (sec_kind s); simpl in *; discriminate || reflexivity. }
  assert (H1 : forall s, is_tbody s = true -> kind_rank (sec_kind s) = 1).
  { intros s Hs. destruct (sec_kind s); simpl in *; discriminate || reflexivity. }
  assert (H2 : forall s, is_tfoot s = true -> kind_rank (sec_kind s) = 2).
  { intros s Hs. destruct (sec_kind s); simpl in *; discriminate || reflexivity. }
  apply sorted_by_rank_app with (r := 0).
  - apply filter_const_sorted with (r := 0); exact H0.
  - apply sorted_by_rank_app with (r := 1).
    + apply filter_const_sorted with (r := 1); exact H1.
    + apply filter_const_sorted with (r := 2); exact H2.
    + eapply Forall_impl; [| apply filter_kind_rank_eq with (r := 1); exact H1].
      simpl; lia.
    + eapply Forall_impl; [| apply filter_kind_rank_eq with (r := 2); exact H2].
      simpl; lia.
  - eapply Forall_impl; [| apply filter_kind_rank_eq with (r := 0); exact H0].
    simpl; lia.
  - apply Forall_app; split.
    + eapply Forall_impl; [| apply filter_kind_rank_eq with (r := 1); exact H1].
      simpl; lia.
    + eapply Forall_impl; [| apply filter_kind_rank_eq with (r := 2); exact H2].
      simpl; lia.
Qed.

(** ** 2. Vertical Stacking Offset Calculation *)

Record PositionedSection : Type := mkPosSection {
  psec_section : TableSection;
  psec_y       : nat
}.

(** Given current offset y_curr and vertical border_spacing v,
    stack sections using Y_{k+1} = Y_k + H_k + v *)
Fixpoint stack_sections_aux (secs : list TableSection) (y_curr v : nat)
  : list PositionedSection * nat :=
  match secs with
  | [] => ([], y_curr)
  | s :: rest =>
      let y_next := y_curr + sec_height s + v in
      let (ps, y_final) := stack_sections_aux rest y_next v in
      (mkPosSection s y_curr :: ps, y_final)
  end.

Definition layout_table_sections
  (secs : list TableSection) (border_top border_bottom v : nat)
  : list PositionedSection * nat :=
  match secs with
  | [] => ([], border_top + border_bottom)
  | _  =>
      let y0 := border_top + v in
      let (ps, y_end) := stack_sections_aux secs y0 v in
      (ps, y_end + border_bottom)
  end.

Fixpoint sum_heights (secs : list TableSection) : nat :=
  match secs with
  | [] => 0
  | s :: rest => sec_height s + sum_heights rest
  end.

(** ** 3. Stacking Recurrence, Decomposition, and Disjointness Proofs *)

Lemma stack_sections_aux_spec : forall secs y_curr v,
  snd (stack_sections_aux secs y_curr v) =
  y_curr + sum_heights secs + length secs * v.
Proof.
  induction secs as [|s rest IH]; intros y_curr v; simpl.
  - lia.
  - destruct (stack_sections_aux rest (y_curr + sec_height s + v) v) as [ps y_final] eqn:E.
    simpl.
    pose proof (IH (y_curr + sec_height s + v) v) as Hrec.
    rewrite E in Hrec. simpl in Hrec.
    lia.
Qed.

(** *** Theorem 2: Total Table Height Decomposition *)
Theorem total_table_height_decomposition : forall secs b_top b_bot v,
  secs <> [] ->
  snd (layout_table_sections secs b_top b_bot v) =
  b_top + b_bot + sum_heights secs + (length secs + 1) * v.
Proof.
  intros secs b_top b_bot v Hne.
  unfold layout_table_sections.
  destruct secs as [|s rest]; [contradiction |].
  remember (s :: rest) as non_empty_secs.
  destruct (stack_sections_aux non_empty_secs (b_top + v) v) as [ps y_end] eqn:E.
  simpl.
  pose proof (stack_sections_aux_spec non_empty_secs (b_top + v) v) as Hspec.
  rewrite E in Hspec. simpl in Hspec.
  lia.
Qed.

(** Step recurrence on positioned output list *)
Lemma stack_sections_aux_nth_step : forall secs y_curr v k p1 p2 d,
  let ps := fst (stack_sections_aux secs y_curr v) in
  S k < length ps ->
   p1 = nth k ps d ->
  p2 = nth (S k) ps d ->
  psec_y p2 = psec_y p1 + sec_height (psec_section p1) + v.
Proof.
  induction secs as [|s rest IH]; intros y_curr v k p1 p2 d Hlen Hp1 Hp2.
  - simpl in Hlen. lia.
  - simpl in *.
    destruct (