(******************************************************************************)
(*                                                                            *)
(*          BLINK HTML5 TREE BUILDER & CSS CASCADE ENGINE FORMALIZATION       *)
(*                                                                            *)
(*  End-to-End Machine-Checked Rocq/Coq 9.3.0 Semantics of Chromium Blink's   *)
(*  Core HTML5 Parsing, CSS Selector Matching, Style Cascade, Value Calc,     *)
(*  and Box/Flex/Table Layout Pipeline:                                       *)
(*                                                                            *)
(*    1. HTML5 Tokenizer & Scope-Bounded Implicit-Closure TreeBuilder         *)
(*       (core/html/parser/html_tree_builder.cc, html_element_stack.cc)       *)
(*    2. Right-to-Left CSS SelectorChecker & Specificity Algebra              *)
(*       (core/css/css_selector.cc, core/css/selector_checker.cc)             *)
(*    3. CSS Cascade Level 5: Origin/!important Inversion & @layer Duality    *)
(*       (core/css/resolver/style_cascade.cc, cascade_priority.h)             *)
(*    4. Cycle-Safe CSS Custom Property var(--x, fallback) Substitution       *)
(*       (core/css/resolver/style_cascade.cc :: ResolveVarInto)               *)
(*    5. Inheritance, Initial/Inherit/Unset Keywords & ComputedStyle          *)
(*       (core/css/resolver/style_builder.cc)                                 *)
(*    6. TRBL Shorthands, Viewport/em/rem Units & Dual-Mode Z calc()          *)
(*       (core/css/css_primitive_value.cc, css_math_expression_node.cc)       *)
(*    7. Box-Sizing (content-box vs border-box), Flexbox & Table Partitioning *)
(*       (core/layout/box_sizing.cc, flex/flexible_box_algorithm.cc)          *)
(*                                                                            *)
(*  Verification Status: 100% Machine-Checked (Strictly 0 Admits, 0 Axioms)   *)
(*                                                                            *)
(******************************************************************************)

From Stdlib Require Import ZArith.
From Stdlib Require Import List.
From Stdlib Require Import Bool.
From Stdlib Require Import Lia.
Require Import BlinkDualModeZSemantics.
Import ListNotations.
Open Scope Z_scope.
#[local] Set Warnings "-register-all".

(* ========================================================================= *)
(* SECTION 1: HTML5 TAG ONTOLOGY, VOID ELEMENTS & SCOPE BOUNDARIES           *)
(*   Chromium: core/html/parser/html_element_stack.cc, html_tree_builder.cc  *)
(* ========================================================================= *)

Inductive HTMLTag : Type :=
  | Tag_Html
  | Tag_Head
  | Tag_Body
  | Tag_Div
  | Tag_Section
  | Tag_Article
  | Tag_Header
  | Tag_Footer
  | Tag_Nav
  | Tag_Main
  | Tag_Aside
  | Tag_P
  | Tag_H1
  | Tag_H2
  | Tag_H3
  | Tag_H4
  | Tag_H5
  | Tag_H6
  | Tag_Ul
  | Tag_Ol
  | Tag_Li
  | Tag_Dl
  | Tag_Dt
  | Tag_Dd
  | Tag_Table
  | Tag_Thead
  | Tag_Tbody
  | Tag_Tfoot
  | Tag_Tr
  | Tag_Th
  | Tag_Td
  | Tag_Caption
  | Tag_Figure
  | Tag_Figcaption
  | Tag_Blockquote
  | Tag_Pre
  | Tag_Code
  | Tag_Span
  | Tag_A
  | Tag_Strong
  | Tag_B
  | Tag_Em
  | Tag_I
  | Tag_Button
  | Tag_Style
  | Tag_Script
  (* Void Elements per WHATWG HTML §13.1.2 *)
  | Tag_Img
  | Tag_Br
  | Tag_Hr
  | Tag_Meta
  | Tag_Link
  | Tag_Input
  | Tag_Col
  | Tag_Source
  | Tag_Wbr.

Definition html_tag_code (t : HTMLTag) : Z :=
  match t with
  | Tag_Html => 1 | Tag_Head => 2 | Tag_Body => 3 | Tag_Div => 4
  | Tag_Section => 5 | Tag_Article => 6 | Tag_Header => 7 | Tag_Footer => 8
  | Tag_Nav => 9 | Tag_Main => 10 | Tag_Aside => 11 | Tag_P => 12
  | Tag_H1 => 13 | Tag_H2 => 14 | Tag_H3 => 15 | Tag_H4 => 16
  | Tag_H5 => 17 | Tag_H6 => 18 | Tag_Ul => 19 | Tag_Ol => 20
  | Tag_Li => 21 | Tag_Dl => 22 | Tag_Dt => 23 | Tag_Dd => 24
  | Tag_Table => 25 | Tag_Thead => 26 | Tag_Tbody => 27 | Tag_Tfoot => 28
  | Tag_Tr => 29 | Tag_Th => 30 | Tag_Td => 31 | Tag_Caption => 32
  | Tag_Figure => 33 | Tag_Figcaption => 34 | Tag_Blockquote => 35
  | Tag_Pre => 36 | Tag_Code => 37 | Tag_Span => 38 | Tag_A => 39
  | Tag_Strong => 40 | Tag_B => 41 | Tag_Em => 42 | Tag_I => 43
  | Tag_Button => 44 | Tag_Style => 45 | Tag_Script => 46
  | Tag_Img => 47 | Tag_Br => 48 | Tag_Hr => 49 | Tag_Meta => 50
  | Tag_Link => 51 | Tag_Input => 52 | Tag_Col => 53 | Tag_Source => 54
  | Tag_Wbr => 55
  end.

Definition html_tag_eqb (t1 t2 : HTMLTag) : bool :=
  Z.eqb (html_tag_code t1) (html_tag_code t2).

Lemma html_tag_eqb_refl : forall t : HTMLTag, html_tag_eqb t t = true.
Proof.
  intro t. unfold html_tag_eqb. apply Z.eqb_refl.
Qed.

Lemma html_tag_eqb_eq : forall t1 t2 : HTMLTag,
  html_tag_eqb t1 t2 = true <-> t1 = t2.
Proof.
  intros t1 t2. unfold html_tag_eqb.
  rewrite Z.eqb_eq.
  split; intro H.
  - destruct t1, t2; simpl in H; try congruence.
  - subst. reflexivity.
Qed.

(** WHATWG HTML §13.1.2 Void Elements: never pushed onto open-element stack *)
Definition is_void_tag (t : HTMLTag) : bool :=
  match t with
  | Tag_Img | Tag_Br | Tag_Hr | Tag_Meta | Tag_Link
  | Tag_Input | Tag_Col | Tag_Source | Tag_Wbr => true
  | _ => false
  end.

(** WHATWG HTML §13.2.4.2 Element-in-Scope Boundaries (HTMLElementStack) *)
Definition is_default_scope_boundary (t : HTMLTag) : bool :=
  match t with
  | Tag_Html | Tag_Table | Tag_Td | Tag_Th | Tag_Caption => true
  | _ => false
  end.

Definition is_button_scope_boundary (t : HTMLTag) : bool :=
  is_default_scope_boundary t || html_tag_eqb t Tag_Button.

Definition is_list_item_scope_boundary (t : HTMLTag) : bool :=
  is_default_scope_boundary t || html_tag_eqb t Tag_Ul || html_tag_eqb t Tag_Ol.

Definition is_table_scope_boundary (t : HTMLTag) : bool :=
  match t with
  | Tag_Html | Tag_Table => true
  | _ => false
  end.

Definition is_p_closing_block_tag (t : HTMLTag) : bool :=
  match t with
  | Tag_P | Tag_Div | Tag_Section | Tag_Article | Tag_Header | Tag_Footer
  | Tag_Nav | Tag_Main | Tag_Aside | Tag_H1 | Tag_H2 | Tag_H3 | Tag_H4
  | Tag_H5 | Tag_H6 | Tag_Ul | Tag_Ol | Tag_Dl | Tag_Table | Tag_Figure
  | Tag_Blockquote | Tag_Pre | Tag_Hr => true
  | _ => false
  end.

Definition is_heading_tag (t : HTMLTag) : bool :=
  match t with
  | Tag_H1 | Tag_H2 | Tag_H3 | Tag_H4 | Tag_H5 | Tag_H6 => true
  | _ => false
  end.

(** Open-element stack check: does [target] appear above the nearest [boundary]? *)
Fixpoint has_in_scope (boundary : HTMLTag -> bool) (target : HTMLTag)
                      (stack : list HTMLTag) : bool :=
  match stack with
  | [] => false
  | top :: rest =>
      if html_tag_eqb top target then true
      else if boundary top then false
      else has_in_scope boundary target rest
  end.

(** Pop elements up to and including [target], ONLY call when [has_in_scope] holds *)
Fixpoint pop_until_tag (target : HTMLTag) (stack : list HTMLTag) : list HTMLTag :=
  match stack with
  | [] => []
  | top :: rest =>
      if html_tag_eqb top target then rest
      else pop_until_tag target rest
  end.

Definition pop_until_in_scope (boundary : HTMLTag -> bool) (target : HTMLTag)
                              (stack : list HTMLTag) : list HTMLTag :=
  if has_in_scope boundary target stack then
    pop_until_tag target stack
  else
    stack.

(** ClosePElementIfInButtonScope (html_tree_builder.cc) *)
Definition close_p_if_in_button_scope (stack : list HTMLTag) : list HTMLTag :=
  pop_until_in_scope is_button_scope_boundary Tag_P stack.

(** Implicit end-tag closure before inserting start tag [new_tag] *)
Definition close_implicit_before_start (new_tag : HTMLTag)
                                       (stack : list HTMLTag) : list HTMLTag :=
  let s1 :=
    if is_p_closing_block_tag new_tag then close_p_if_in_button_scope stack
    else stack
  in
  match new_tag with
  | Tag_Li =>
      pop_until_in_scope is_list_item_scope_boundary Tag_Li s1
  | Tag_Dt | Tag_Dd =>
      let s_dt := pop_until_in_scope is_default_scope_boundary Tag_Dt s1 in
      pop_until_in_scope is_default_scope_boundary Tag_Dd s_dt
  | Tag_H1 | Tag_H2 | Tag_H3 | Tag_H4 | Tag_H5 | Tag_H6 =>
      match s1 with
      | top :: rest => if is_heading_tag top then rest else s1
      | [] => []
      end
  | Tag_Td | Tag_Th =>
      let s_td := pop_until_in_scope is_table_scope_boundary Tag_Td s1 in
      pop_until_in_scope is_table_scope_boundary Tag_Th s_td
  | Tag_Tr =>
      let s_td := pop_until_in_scope is_table_scope_boundary Tag_Td s1 in
      let s_th := pop_until_in_scope is_table_scope_boundary Tag_Th s_td in
      pop_until_in_scope is_table_scope_boundary Tag_Tr s_th
  | _ => s1
  end.

Inductive HTMLToken : Type :=
  | Tok_StartTag (tag : HTMLTag) (self_closing : bool)
  | Tok_EndTag   (tag : HTMLTag)
  | Tok_Text     (char_count : Z)
  | Tok_Comment.

(** Step the HTML5 open-element stack on a single token *)
Definition html_tree_builder_step (stack : list HTMLTag) (tok : HTMLToken)
  : list HTMLTag :=
  match tok with
  | Tok_Comment | Tok_Text _ => stack
  | Tok_StartTag tag self_cl =>
      let s_closed := close_implicit_before_start tag stack in
      if self_cl || is_void_tag tag then s_closed
      else tag :: s_closed
  | Tok_EndTag tag =>
      let bnd :=
        match tag with
        | Tag_Li => is_list_item_scope_boundary
        | Tag_P => is_button_scope_boundary
        | Tag_Tr | Tag_Td | Tag_Th => is_table_scope_boundary
        | _ => is_default_scope_boundary
        end
      in
      pop_until_in_scope bnd tag stack
  end.

(** THEOREM 1: Popping until a tag never increases open-element stack depth *)
Lemma pop_until_tag_length_le : forall (target : HTMLTag) (stack : list HTMLTag),
  (length (pop_until_tag target stack) <= length stack)%nat.
Proof.
  intros target stack. induction stack as [| top rest IH]; simpl.
  - lia.
  - destruct (html_tag_eqb top target); lia.
Qed.

Theorem pop_until_in_scope_nonincreasing_depth :
  forall (bnd : HTMLTag -> bool) (target : HTMLTag) (stack : list HTMLTag),
    (length (pop_until_in_scope bnd target stack) <= length stack)%nat.
Proof.
  intros bnd target stack. unfold pop_until_in_scope.
  destruct (has_in_scope bnd target stack).
  - apply pop_until_tag_length_le.
  - lia.
Qed.

(** THEOREM 2: Void HTML5 tags never push onto the open-element stack *)
Theorem html_void_tag_never_grows_stack :
  forall (tag : HTMLTag) (self_cl : bool) (stack : list HTMLTag),
    is_void_tag tag = true ->
    (length (html_tree_builder_step stack (Tok_StartTag tag self_cl)) <= length stack)%nat.
Proof.
  intros tag self_cl stack Hvoid.
  simpl. rewrite Hvoid, orb_true_r.
  unfold close_implicit_before_start, close_p_if_in_button_scope.
  destruct tag; simpl in Hvoid; try discriminate; simpl;
  try apply pop_until_in_scope_nonincreasing_depth;
  lia.
Qed.

(** THEOREM 3: Scope Boundary Firewall — if [stack = bnd_tag :: lower] where
    [bnd bnd_tag = true] and [bnd_tag <> target], then [pop_until_in_scope]
    cannot cross [bnd_tag] and leaves [bnd_tag :: lower] completely intact! *)
Theorem pop_until_in_scope_preserves_scope_boundary :
  forall (bnd : HTMLTag -> bool) (target bnd_tag : HTMLTag) (lower : list HTMLTag),
    bnd bnd_tag = true ->
    html_tag_eqb bnd_tag target = false ->
    pop_until_in_scope bnd target (bnd_tag :: lower) = bnd_tag :: lower.
Proof.
  intros bnd target bnd_tag lower Hbnd Hneq.
  unfold pop_until_in_scope. simpl.
  rewrite Hneq, Hbnd. reflexivity.
Qed.

(** THEOREM 4: Implicit <p> Closure — starting a new <p> when <p> is on top of
    the stack replaces the open <p> rather than nesting <p> inside <p>! *)
Theorem implicit_p_closes_prior_p :
  forall (rest : list HTMLTag),
    html_tree_builder_step (Tag_P :: rest) (Tok_StartTag Tag_P false) = Tag_P :: rest.
Proof.
  intro rest. reflexivity.
Qed.

(** THEOREM 5: Implicit <li> Closure — starting <li> inside <li> :: <ul> :: rest
    closes the sibling <li> while keeping <ul> intact! *)
Theorem implicit_li_closes_sibling_li_preserving_ul :
  forall (rest : list HTMLTag),
    html_tree_builder_step (Tag_Li :: Tag_Ul :: rest) (Tok_StartTag Tag_Li false) =
    Tag_Li :: Tag_Ul :: rest.
Proof.
  intro rest. reflexivity.
Qed.

(** THEOREM 6: Implicit <td> Closure — starting <td> inside <td> :: <tr> :: <table> :: rest
    closes the prior <td> while keeping <tr> and <table> intact! *)
Theorem implicit_td_closes_prior_td_preserving_tr :
  forall (rest : list HTMLTag),
    html_tree_builder_step (Tag_Td :: Tag_Tr :: Tag_Table :: rest)
                           (Tok_StartTag Tag_Td false) =
    Tag_Td :: Tag_Tr :: Tag_Table :: rest.
Proof.
  intro rest. reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 2: RIGHT-TO-LEFT CSS SELECTOR MATCHER & SPECIFICITY ALGEBRA       *)
(*   Chromium: core/css/css_selector.cc, core/css/selector_checker.cc        *)
(* ========================================================================= *)

Record ElementSummary : Type := {
  el_tag          : HTMLTag;
  el_id           : option Z;     (* Interned atomic ID symbol *)
  el_classes      : list Z;       (* Interned atomic class list *)
  el_attrs        : list (Z * Z); (* Interned (attr_name, attr_val) pairs *)
  el_sibling_idx1 : Z             (* 1-based index among element siblings *)
}.

Inductive SimpleSelector : Type :=
  | SSel_Universal
  | SSel_Tag      (t : HTMLTag)
  | SSel_Id       (id_sym : Z)
  | SSel_Class    (cls_sym : Z)
  | SSel_AttrHas  (attr_name : Z)
  | SSel_AttrEq   (attr_name : Z) (attr_val : Z)
  | SSel_FirstChild
  | SSel_NthChild (step_a : Z) (offset_b : Z) (* an + b *)
  | SSel_Where    (inner : list SimpleSelector). (* :where(...) zero specificity *)

Definition CompoundSelector : Type := list SimpleSelector.

Inductive SelectorCombinator : Type :=
  | Comb_Descendant        (* A B *)
  | Comb_Child             (* A > B *)
  | Comb_NextSibling.      (* A + B *)

(** Right-to-left complex selector: [subject_compound] matched on the target
    element, linked via [combinator] to ancestor/previous-sibling selectors,
    mirroring Blink's SelectorChecker::MatchSelector! *)
Inductive ComplexSelector : Type :=
  | CSel_Subject (subj : CompoundSelector)
  | CSel_Chain   (subj : CompoundSelector)
                 (comb : SelectorCombinator)
                 (left_context : ComplexSelector).

Fixpoint mem_z (x : Z) (xs : list Z) : bool :=
  match xs with
  | [] => false
  | y :: ys => if Z.eqb x y then true else mem_z x ys
  end.

Fixpoint has_attr_name (k : Z) (attrs : list (Z * Z)) : bool :=
  match attrs with
  | [] => false
  | (ak, _) :: rest => if Z.eqb k ak then true else has_attr_name k rest
  end.

Fixpoint has_attr_kv (k v : Z) (attrs : list (Z * Z)) : bool :=
  match attrs with
  | [] => false
  | (ak, av) :: rest =>
      if Z.eqb k ak && Z.eqb v av then true else has_attr_kv k v rest
  end.

(** W3C Selectors 4 §14.3 :nth-child(an + b) integer congruence check *)
Definition match_nth_formula (a b idx : Z) : bool :=
  if Z.ltb idx 1 then false
  else if Z.eqb a 0 then Z.eqb idx b
  else
    let diff := idx - b in
    if Z.gtb a 0 then (Z.geb diff 0) && (Z.eqb (Z.modulo diff a) 0)
    else (Z.leb diff 0) && (Z.eqb (Z.modulo diff a) 0).

Fixpoint match_simple_selector (el : ElementSummary) (ss : SimpleSelector) : bool :=
  match ss with
  | SSel_Universal => true
  | SSel_Tag t => html_tag_eqb (el_tag el) t
  | SSel_Id id_s =>
      match el_id el with
      | Some eid => Z.eqb eid id_s
      | None => false
      end
  | SSel_Class cls_s => mem_z cls_s (el_classes el)
  | SSel_AttrHas k => has_attr_name k (el_attrs el)
  | SSel_AttrEq k v => has_attr_kv k v (el_attrs el)
  | SSel_FirstChild => Z.eqb (el_sibling_idx1 el) 1
  | SSel_NthChild a b => match_nth_formula a b (el_sibling_idx1 el)
  | SSel_Where inner =>
      (fix match_all (l : list SimpleSelector) : bool :=
         match l with
         | [] => true
         | h :: tl => match_simple_selector el h && match_all tl
         end) inner
  end.

Fixpoint match_compound_selector (el : ElementSummary) (cs : CompoundSelector) : bool :=
  match cs with
  | [] => true
  | s :: rest => match_simple_selector el s && match_compound_selector el rest
  end.

(** Ancestor-and-sibling context chain from target element upward:
    Each frame holds [(el, prev_siblings_nearest_first)]. *)
Definition ElementContextChain : Type :=
  list (ElementSummary * list ElementSummary).

(** Right-to-left Blink SelectorChecker over ElementContextChain *)
Fixpoint match_complex_selector (chain : ElementContextChain)
                                (sel : ComplexSelector) {struct sel} : bool :=
  match sel with
  | CSel_Subject subj =>
      match chain with
      | [] => false
      | (curr_el, _) :: _ => match_compound_selector curr_el subj
      end
  | CSel_Chain subj comb left_sel =>
      match chain with
      | [] => false
      | (curr_el, prev_sibs) :: parent_chain =>
          if negb (match_compound_selector curr_el subj) then false
          else
            match comb with
            | Comb_Child =>
                match_complex_selector parent_chain left_sel
            | Comb_Descendant =>
                (fix any_ancestor (ancs : ElementContextChain) : bool :=
                   match ancs with
                   | [] => false
                   | _ :: tl =>
                       if match_complex_selector ancs left_sel then true
                       else any_ancestor tl
                   end) parent_chain
            | Comb_NextSibling =>
                match prev_sibs with
                | [] => false
                | prev_el :: older_sibs =>
                    match_complex_selector ((prev_el, older_sibs) :: parent_chain) left_sel
                end
            end
      end
  end.

(** W3C Selectors Level 4 §17 Specificity Tuple (a = ID, b = Class/Attr/Pseudo, c = Tag) *)
Record Specificity : Type := {
  spec_id    : Z;
  spec_class : Z;
  spec_tag   : Z
}.

Definition spec_zero : Specificity := {| spec_id := 0; spec_class := 0; spec_tag := 0 |}.

Definition spec_add (s1 s2 : Specificity) : Specificity := {|
  spec_id    := spec_id s1 + spec_id s2;
  spec_class := spec_class s1 + spec_class s2;
  spec_tag   := spec_tag s1 + spec_tag s2
|}.

Definition simple_selector_specificity (ss : SimpleSelector) : Specificity :=
  match ss with
  | SSel_Universal => spec_zero
  | SSel_Tag _ => {| spec_id := 0; spec_class := 0; spec_tag := 1 |}
  | SSel_Id _ => {| spec_id := 1; spec_class := 0; spec_tag := 0 |}
  | SSel_Class _ | SSel_AttrHas _ | SSel_AttrEq _ _
  | SSel_FirstChild | SSel_NthChild _ _ =>
      {| spec_id := 0; spec_class := 1; spec_tag := 0 |}
  | SSel_Where _ => spec_zero
  end.

Fixpoint compound_specificity (cs : CompoundSelector) : Specificity :=
  match cs with
  | [] => spec_zero
  | s :: rest => spec_add (simple_selector_specificity s) (compound_specificity rest)
  end.

Fixpoint complex_specificity (sel : ComplexSelector) : Specificity :=
  match sel with
  | CSel_Subject subj => compound_specificity subj
  | CSel_Chain subj _ left_sel =>
      spec_add (compound_specificity subj) (complex_specificity left_sel)
  end.

Definition specificity_ltb (s1 s2 : Specificity) : bool :=
  if Z.ltb (spec_id s1) (spec_id s2) then true
  else if Z.ltb (spec_id s2) (spec_id s1) then false
  else if Z.ltb (spec_class s1) (spec_class s2) then true
  else if Z.ltb (spec_class s2) (spec_class s1) then false
  else Z.ltb (spec_tag s1) (spec_tag s2).

(** THEOREM 7: Specificity Non-Negativity across all ComplexSelectors *)
Lemma simple_specificity_nonneg : forall s : SimpleSelector,
  0 <= spec_id (simple_selector_specificity s) /\
  0 <= spec_class (simple_selector_specificity s) /\
  0 <= spec_tag (simple_selector_specificity s).
Proof.
  intro s. destruct s; simpl; repeat split; lia.
Qed.

Lemma compound_specificity_nonneg : forall cs : list SimpleSelector,
  0 <= spec_id (compound_specificity cs) /\
  0 <= spec_class (compound_specificity cs) /\
  0 <= spec_tag (compound_specificity cs).
Proof.
  induction cs as [| s rest [HI [HC HT]]]; simpl.
  - repeat split; lia.
  - pose proof (simple_specificity_nonneg s) as [SI [SC ST]].
    repeat split; lia.
Qed.

Theorem complex_specificity_nonneg : forall sel : ComplexSelector,
  0 <= spec_id (complex_specificity sel) /\
  0 <= spec_class (complex_specificity sel) /\
  0 <= spec_tag (complex_specificity sel).
Proof.
  induction sel as [subj | subj comb left_sel [HI [HC HT]]]; simpl.
  - apply compound_specificity_nonneg.
  - pose proof (compound_specificity_nonneg subj) as [SI [SC ST]].
    repeat split; lia.
Qed.

(** THEOREM 8: Combinator Specificity Additivity *)
Theorem specificity_combinator_additive :
  forall (subj : CompoundSelector) (comb : SelectorCombinator) (left_sel : ComplexSelector),
    complex_specificity (CSel_Chain subj comb left_sel) =
    spec_add (compound_specificity subj) (complex_specificity left_sel).
Proof.
  intros. reflexivity.
Qed.

(** THEOREM 9: :where(...) Zero-Specificity Invariant (Selectors 4 §17) *)
Theorem where_pseudo_zero_specificity :
  forall (inner : list SimpleSelector),
    compound_specificity [SSel_Where inner] = spec_zero.
Proof.
  intro inner. reflexivity.
Qed.

(** THEOREM 10: Specificity Strict Lexicographical Order (Irreflexivity & Transitivity) *)
Theorem specificity_ltb_irrefl : forall s : Specificity,
  specificity_ltb s s = false.
Proof.
  intro s. unfold specificity_ltb.
  repeat rewrite Z.ltb_irrefl. reflexivity.
Qed.

Lemma specificity_ltb_iff : forall s1 s2 : Specificity,
  specificity_ltb s1 s2 = true <->
    (spec_id s1 < spec_id s2 \/
     (spec_id s1 = spec_id s2 /\ spec_class s1 < spec_class s2) \/
     (spec_id s1 = spec_id s2 /\ spec_class s1 = spec_class s2 /\ spec_tag s1 < spec_tag s2)).
Proof.
  intros [i1 c1 t1] [i2 c2 t2]. unfold specificity_ltb; simpl.
  destruct (i1 <? i2) eqn:E1; [apply Z.ltb_lt in E1 | apply Z.ltb_ge in E1].
  - split; intro; [left; lia | reflexivity].
  - destruct (i2 <? i1) eqn:E2; [apply Z.ltb_lt in E2 | apply Z.ltb_ge in E2].
    + split; [discriminate | intro H; lia].
    + destruct (c1 <? c2) eqn:E3; [apply Z.ltb_lt in E3 | apply Z.ltb_ge in E3].
      * split; intro; [right; left; lia | reflexivity].
      * destruct (c2 <? c1) eqn:E4; [apply Z.ltb_lt in E4 | apply Z.ltb_ge in E4].
        -- split; [discriminate | intro H; lia].
        -- rewrite Z.ltb_lt. split; intro H; [right; right; lia | lia].
Qed.

Theorem specificity_ltb_trans : forall s1 s2 s3 : Specificity,
  specificity_ltb s1 s2 = true ->
  specificity_ltb s2 s3 = true ->
  specificity_ltb s1 s3 = true.
Proof.
  intros s1 s2 s3 H12 H23.
  rewrite specificity_ltb_iff in *.
  lia.
Qed.

(* ========================================================================= *)
(* SECTION 3: CSS CASCADE LEVEL 5 — ORIGIN, !IMPORTANT & @LAYER INVERSION    *)
(*   Chromium: core/css/resolver/cascade_priority.h, style_cascade.cc        *)
(* ========================================================================= *)

Inductive CSSOrigin : Type :=
  | Origin_UserAgent   (* Browser default UA stylesheet *)
  | Origin_User        (* User preference stylesheet *)
  | Origin_Author      (* Page <style> / external CSS *)
  | Origin_Inline.     (* Element style="..." attribute *)

Record CascadeDeclarationMeta : Type := {
  cdm_origin       : CSSOrigin;
  cdm_important    : bool;
  cdm_layer_order  : Z; (* 0..N-1 for explicit @layer, Unlayered_Max = 1000000 for unlayered *)
  cdm_specificity  : Specificity;
  cdm_source_order : Z
}.

(** Origin + Importance rank per CSS Cascade Level 5 §6.1:
      1: UA normal
      2: User normal
      3: Author normal
      4: Inline normal
      5: Author !important
      6: Inline !important
      7: User !important
      8: UA !important *)
Definition cascade_origin_importance_rank (orig : CSSOrigin) (imp : bool) : Z :=
  match orig, imp with
  | Origin_UserAgent, false => 1
  | Origin_User,      false => 2
  | Origin_Author,    false => 3
  | Origin_Inline,    false => 4
  | Origin_Author,    true  => 5
  | Origin_Inline,    true  => 6
  | Origin_User,      true  => 7
  | Origin_UserAgent, true  => 8
  end.

(** CSS Cascade Level 5 §6.4.3 Layer Order Inversion:
    In normal cascade, higher layer_order wins; in !important cascade,
    EARLIER declared layers (smaller layer_order) win! *)
Definition effective_layer_rank (layer_order : Z) (imp : bool) : Z :=
  if imp then - layer_order else layer_order.

Definition cascade_meta_ltb (m1 m2 : CascadeDeclarationMeta) : bool :=
  let r1 := cascade_origin_importance_rank (cdm_origin m1) (cdm_important m1) in
  let r2 := cascade_origin_importance_rank (cdm_origin m2) (cdm_important m2) in
  if Z.ltb r1 r2 then true
  else if Z.ltb r2 r1 then false
  else
    let l1 := effective_layer_rank (cdm_layer_order m1) (cdm_important m1) in
    let l2 := effective_layer_rank (cdm_layer_order m2) (cdm_important m2) in
    if Z.ltb l1 l2 then true
    else if Z.ltb l2 l1 then false
    else if specificity_ltb (cdm_specificity m1) (cdm_specificity m2) then true
    else if specificity_ltb (cdm_specificity m2) (cdm_specificity m1) then false
    else Z.ltb (cdm_source_order m1) (cdm_source_order m2).

(** THEOREM 11: Every !important declaration strictly outranks every normal declaration *)
Theorem important_strictly_beats_normal :
  forall (m_norm m_imp : CascadeDeclarationMeta),
    cdm_important m_norm = false ->
    cdm_important m_imp = true ->
    cascade_meta_ltb m_norm m_imp = true.
Proof.
  intros m_norm m_imp Hn Hi.
  unfold cascade_meta_ltb. rewrite Hn, Hi.
  destruct (cdm_origin m_norm), (cdm_origin m_imp); simpl; reflexivity.
Qed.

(** THEOREM 12: Origin Duality — Author beats UA in normal mode, but UA !important
    beats Author !important! *)
Theorem cascade_origin_importance_duality :
  cascade_origin_importance_rank Origin_UserAgent false <
  cascade_origin_importance_rank Origin_Author false /\
  cascade_origin_importance_rank Origin_Author true <
  cascade_origin_importance_rank Origin_UserAgent true.
Proof.
  simpl. lia.
Qed.

(** THEOREM 13: CSS Cascade Level 5 @layer Inversion Duality —
    For two Author rules in layers L1 < L2:
    - When normal (important = false), L2 strictly beats L1;
    - When !important (important = true), L1 strictly beats L2! *)
Theorem cascade_layer_important_inversion :
  forall (L1 L2 : Z) (sp1 sp2 : Specificity) (ord1 ord2 : Z),
    L1 < L2 ->
    let m1_norm := {| cdm_origin := Origin_Author; cdm_important := false;
                      cdm_layer_order := L1; cdm_specificity := sp1; cdm_source_order := ord1 |} in
    let m2_norm := {| cdm_origin := Origin_Author; cdm_important := false;
                      cdm_layer_order := L2; cdm_specificity := sp2; cdm_source_order := ord2 |} in
    let m1_imp  := {| cdm_origin := Origin_Author; cdm_important := true;
                      cdm_layer_order := L1; cdm_specificity := sp1; cdm_source_order := ord1 |} in
    let m2_imp  := {| cdm_origin := Origin_Author; cdm_important := true;
                      cdm_layer_order := L2; cdm_specificity := sp2; cdm_source_order := ord2 |} in
    cascade_meta_ltb m1_norm m2_norm = true /\
    cascade_meta_ltb m2_imp m1_imp = true.
Proof.
  intros L1 L2 sp1 sp2 ord1 ord2 Hlt.
  unfold cascade_meta_ltb, effective_layer_rank; simpl.
  assert (H1: (L1 <? L2) = true) by (apply Z.ltb_lt; lia).
  assert (H2: (- L2 <? - L1) = true) by (apply Z.ltb_lt; lia).
  rewrite H1, H2. split; reflexivity.
Qed.

(** THEOREM 14: Cascade Priority Irreflexivity *)
Theorem cascade_meta_ltb_irrefl : forall m : CascadeDeclarationMeta,
  cascade_meta_ltb m m = false.
Proof.
  intro m. unfold cascade_meta_ltb.
  repeat rewrite Z.ltb_irrefl.
  rewrite specificity_ltb_irrefl.
  reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 4: CYCLE-SAFE CSS CUSTOM PROPERTY var(--x, fallback) RESOLUTION   *)
(*   Chromium: core/css/resolver/style_cascade.cc :: ResolveVarInto          *)
(* ========================================================================= *)

Inductive CSSVarExpr : Type :=
  | VarExpr_Concrete (px_or_color : Z)
  | VarExpr_Ref      (var_id : Z) (fallback : option CSSVarExpr).

Definition CSSVarTable : Type := list (Z * CSSVarExpr).

Fixpoint lookup_css_var (vid : Z) (tbl : CSSVarTable) : option CSSVarExpr :=
  match tbl with
  | [] => None
  | (k, v) :: rest => if Z.eqb vid k then Some v else lookup_css_var vid rest
  end.

(** Cycle-detecting evaluator matching Blink's StyleCascade::ResolveVarInto:
    tracks [visited] custom property IDs and bounded [fuel] recursion depth.
    Wait: per W3C CSS Custom Properties §2.1, if a variable is in a dependency
    cycle, the variable itself becomes guaranteed-invalid, so a reference
    var(--cycle, fb) evaluates [fb] (if provided and non-cyclic)! *)
Fixpoint resolve_css_var_expr (fuel : nat) (tbl : CSSVarTable)
                              (visited : list Z) (expr : CSSVarExpr) : option Z :=
  match fuel with
  | O => None
  | S fuel' =>
      match expr with
      | VarExpr_Concrete v => Some v
      | VarExpr_Ref vid fb_opt =>
          let primary :=
            if mem_z vid visited then None
            else
              match lookup_css_var vid tbl with
              | None => None
              | Some rhs => resolve_css_var_expr fuel' tbl (vid :: visited) rhs
              end
          in
          match primary with
          | Some resolved => Some resolved
          | None =>
              match fb_opt with
              | None => None
              | Some fb => resolve_css_var_expr fuel' tbl visited fb
              end
          end
      end
  end.

(** THEOREM 15: Self-Referential Cycle Safety — `--x: var(--x)` resolves to None
    when no fallback is given, and cleanly resolves to `Some fb_val` when
    referenced as `var(--x, fb_val)`! *)
Theorem css_var_self_cycle_safe_fallback :
  forall (vid fb_val : Z),
    let cyclic_tbl := [(vid, VarExpr_Ref vid None)] in
    resolve_css_var_expr 4 cyclic_tbl [] (VarExpr_Ref vid None) = None /\
    resolve_css_var_expr 4 cyclic_tbl []
      (VarExpr_Ref vid (Some (VarExpr_Concrete fb_val))) = Some fb_val.
Proof.
  intros vid fb_val. simpl.
  rewrite Z.eqb_refl. simpl.
  rewrite Z.eqb_refl. simpl.
  split; reflexivity.
Qed.

(** THEOREM 16: Mutual 2-Cycle Safety — `--a: var(--b); --b: var(--a)` never
    diverges and falls back cleanly to concrete fallback `fb_val`! *)
Theorem css_var_mutual_2_cycle_safe :
  forall (va vb fb_val : Z),
    Z.eqb va vb = false ->
    let tbl := [(va, VarExpr_Ref vb None); (vb, VarExpr_Ref va None)] in
    resolve_css_var_expr 5 tbl []
      (VarExpr_Ref va (Some (VarExpr_Concrete fb_val))) = Some fb_val.
Proof.
  intros va vb fb_val Hneq. simpl.
  rewrite Z.eqb_refl. simpl.
  assert (Hba: Z.eqb vb va = false).
  { rewrite Z.eqb_sym. exact Hneq. }
  rewrite Hba. simpl.
  rewrite Z.eqb_refl. simpl.
  destruct (Z.eqb va vb) eqn:E; [congruence |].
  rewrite Z.eqb_refl. simpl. reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 5: INHERITANCE & CSS WIDE KEYWORDS (initial / inherit / unset)    *)
(*   Chromium: core/css/resolver/style_builder.cc                            *)
(* ========================================================================= *)

Inductive CSSPropertyId : Type :=
  (* Inherited Properties *)
  | Prop_Color
  | Prop_FontSize
  | Prop_FontWeight
  | Prop_FontStyle
  | Prop_LineHeight
  | Prop_TextAlign
  (* Non-Inherited Box/Layout Properties *)
  | Prop_BackgroundColor
  | Prop_MarginTop
  | Prop_MarginRight
  | Prop_MarginBottom
  | Prop_MarginLeft
  | Prop_PaddingTop
  | Prop_PaddingRight
  | Prop_PaddingBottom
  | Prop_PaddingLeft
  | Prop_BorderWidth
  | Prop_Width
  | Prop_Height
  | Prop_Display
  | Prop_BoxSizing.

Definition is_inherited_property (p : CSSPropertyId) : bool :=
  match p with
  | Prop_Color | Prop_FontSize | Prop_FontWeight
  | Prop_FontStyle | Prop_LineHeight | Prop_TextAlign => true
  | _ => false
  end.

Inductive CascadedValue : Type :=
  | CVal_Missing
  | CVal_Explicit (v : Z)
  | CVal_Initial
  | CVal_Inherit
  | CVal_Unset.

Definition resolve_property_value (prop : CSSPropertyId)
                                  (initial_val parent_val : Z)
                                  (cascaded : CascadedValue) : Z :=
  match cascaded with
  | CVal_Explicit v => v
  | CVal_Initial => initial_val
  | CVal_Inherit => parent_val
  | CVal_Missing | CVal_Unset =>
      if is_inherited_property prop then parent_val else initial_val
  end.

(** THEOREM 17: CSS `unset` Keyword Duality (CSS Cascade 5 §7.3.3) *)
Theorem css_unset_keyword_duality :
  forall (prop : CSSPropertyId) (init_v parent_v : Z),
    (is_inherited_property prop = true ->
      resolve_property_value prop init_v parent_v CVal_Unset =
      resolve_property_value prop init_v parent_v CVal_Inherit) /\
    (is_inherited_property prop = false ->
      resolve_property_value prop init_v parent_v CVal_Unset =
      resolve_property_value prop init_v parent_v CVal_Initial).
Proof.
  intros prop init_v parent_v.
  unfold resolve_property_value.
  split; intro H; rewrite H; reflexivity.
Qed.

(* ========================================================================= *)
(* SECTION 6: TRBL SHORTHANDS, LENGTH UNITS & DUAL-MODE Z calc()             *)
(*   Chromium: core/css/css_primitive_value.cc, css_math_expression_node.cc  *)
(* ========================================================================= *)

Record BoxQuad : Type := {
  bq_top    : Z;
  bq_right  : Z;
  bq_bottom : Z;
  bq_left   : Z
}.

Inductive BoxShorthandAST : Type :=
  | Shorthand_1 (a : Z)
  | Shorthand_2 (vert horiz : Z)
  | Shorthand_3 (top horiz bottom : Z)
  | Shorthand_4 (top right bottom left : Z).

Definition expand_box_shorthand (sh : BoxShorthandAST) : BoxQuad :=
  match sh with
  | Shorthand_1 a        => {| bq_top := a;    bq_right := a;     bq_bottom := a;      bq_left := a |}
  | Shorthand_2 v h      => {| bq_top := v;    bq_right := h;     bq_bottom := v;      bq_left := h |}
  | Shorthand_3 t h b    => {| bq_top := t;    bq_right := h;     bq_bottom := b;      bq_left := h |}
  | Shorthand_4 t r b l  => {| bq_top := t;    bq_right := r;     bq_bottom := b;      bq_left := l |}
  end.

(** THEOREM 18: TRBL Shorthand Horizontal/Vertical Symmetry Laws *)
Theorem expand_shorthand_symmetry_laws :
  forall (a v h t b : Z),
    let q1 := expand_box_shorthand (Shorthand_1 a) in
    let q2 := expand_box_shorthand (Shorthand_2 v h) in
    let q3 := expand_box_shorthand (Shorthand_3 t h b) in
    (bq_top q1 = bq_bottom q1 /\ bq_left q1 = bq_right q1 /\ bq_top q1 = bq_left q1) /\
    (bq_top q2 = bq_bottom q2 /\ bq_left q2 = bq_right q2) /\
    (bq_left q3 = bq_right q3).
Proof.
  intros. simpl. repeat split; reflexivity.
Qed.

Record CSSLengthContext : Type := {
  lctx_parent_px    : Z;
  lctx_font_px      : Z;
  lctx_root_font_px : Z;
  lctx_viewport_w   : Z;
  lctx_viewport_h   : Z
}.

Inductive CSSCalcExpr : Type :=
  | Calc_Px      (px : Z)
  | Calc_Percent (pct : Z)        (* pct% of lctx_parent_px *)
  | Calc_Em      (milli_em : Z)   (* milli_em / 1000 * lctx_font_px *)
  | Calc_Rem     (milli_rem : Z)  (* milli_rem / 1000 * lctx_root_font_px *)
  | Calc_Vw      (vw : Z)         (* vw% of lctx_viewport_w *)
  | Calc_Vh      (vh : Z)         (* vh% of lctx_viewport_h *)
  | Calc_Add     (e1 e2 : CSSCalcExpr)
  | Calc_Sub     (e1 e2 : CSSCalcExpr)
  | Calc_Scale   (factor : Z) (e : CSSCalcExpr).

Fixpoint eval_css_calc (mode : ZLayoutMode) (ctx : CSSLengthContext)
                       (expr : CSSCalcExpr) : Z :=
  let sc := z_scale mode in
  match expr with
  | Calc_Px px => px * sc
  | Calc_Percent pct => (lctx_parent_px ctx * sc * pct) / 100
  | Calc_Em mem => (lctx_font_px ctx * sc * mem) / 1000
  | Calc_Rem mrem => (lctx_root_font_px ctx * sc * mrem) / 1000
  | Calc_Vw vw => (lctx_viewport_w ctx * sc * vw) / 100
  | Calc_Vh vh => (lctx_viewport_h ctx * sc * vh) / 100
  | Calc_Add e1 e2 => eval_css_calc mode ctx e1 + eval_css_calc mode ctx e2
  | Calc_Sub e1 e2 => eval_css_calc mode ctx e1 - eval_css_calc mode ctx e2
  | Calc_Scale k e => k * eval_css_calc mode ctx e
  end.

(** THEOREM 19: Dual-Mode Pixel Exactness of Linear calc(a px + b px - c px) *)
Theorem eval_calc_pixel_linear_exact :
  forall (m : ZLayoutMode) (ctx : CSSLengthContext) (a b c : Z),
    z_to_device_pixel m
      (eval_css_calc m ctx (Calc_Sub (Calc_Add (Calc_Px a) (Calc_Px b)) (Calc_Px c))) =
    a + b - c.
Proof.
  intros m ctx a b c.
  destruct m; simpl; unfold z_to_device_pixel.
  - lia.
  - assert (H: a * 64 + b * 64 - c * 64 = (a + b - c) * 64) by ring.
    rewrite H. symmetry.
    apply Z.div_unique with (r := 32); [lia | ring].
Qed.

(** THEOREM 20: 100vw Resolves Exactly to Viewport Width in Both Modes *)
Theorem eval_calc_100vw_identity :
  forall (m : ZLayoutMode) (ctx : CSSLengthContext),
    z_to_device_pixel m (eval_css_calc m ctx (Calc_Vw 100)) = lctx_viewport_w ctx.
Proof.
  intros m ctx. destruct m; simpl; unfold z_to_device_pixel.
  - assert (H: (lctx_viewport_w ctx * 1 * 100) / 100 = lctx_viewport_w ctx).
    { replace (lctx_viewport_w ctx * 1 * 100) with (lctx_viewport_w ctx * 100) by ring.
      apply Z.div_mul. lia. }
    exact H.
  - assert (H1: (lctx_viewport_w ctx * 64 * 100) / 100 = lctx_viewport_w ctx * 64).
    { apply Z.div_mul. lia. }
    rewrite H1. symmetry.
    apply Z.div_unique with (r := 32); [lia | ring].
Qed.

(* ========================================================================= *)
(* SECTION 7: BOX-SIZING, FLEXBOX ROW DISTRIBUTION & TABLE COLUMN TILING     *)
(*   Chromium: core/layout/box_sizing.cc, flex/flexible_box_algorithm.cc     *)
(* ========================================================================= *)

Inductive BoxSizingMode : Type :=
  | BoxSizing_ContentBox
  | BoxSizing_BorderBox.

Definition resolve_content_inline_size (bs : BoxSizingMode)
                                       (author_w pad_l pad_r bdr_l bdr_r : Z) : Z :=
  match bs with
  | BoxSizing_ContentBox => Z.max 0 author_w
  | BoxSizing_BorderBox  => Z.max 0 (author_w - pad_l - pad_r - bdr_l - bdr_r)
  end.

Definition outer_border_box_inline_size (bs : BoxSizingMode)
                                        (author_w pad_l pad_r bdr_l bdr_r : Z) : Z :=
  resolve_content_inline_size bs author_w pad_l pad_r bdr_l bdr_r
  + pad_l + pad_r + bdr_l + bdr_r.

(** THEOREM 21: Content Inline Size is Always Non-Negative under Both Box-Sizing Modes *)
Theorem resolve_content_inline_size_nonneg :
  forall (bs : BoxSizingMode) (w pl pr bl br : Z),
    0 <= resolve_content_inline_size bs w pl pr bl br.
Proof.
  intros bs w pl pr bl br. destruct bs; simpl; lia.
Qed.

(** THEOREM 22: border-box Outer Width Conservation Law —
    Whenever author_w >= horizontal padding + border, the outer border-box width
    equals author_w with zero overflow! *)
Theorem border_box_outer_width_conservation :
  forall (author_w pl pr bl br : Z),
    0 <= pl -> 0 <= pr -> 0 <= bl -> 0 <= br ->
    pl + pr + bl + br <= author_w ->
    outer_border_box_inline_size BoxSizing_BorderBox author_w pl pr bl br = author_w.
Proof.
  intros author_w pl pr bl br Hpl Hpr Hbl Hbr Hfit.
  unfold outer_border_box_inline_size, resolve_content_inline_size.
  lia.
Qed.

Inductive FlexJustify : Type :=
  | Justify_FlexStart
  | Justify_Center
  | Justify_FlexEnd.

(** Initial main-axis offset for flex line under justify-content (CSS Flexbox 1 §8.2) *)
Definition flex_justify_initial_offset (just : FlexJustify) (free_space : Z) : Z :=
  let pos_free := Z.max 0 free_space in
  match just with
  | Justify_FlexStart => 0
  | Justify_Center    => pos_free / 2
  | Justify_FlexEnd   => pos_free
  end.

(** THEOREM 23: Flex Justify Offset Bounds (0 <= offset <= max(0, free_space)) *)
Theorem flex_justify_offset_bounded :
  forall (just : FlexJustify) (free_space : Z),
    0 <= flex_justify_initial_offset just free_space <= Z.max 0 free_space.
Proof.
  intros just free_space. unfold flex_justify_initial_offset.
  set (pf := Z.max 0 free_space).
  assert (Hpf: 0 <= pf) by (unfold pf; lia).
  destruct just.
  - lia.
  - split.
    + apply Z.div_pos; lia.
    + assert (Hle: pf / 2 <= pf).
      { apply Z.div_le_upper_bound; lia. }
      exact Hle.
  - lia.
Qed.

(** Multi-Column Table Equal-Track Width via Dual-Mode Partition Boundaries *)
Definition table_auto_col_start (mode : ZLayoutMode) (avail_w num_cols col_idx : Z) : Z :=
  z_partition_boundary mode avail_w num_cols col_idx.

Definition table_auto_col_width (mode : ZLayoutMode) (avail_w num_cols col_idx : Z) : Z :=
  z_partition_boundary mode avail_w num_cols (col_idx + 1) -
  z_partition_boundary mode avail_w num_cols col_idx.

(** THEOREM 24: Seamless Adjacent Table Column Abutment & Two-Column Exact Conservation *)
Theorem table_two_col_seamless_conservation :
  forall (mode : ZLayoutMode) (avail_w : Z),
    0 <= avail_w ->
    table_auto_col_start mode avail_w 2 0 + table_auto_col_width mode avail_w 2 0 =
      table_auto_col_start mode avail_w 2 1 /\
    table_auto_col_width mode avail_w 2 0 + table_auto_col_width mode avail_w 2 1 =
      avail_w.
Proof.
  intros mode avail_w Haw.
  unfold table_auto_col_start, table_auto_col_width.
  replace (0 + 1) with 1 by lia.
  replace (1 + 1) with 2 by lia.
  destruct mode.
  - unfold z_partition_boundary.
    assert (H0: (avail_w * 0) / 2 = 0) by (rewrite Z.mul_0_r; reflexivity).
    assert (H2: (avail_w * 2) / 2 = avail_w) by (apply Z.div_mul; lia).
    rewrite H0, H2. lia.
  - pose proof (chromium_partition_totality avail_w 2 ltac:(lia) ltac:(lia)) as [H0 H2].
    rewrite H0, H2. lia.
Qed.
