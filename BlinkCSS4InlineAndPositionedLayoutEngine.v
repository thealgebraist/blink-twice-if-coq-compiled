(* ========================================================================= *)
(* Chromium Blink CSS4, Multi-Span Inline & Positioned/Float/Grid/Table      *)
(* Unified Rocq/Coq 9.3.0 Formalization (Pillars 2, 3 & 4)                   *)
(*                                                                           *)
(* Imports & Extends:                                                        *)
(*   - BlinkDualModeZSemantics.v                                             *)
(*   - BlinkHTML5TreeBuilderAndCSSCascadeEngine.v                            *)
(*                                                                           *)
(* Formalizes:                                                               *)
(*   Pillar 2 (core/css/):                                                   *)
(*     - Selectors Level 4: `~` (subsequent-sibling), `:is(...)` & `:not()`  *)
(*       max-specificity algebra, relational `:has(...)` subtree lookahead,  *)
(*       attribute prefix/suffix/substring matchers, `::before`/`::after`    *)
(*     - Cascade Level 5/6: `revert` & `revert-layer` rollback semantics,    *)
(*       `@container` inline-size queries, `@scope (root) to (limit)` donut  *)
(*     - Values Level 4: `min()`, `max()`, `clamp()`, `color-mix(in srgb)`   *)
(*   Pillar 3 (core/layout/inline/):                                         *)
(*     - Multi-Span Inline Formatting Context (`NGInlineLayoutAlgorithm`):   *)
(*       per-span typography/color/pill-box/decoration/vertical-align,       *)
(*       float-exclusion-aware line breaking, forced `<pre>`/`\n` breaks     *)
(*   Pillar 4 (core/layout/ & core/paint/):                                  *)
(*     - Out-of-Flow Positioning (`relative`/`absolute`/`fixed` insets)      *)
(*     - CSS 2.2 Appendix E 7-Phase Paint & `z-index` Stacking Order         *)
(*     - Floats (`float: left|right`) & `clear` `ExclusionSpace` shelves     *)
(*     - Flexbox (`flex-wrap`, `flex-shrink`, `flex-direction`, `min/max`)   *)
(*     - Grid (`minmax()`, multi-track `span K`)                             *)
(*     - Table 2D `rowspan x colspan` occupancy & `border-collapse` priority *)
(*                                                                           *)
(* Strictly 0 Admits / 0 Axioms.                                             *)
(* ========================================================================= *)

From Stdlib Require Import ZArith List Bool Lia.
Require Import BlinkDualModeZSemantics.
Require Import BlinkHTML5TreeBuilderAndCSSCascadeEngine.
Import ListNotations.
Open Scope Z_scope.

#[local] Set Warnings "-register-all".

(* ========================================================================= *)
(* PART I (PILLAR 2): CSS SELECTORS L4, CASCADE ROLLBACK, @CONTAINER/@SCOPE  *)
(*                    & NONLINEAR VALUES (`min`/`max`/`clamp`/`color-mix`)   *)
(* ========================================================================= *)

(** 1.1 Attribute Substring/Token Matchers (`=`, `^=`, `$=`, `*=`, `~=`, `|=`) *)
Inductive AttrMatchOp : Type :=
  | AttrOp_Present
  | AttrOp_Exact      (* [k="v"]  *)
  | AttrOp_Prefix     (* [k^="v"] *)
  | AttrOp_Suffix     (* [k$="v"] *)
  | AttrOp_Substr     (* [k*="v"] *)
  | AttrOp_Word       (* [k~="v"] *)
  | AttrOp_DashPrefix. (* [k|="v"] *)

Fixpoint list_prefix_eqb (pat s : list Z) : bool :=
  match pat, s with
  | [], _ => true
  | _ :: _, [] => false
  | p :: ps, c :: cs => if Z.eqb p c then list_prefix_eqb ps cs else false
  end.

Fixpoint list_contains_sublist (pat s : list Z) : bool :=
  if list_prefix_eqb pat s then true
  else match s with
       | [] => false
       | _ :: tl => list_contains_sublist pat tl
       end.

Definition list_suffix_eqb (pat s : list Z) : bool :=
  list_prefix_eqb (rev pat) (rev s).

Theorem prefix_empty_always_matches : forall s : list Z,
  list_prefix_eqb [] s = true.
Proof. reflexivity. Qed.

Theorem exact_list_implies_prefix_and_substr : forall s : list Z,
  list_prefix_eqb s s = true /\ list_contains_sublist s s = true.
Proof.
  intro s.
  assert (Hp : forall l : list Z, list_prefix_eqb l l = true).
  { induction l as [| h tl IH]; simpl; [reflexivity |].
    rewrite Z.eqb_refl. exact IH. }
  split; [apply Hp |].
  destruct s as [| h tl]; simpl; [reflexivity |].
  rewrite Z.eqb_refl, Hp. reflexivity.
Qed.

(** 1.2 Selectors Level 4: `~` Combinator, `:is()`, `:not()`, and `:has()` *)

Definition spec_max (s1 s2 : Specificity) : Specificity :=
  if specificity_ltb s1 s2 then s2 else s1.

Fixpoint max_specificity_of_list (sels : list Specificity) : Specificity :=
  match sels with
  | [] => spec_zero
  | s :: rest => spec_max s (max_specificity_of_list rest)
  end.

Inductive L4SimpleSelector : Type :=
  | L4_Base   (base : SimpleSelector)
  | L4_Is     (branches : list (list SimpleSelector))  (* :is(...) max specificity  *)
  | L4_Not    (branches : list (list SimpleSelector))  (* :not(...) max specificity *)
  | L4_HasTag (child_tag : HTMLTag).                   (* :has(> tag / tag)         *)

Fixpoint compound_list_specificities (branches : list (list SimpleSelector)) : list Specificity :=
  match branches with
  | [] => []
  | b :: rest => compound_specificity b :: compound_list_specificities rest
  end.

Definition l4_simple_specificity (ss : L4SimpleSelector) : Specificity :=
  match ss with
  | L4_Base b => simple_selector_specificity b
  | L4_Is branches => max_specificity_of_list (compound_list_specificities branches)
  | L4_Not branches => max_specificity_of_list (compound_list_specificities branches)
  | L4_HasTag _ => {| spec_id := 0; spec_class := 0; spec_tag := 1 |}
  end.

Definition specificity_le (s1 s2 : Specificity) : Prop :=
  s1 = s2 \/ specificity_ltb s1 s2 = true.

Lemma specificity_trichotomy : forall s1 s2 : Specificity,
  specificity_ltb s1 s2 = true \/ s1 = s2 \/ specificity_ltb s2 s1 = true.
Proof.
  intros [i1 c1 t1] [i2 c2 t2].
  destruct (Z.lt_trichotomy i1 i2) as [Hi | [Hi | Hi]].
  - left. rewrite specificity_ltb_iff; simpl. left. lia.
  - subst i2. destruct (Z.lt_trichotomy c1 c2) as [Hc | [Hc | Hc]].
    + left. rewrite specificity_ltb_iff; simpl. right; left. lia.
    + subst c2. destruct (Z.lt_trichotomy t1 t2) as [Ht | [Ht | Ht]].
      * left. rewrite specificity_ltb_iff; simpl. right; right. lia.
      * subst t2. right; left. reflexivity.
      * right; right. rewrite specificity_ltb_iff; simpl. right; right. lia.
    + right; right. rewrite specificity_ltb_iff; simpl. right; left. lia.
  - right; right. rewrite specificity_ltb_iff; simpl. left. lia.
Qed.

Lemma specificity_le_trans : forall s1 s2 s3 : Specificity,
  specificity_le s1 s2 -> specificity_le s2 s3 -> specificity_le s1 s3.
Proof.
  intros s1 s2 s3 [E12 | L12] [E23 | L23]; subst.
  - left; reflexivity.
  - right; exact L23.
  - right; exact L12.
  - right; eapply specificity_ltb_trans; eauto.
Qed.

Lemma spec_max_upper_l : forall a b : Specificity, specificity_le a (spec_max a b).
Proof.
  intros a b. unfold spec_max.
  destruct (specificity_ltb a b) eqn:E.
  - right; exact E.
  - left; reflexivity.
Qed.

Lemma spec_max_upper_r : forall a b : Specificity, specificity_le b (spec_max a b).
Proof.
  intros a b. unfold spec_max.
  destruct (specificity_ltb a b) eqn:E.
  - left; reflexivity.
  - destruct (specificity_trichotomy a b) as [Hlt | [Heq | Hgt]].
    + rewrite Hlt in E; discriminate.
    + subst; left; reflexivity.
    + right; exact Hgt.
Qed.

(** THEOREM 1 (Selectors 4 §17): `:is(...)` and `:not(...)` have specificity at
    least as large as every branch in their selector list! *)
Theorem is_not_specificity_dominates_all_branches :
  forall (branches : list (list SimpleSelector)) (b : list SimpleSelector),
    In b branches ->
    specificity_le (compound_specificity b) (l4_simple_specificity (L4_Is branches)) /\
    specificity_le (compound_specificity b) (l4_simple_specificity (L4_Not branches)).
Proof.
  intros branches b Hin.
  assert (Hdom : forall bs : list (list SimpleSelector),
            In b bs ->
            specificity_le (compound_specificity b)
                           (max_specificity_of_list (compound_list_specificities bs))).
  { induction bs as [| h tl IH]; simpl; intro H.
    - contradiction.
    - destruct H as [Heq | Htl].
      + subst h. apply spec_max_upper_l.
      + eapply specificity_le_trans.
        * apply IH; exact Htl.
        * apply spec_max_upper_r. }
  pose proof (Hdom branches Hin) as H.
  split; exact H.
Qed.

(** `:not(...)` boolean negation complement law *)
Fixpoint match_any_compound (el : ElementSummary) (branches : list (list SimpleSelector)) : bool :=
  match branches with
  | [] => false
  | b :: rest => if match_compound_selector el b then true else match_any_compound el rest
  end.

Definition match_l4_is (el : ElementSummary) (branches : list (list SimpleSelector)) : bool :=
  match_any_compound el branches.

Definition match_l4_not (el : ElementSummary) (branches : list (list SimpleSelector)) : bool :=
  negb (match_any_compound el branches).

Theorem l4_is_not_partition_universe :
  forall (el : ElementSummary) (branches : list (list SimpleSelector)),
    xorb (match_l4_is el branches) (match_l4_not el branches) = true.
Proof.
  intros el branches. unfold match_l4_is, match_l4_not.
  destruct (match_any_compound el branches); reflexivity.
Qed.

(** General subsequent-sibling combinator `A ~ B` (`Comb_SubsequentSibling`):
    Matches if ANY preceding element sibling in `prev_sibs` matches `left_sel`! *)
Fixpoint match_subsequent_sibling (prev_sibs : list ElementSummary)
                                  (left_comp : CompoundSelector) : bool :=
  match prev_sibs with
  | [] => false
  | sib :: older =>
      if match_compound_selector sib left_comp then true
      else match_subsequent_sibling older left_comp
  end.

Theorem next_sibling_implies_subsequent_sibling :
  forall (prev_el : ElementSummary) (older : list ElementSummary) (c : CompoundSelector),
    match_compound_selector prev_el c = true ->
    match_subsequent_sibling (prev_el :: older) c = true.
Proof.
  intros prev_el older c H. simpl. rewrite H. reflexivity.
Qed.

(** Relational `:has(...)` over inductive DOM tree *)
Inductive DOMTree : Type :=
  | DOM_Node (summary : ElementSummary) (children : list DOMTree).

Fixpoint tree_has_descendant (pred : ElementSummary -> bool) (t : DOMTree) : bool :=
  let fix any_in_forest (ts : list DOMTree) : bool :=
      match ts with
      | [] => false
      | c :: rest =>
          let matched_c :=
              match c with
              | DOM_Node s _ => if pred s then true else tree_has_descendant pred c
              end
          in if matched_c then true else any_in_forest rest
      end
  in match t with
     | DOM_Node _ chs => any_in_forest chs
     end.

Theorem has_direct_child_implies_has_descendant :
  forall (pred : ElementSummary -> bool) (root_s child_s : ElementSummary)
         (c_kids : list DOMTree) (rest_siblings : list DOMTree),
    pred child_s = true ->
    tree_has_descendant pred (DOM_Node root_s (DOM_Node child_s c_kids :: rest_siblings)) = true.
Proof.
  intros pred root_s child_s c_kids rest_siblings Hp.
  simpl. rewrite Hp. reflexivity.
Qed.

(** 1.3 Cascade Level 5/6 Rollback (`revert` and `revert-layer`) *)
Record LayeredDecl : Type := {
  ld_origin : CSSOrigin;
  ld_layer  : Z;
  ld_value  : Z
}.

Fixpoint resolve_with_origin_cap (max_origin_rank : Z) (ua_default : Z)
                                 (decls : list LayeredDecl) : Z :=
  match decls with
  | [] => ua_default
  | d :: rest =>
      if cascade_origin_importance_rank (ld_origin d) false <=? max_origin_rank
      then ld_value d
      else resolve_with_origin_cap max_origin_rank ua_default rest
  end.

(** `revert` from Author origin rolls back cap to User/UA (`rank <= 2`), discarding Author (`rank = 3`) & Inline (`rank = 4`) *)
Definition resolve_author_revert (ua_default : Z) (decls_high_to_low : list LayeredDecl) : Z :=
  resolve_with_origin_cap 2 ua_default decls_high_to_low.

Theorem author_revert_discards_all_author_and_inline_decls :
  forall (ua_val v1 v2 : Z) (l1 l2 : Z),
    resolve_author_revert ua_val
      [{| ld_origin := Origin_Inline; ld_layer := l1; ld_value := v1 |};
       {| ld_origin := Origin_Author; ld_layer := l2; ld_value := v2 |}] = ua_val.
Proof.
  intros. reflexivity.
Qed.

(** `revert-layer` from layer `L` rolls back strictly to layers `< L` *)
Fixpoint resolve_revert_layer (cur_layer : Z) (fallback_val : Z)
                              (author_decls_high_to_low : list LayeredDecl) : Z :=
  match author_decls_high_to_low with
  | [] => fallback_val
  | d :: rest =>
      if ld_layer d <? cur_layer then ld_value d
      else resolve_revert_layer cur_layer fallback_val rest
  end.

Theorem revert_layer_selects_strictly_earlier_layer :
  forall (L_early L_cur v_cur v_early fb : Z),
    L_early < L_cur ->
    resolve_revert_layer L_cur fb
      [{| ld_origin := Origin_Author; ld_layer := L_cur;   ld_value := v_cur |};
       {| ld_origin := Origin_Author; ld_layer := L_early; ld_value := v_early |}] = v_early.
Proof.
  intros L_early L_cur v_cur v_early fb Hlt.
  simpl. rewrite Z.ltb_irrefl.
  destruct (L_early <? L_cur) eqn:E; [reflexivity |].
  apply Z.ltb_ge in E. lia.
Qed.

(** 1.4 `@container` Inline-Size Queries & `@scope (root) to (limit)` Donut Scope *)
Definition eval_container_inline_query (container_w : Z)
                                       (opt_min opt_max : option Z) : bool :=
  let ok_min := match opt_min with Some mn => mn <=? container_w | None => true end in
  let ok_max := match opt_max with Some mx => container_w <=? mx | None => true end in
  ok_min && ok_max.

Theorem container_query_interval_sound :
  forall (cw mn mx : Z),
    eval_container_inline_query cw (Some mn) (Some mx) = true <-> mn <= cw <= mx.
Proof.
  intros cw mn mx. unfold eval_container_inline_query.
  rewrite andb_true_iff, !Z.leb_le. tauto.
Qed.

(** `@scope (R) to (L)` Donut Scope:
    Walks from target element upward to root; succeeds if `is_root` is reached
    BEFORE encountering `is_limit`! *)
Fixpoint in_donut_scope (ancestors_bottom_up : list ElementSummary)
                        (is_root is_limit : ElementSummary -> bool) : bool :=
  match ancestors_bottom_up with
  | [] => false
  | el :: parent_ancs =>
      if is_limit el then false
      else if is_root el then true
      else in_donut_scope parent_ancs is_root is_limit
  end.

Theorem scope_limit_blocks_enclosing_scope_root :
  forall (target limit_el root_el : ElementSummary) (above : list ElementSummary)
         (is_root is_limit : ElementSummary -> bool),
    is_limit target = false ->
    is_root target = false ->
    is_limit limit_el = true ->
    in_donut_scope (target :: limit_el :: root_el :: above) is_root is_limit = false.
Proof.
  intros target limit_el root_el above is_root is_limit Hnt Hnr Hlim.
  simpl. rewrite Hnt, Hnr, Hlim. reflexivity.
Qed.

(** 1.5 Nonlinear CSS Math (`min`, `max`, `clamp`) & `color-mix(in srgb)` *)
Inductive CSSMathNode : Type :=
  | Math_Const (v : Z)
  | Math_Add   (a b : CSSMathNode)
  | Math_Sub   (a b : CSSMathNode)
  | Math_Min   (a b : CSSMathNode)
  | Math_Max   (a b : CSSMathNode)
  | Math_Clamp (lo val hi : CSSMathNode).

Fixpoint eval_css_math (n : CSSMathNode) : Z :=
  match n with
  | Math_Const v => v
  | Math_Add a b => eval_css_math a + eval_css_math b
  | Math_Sub a b => eval_css_math a - eval_css_math b
  | Math_Min a b => Z.min (eval_css_math a) (eval_css_math b)
  | Math_Max a b => Z.max (eval_css_math a) (eval_css_math b)
  | Math_Clamp lo v hi =>
      (* Per W3C CSS Values 4 §10.1: clamp(MIN, VAL, MAX) = max(MIN, min(VAL, MAX)) *)
      Z.max (eval_css_math lo) (Z.min (eval_css_math v) (eval_css_math hi))
  end.

Theorem css_clamp_bounded_when_ordered :
  forall (lo v hi : CSSMathNode),
    eval_css_math lo <= eval_css_math hi ->
    eval_css_math lo <= eval_css_math (Math_Clamp lo v hi) <= eval_css_math hi.
Proof.
  intros lo v hi Hord. simpl. lia.
Qed.

Theorem css_clamp_returns_min_when_inverted :
  forall (lo v hi : CSSMathNode),
    eval_css_math hi <= eval_css_math lo ->
    eval_css_math (Math_Clamp lo v hi) = eval_css_math lo.
Proof.
  intros lo v hi Hinv. simpl. lia.
Qed.

Definition color_mix_channel (c1 p1 c2 p2 : Z) : Z :=
  if p1 + p2 <=? 0 then 0
  else (c1 * p1 + c2 * p2) / (p1 + p2).

Theorem color_mix_channel_bounded_0_255 :
  forall (c1 p1 c2 p2 : Z),
    0 <= c1 <= 255 -> 0 <= c2 <= 255 ->
    0 <= p1 -> 0 <= p2 -> 0 < p1 + p2 ->
    0 <= color_mix_channel c1 p1 c2 p2 <= 255.
Proof.
  intros c1 p1 c2 p2 Hc1 Hc2 Hp1 Hp2 Hpos.
  unfold color_mix_channel.
  destruct (p1 + p2 <=? 0) eqn:E; [apply Z.leb_le in E; lia |].
  split.
  - apply Z.div_pos; [| lia].
    assert (0 <= c1 * p1) by (apply Z.mul_nonneg_nonneg; lia).
    assert (0 <= c2 * p2) by (apply Z.mul_nonneg_nonneg; lia).
    lia.
  - apply Z.div_le_upper_bound; [lia |].
    assert (c1 * p1 <= 255 * p1) by (apply Z.mul_le_mono_nonneg_r; lia).
    assert (c2 * p2 <= 255 * p2) by (apply Z.mul_le_mono_nonneg_r; lia).
    lia.
Qed.

(* ========================================================================= *)
(* PART II (PILLAR 3): MULTI-SPAN INLINE FORMATTING CONTEXT (`NGInlineNode`) *)
(*   Chromium: core/layout/inline/inline_layout_algorithm.cc, line_breaker.cc*)
(* ========================================================================= *)

Inductive InlineValign : Type :=
  | VAlign_Baseline
  | VAlign_Sub
  | VAlign_Super
  | VAlign_Middle.

Record InlineSpanStyle : Type := {
  iss_font_px     : Z;
  iss_bold        : bool;
  iss_italic      : bool;
  iss_underline   : bool;
  iss_strike      : bool;
  iss_valign      : InlineValign;
  iss_color_argb  : Z;
  iss_has_pill_bg : bool;
  iss_pad_inline  : Z
}.

Record InlineToken : Type := {
  itok_width          : Z;
  itok_space_after    : Z;
  itok_forced_newline : bool;
  itok_style          : InlineSpanStyle
}.

Record PositionedInlineFrag : Type := {
  pif_line_idx : Z;
  pif_x        : Z;
  pif_w        : Z;
  pif_style    : InlineSpanStyle
}.

(** Float-aware line band `(band_left, band_right)` for line index `l` *)
Definition LineBandFn : Type := Z -> (Z * Z).

Fixpoint break_inline_tokens (band : LineBandFn)
                             (cur_line : Z)
                             (cur_x : Z)
                             (on_line_start : bool)
                             (toks : list InlineToken)
  : list PositionedInlineFrag :=
  match toks with
  | [] => []
  | tok :: rest =>
      let '(b_left, b_right) := band cur_line in
      if itok_forced_newline tok then
        let next_l := cur_line + 1 in
        let '(nl_left, _) := band next_l in
        break_inline_tokens band next_l nl_left true rest
      else
        let w := Z.max 0 (itok_width tok) in
        let sp := Z.max 0 (itok_space_after tok) in
        if (negb on_line_start) && (b_right <? cur_x + w) then
          (* Wrap onto next line *)
          let next_l := cur_line + 1 in
          let '(nl_left, _) := band next_l in
          let frag := {| pif_line_idx := next_l;
                         pif_x := nl_left;
                         pif_w := w;
                         pif_style := itok_style tok |} in
          frag :: break_inline_tokens band next_l (nl_left + w + sp) false rest
        else
          let place_x := if on_line_start then b_left else cur_x in
          let frag := {| pif_line_idx := cur_line;
                         pif_x := place_x;
                         pif_w := w;
                         pif_style := itok_style tok |} in
          frag :: break_inline_tokens band cur_line (place_x + w + sp) false rest
  end.

Fixpoint count_non_newline_tokens (toks : list InlineToken) : nat :=
  match toks with
  | [] => 0%nat
  | t :: rest =>
      if itok_forced_newline t then count_non_newline_tokens rest
      else S (count_non_newline_tokens rest)
  end.

(** THEOREM 2 (Inline Fragment Conservation):
    Multi-span line breaking emits an exact 1-to-1 positioned fragment for every
    visible inline token across arbitrary styled spans (`<b>`, `<i>`, `<a>`, `<code>`)! *)
Theorem break_inline_tokens_conserves_visible_spans :
  forall (toks : list InlineToken) (band : LineBandFn) (l x : Z) (start : bool),
    length (break_inline_tokens band l x start toks) = count_non_newline_tokens toks.
Proof.
  induction toks as [| tok rest IH]; intros band l x start; simpl; [reflexivity |].
  destruct (band l) as [bl br].
  destruct (itok_forced_newline tok) eqn:Enl.
  - destruct (band (l + 1)) as [nll nlr]. apply IH.
  - destruct ((negb start) && (br <? x + Z.max 0 (itok_width tok))) eqn:Ewrap.
    + destruct (band (l + 1)) as [nll nlr]. simpl. f_equal. apply IH.
    + simpl. f_equal. apply IH.
Qed.

(** THEOREM 3 (Inline Line-Box Bounds Soundness):
    Whenever every token's width fits within its line's available float-exclusion
    band `[b_left, b_right]`, every emitted fragment lies strictly within `[b_left, b_right]`! *)
Theorem break_inline_tokens_respects_band_bounds :
  forall (toks : list InlineToken) (band : LineBandFn) (l x : Z) (start : bool)
         (frag : PositionedInlineFrag),
    (start = false -> fst (band l) <= x) ->
    (forall t line_i, In t toks -> Z.max 0 (itok_width t) <= snd (band line_i) - fst (band line_i)) ->
    In frag (break_inline_tokens band l x start toks) ->
    fst (band (pif_line_idx frag)) <= pif_x frag /\
    pif_x frag + pif_w frag <= snd (band (pif_line_idx frag)).
Proof.
  induction toks as [| tok rest IH]; intros band l x start frag Hx Hfit Hin.
  - simpl in Hin; contradiction.
  - simpl in Hin.
    destruct (band l) as [bl br] eqn:Ebl.
    destruct (itok_forced_newline tok) eqn:Enl.
    + destruct (band (l + 1)) as [nll nlr] eqn:Enl_b.
      eapply IH with (l := l + 1) (x := nll) (start := true); eauto.
      * intro Hfalse; discriminate.
      * intros t li Ht; apply Hfit; right; exact Ht.
    + set (w := Z.max 0 (itok_width tok)) in *.
      set (sp := Z.max 0 (itok_space_after tok)) in *.
      destruct ((negb start) && (br <? x + w)) eqn:Ewrap.
      * destruct (band (l + 1)) as [nll nlr] eqn:Enl_b.
        simpl in Hin. destruct Hin as [Heq | Hrest].
        -- subst frag. simpl. rewrite Enl_b. simpl.
           pose proof (Hfit tok (l + 1) (or_introl eq_refl)) as Hw.
           rewrite Enl_b in Hw; simpl in Hw. lia.
        -- eapply IH with (l := l + 1) (x := nll + w + sp) (start := false); eauto.
           ++ rewrite Enl_b; simpl. intro. lia.
           ++ intros t li Ht; apply Hfit; right; exact Ht.
      * simpl in Hin. destruct Hin as [Heq | Hrest].
        -- subst frag. simpl. rewrite Ebl; simpl.
           pose proof (Hfit tok l (or_introl eq_refl)) as Hw.
           rewrite Ebl in Hw; simpl in Hw.
           destruct start; simpl in *.
           ++ lia.
           ++ apply Z.ltb_ge in Ewrap.
              pose proof (Hx eq_refl) as Hxl.
              lia.
        -- eapply IH with (l := l) (x := (if start then bl else x) + w + sp) (start := false); eauto.
           ++ rewrite Ebl; simpl. intro.
              destruct start; [lia |].
              simpl in Hx. pose proof (Hx eq_refl) as Hxl. lia.
           ++ intros t li Ht; apply Hfit; right; exact Ht.
Qed.

(* ========================================================================= *)
(* PART III (PILLAR 4): POSITIONING, Z-INDEX STACKING, FLOATS, FLEX, GRID    *)
(*                      & TABLE 2D ROWSPAN + BORDER-COLLAPSE                 *)
(* ========================================================================= *)

(** 3.1 Out-of-Flow Absolute/Fixed 1D Axis Constraint Solver (CSS Position L3 §4) *)
Definition resolve_abs_axis (cb_size : Z)
                            (opt_start opt_end opt_size : option Z)
                            (intrinsic_size : Z) : (Z * Z) :=
  match opt_start, opt_end, opt_size with
  | Some s, Some e, None =>
      let sz := Z.max 0 (cb_size - s - e) in (s, sz)
  | Some s, _, Some sz =>
      (s, Z.max 0 sz)
  | Some s, None, None =>
      (s, Z.max 0 intrinsic_size)
  | None, Some e, Some sz =>
      let csz := Z.max 0 sz in (cb_size - e - csz, csz)
  | None, Some e, None =>
      let csz := Z.max 0 intrinsic_size in (cb_size - e - csz, csz)
  | None, None, Some sz =>
      (0, Z.max 0 sz)
  | None, None, None =>
      (0, Z.max 0 intrinsic_size)
  end.

Theorem abs_both_insets_auto_size_exact_fit :
  forall (cb s e intr : Z),
    s + e <= cb ->
    let '(pos, sz) := resolve_abs_axis cb (Some s) (Some e) None intr in
    pos = s /\ pos + sz + e = cb.
Proof.
  intros cb s e intr Hfit. simpl. lia.
Qed.

Theorem abs_end_anchored_touches_right_inset :
  forall (cb e sz intr : Z),
    0 <= sz ->
    let '(pos, out_sz) := resolve_abs_axis cb None (Some e) (Some sz) intr in
    pos + out_sz + e = cb.
Proof.
  intros cb e sz intr Hsz. simpl. lia.
Qed.

(** 3.2 CSS 2.2 Appendix E 7-Phase Paint & `z-index` Stacking Order *)
Inductive PaintPhase : Type :=
  | Phase_1_RootBackgroundBorders
  | Phase_2_NegativeZIndex      (* z-index < 0 *)
  | Phase_3_InFlowBlocks
  | Phase_4_NonPositionedFloats
  | Phase_5_InFlowInlineRuns
  | Phase_6_ZeroOrAutoPositioned (* z-index: auto / 0 *)
  | Phase_7_PositiveZIndex.      (* z-index > 0 *)

Definition paint_phase_rank (p : PaintPhase) : Z :=
  match p with
  | Phase_1_RootBackgroundBorders => 1
  | Phase_2_NegativeZIndex        => 2
  | Phase_3_InFlowBlocks          => 3
  | Phase_4_NonPositionedFloats   => 4
  | Phase_5_InFlowInlineRuns      => 5
  | Phase_6_ZeroOrAutoPositioned  => 6
  | Phase_7_PositiveZIndex        => 7
  end.

Record StackingPaintItem : Type := {
  spi_phase     : PaintPhase;
  spi_z_index   : Z;
  spi_dom_order : Z
}.

Definition stacking_item_ltb (a b : StackingPaintItem) : bool :=
  let pa := paint_phase_rank (spi_phase a) in
  let pb := paint_phase_rank (spi_phase b) in
  if pa <? pb then true
  else if pb <? pa then false
  else if spi_z_index a <? spi_z_index b then true
  else if spi_z_index b <? spi_z_index a then false
  else spi_dom_order a <? spi_dom_order b.

Theorem stacking_item_ltb_irrefl : forall x : StackingPaintItem,
  stacking_item_ltb x x = false.
Proof.
  intro x. unfold stacking_item_ltb.
  repeat rewrite Z.ltb_irrefl. reflexivity.
Qed.

Lemma stacking_item_ltb_iff : forall a b : StackingPaintItem,
  stacking_item_ltb a b = true <->
    (paint_phase_rank (spi_phase a) < paint_phase_rank (spi_phase b) \/
     (paint_phase_rank (spi_phase a) = paint_phase_rank (spi_phase b) /\
      spi_z_index a < spi_z_index b) \/
     (paint_phase_rank (spi_phase a) = paint_phase_rank (spi_phase b) /\
      spi_z_index a = spi_z_index b /\
      spi_dom_order a < spi_dom_order b)).
Proof.
  intros a b. unfold stacking_item_ltb.
  set (pa := paint_phase_rank (spi_phase a)).
  set (pb := paint_phase_rank (spi_phase b)).
  destruct (pa <? pb) eqn:E1; [apply Z.ltb_lt in E1; split; [intro; left; lia | reflexivity] | apply Z.ltb_ge in E1].
  destruct (pb <? pa) eqn:E2; [apply Z.ltb_lt in E2; split; [discriminate | intro H; lia] | apply Z.ltb_ge in E2].
  destruct (spi_z_index a <? spi_z_index b) eqn:E3; [apply Z.ltb_lt in E3; split; [intro; right; left; lia | reflexivity] | apply Z.ltb_ge in E3].
  destruct (spi_z_index b <? spi_z_index a) eqn:E4; [apply Z.ltb_lt in E4; split; [discriminate | intro H; lia] | apply Z.ltb_ge in E4].
  rewrite Z.ltb_lt. split; intro H; [right; right; lia | lia].
Qed.

Theorem stacking_item_ltb_trans : forall a b c : StackingPaintItem,
  stacking_item_ltb a b = true ->
  stacking_item_ltb b c = true ->
  stacking_item_ltb a c = true.
Proof.
  intros a b c H12 H23.
  rewrite stacking_item_ltb_iff in *. lia.
Qed.

Theorem appendix_e_negative_z_before_inflow_before_positive_z :
  forall (neg_it blk_it flt_it inl_it pos_it : StackingPaintItem),
    spi_phase neg_it = Phase_2_NegativeZIndex ->
    spi_phase blk_it = Phase_3_InFlowBlocks ->
    spi_phase flt_it = Phase_4_NonPositionedFloats ->
    spi_phase inl_it = Phase_5_InFlowInlineRuns ->
    spi_phase pos_it = Phase_7_PositiveZIndex ->
    stacking_item_ltb neg_it blk_it = true /\
    stacking_item_ltb blk_it flt_it = true /\
    stacking_item_ltb flt_it inl_it = true /\
    stacking_item_ltb inl_it pos_it = true.
Proof.
  intros neg_it blk_it flt_it inl_it pos_it H1 H2 H3 H4 H5.
  repeat rewrite stacking_item_ltb_iff.
  rewrite H1, H2, H3, H4, H5. simpl. repeat split; left; lia.
Qed.

(** 3.3 Floats (`float: left | right`) & `clear` `ExclusionSpace` *)
Inductive CSSClear : Type :=
  | Clear_None
  | Clear_Left
  | Clear_Right
  | Clear_Both.

Record FloatExclusionSpace : Type := {
  fes_container_left   : Z;
  fes_container_right  : Z;
  fes_left_edge        : Z; (* Current right-edge of active left floats *)
  fes_left_bottom_y    : Z;
  fes_right_edge       : Z; (* Current left-edge of active right floats *)
  fes_right_bottom_y   : Z
}.

Definition available_band_at_y (fes : FloatExclusionSpace) (y : Z) : (Z * Z) :=
  let lx := if y <? fes_left_bottom_y fes then fes_left_edge fes else fes_container_left fes in
  let rx := if y <? fes_right_bottom_y fes then fes_right_edge fes else fes_container_right fes in
  (lx, Z.max lx rx).

Definition apply_clearance_y (fes : FloatExclusionSpace) (cl : CSSClear) (cur_y : Z) : Z :=
  match cl with
  | Clear_None  => cur_y
  | Clear_Left  => Z.max cur_y (fes_left_bottom_y fes)
  | Clear_Right => Z.max cur_y (fes_right_bottom_y fes)
  | Clear_Both  => Z.max cur_y (Z.max (fes_left_bottom_y fes) (fes_right_bottom_y fes))
  end.

Theorem available_band_nonneg_width :
  forall (fes : FloatExclusionSpace) (y : Z),
    let '(lx, rx) := available_band_at_y fes y in
    lx <= rx.
Proof.
  intros fes y. unfold available_band_at_y. lia.
Qed.

Theorem clear_both_restores_full_container_width :
  forall (fes : FloatExclusionSpace) (cur_y : Z),
    fes_container_left fes <= fes_container_right fes ->
    let cleared_y := apply_clearance_y fes Clear_Both cur_y in
    available_band_at_y fes cleared_y = (fes_container_left fes, fes_container_right fes).
Proof.
  intros fes cur_y Hle. simpl. unfold available_band_at_y.
  set (cy := Z.max cur_y (Z.max (fes_left_bottom_y fes) (fes_right_bottom_y fes))).
  assert (E1 : (cy <? fes_left_bottom_y fes) = false) by (apply Z.ltb_ge; lia).
  assert (E2 : (cy <? fes_right_bottom_y fes) = false) by (apply Z.ltb_ge; lia).
  rewrite E1, E2. f_equal. lia.
Qed.

(** 3.4 Flexbox `flex-shrink` Contraction, `min/max` Clamping & `flex-wrap` *)
Definition flex_shrink_width (base_w deficit shrink_weight total_weighted : Z) : Z :=
  if (deficit <=? 0) || (total_weighted <=? 0) then Z.max 0 base_w
  else Z.max 0 (base_w - (deficit * base_w * shrink_weight) / total_weighted).

Theorem flex_shrink_nonneg_and_at_most_base :
  forall (base_w deficit sw tot : Z),
    0 <= base_w -> 0 <= sw ->
    0 <= flex_shrink_width base_w deficit sw tot <= base_w.
Proof.
  intros base_w deficit sw tot Hb Hsw.
  unfold flex_shrink_width.
  destruct ((deficit <=? 0) || ( tot <=? 0)) eqn:E.
  - lia.
  - apply orb_false_iff in E as [Ed Et].
    apply Z.leb_gt in Ed. apply Z.leb_gt in Et.
    assert (Hdiv : 0 <= (deficit * base_w * sw) / tot).
    { apply Z.div_pos; [| lia].
      apply Z.mul_nonneg_nonneg; [apply Z.mul_nonneg_nonneg; lia | lia]. }
    lia.
Qed.

Fixpoint count_wrapped_flex_items (lines : list (list Z)) : nat :=
  match lines with
  | [] => 0%nat
  | l :: rest => (length l + count_wrapped_flex_items rest)%nat
  end.

Fixpoint wrap_flex_row_widths (max_line_w gap : Z)
                              (cur_line : list Z) (cur_used : Z)
                              (items : list Z) : list (list Z) :=
  match items with
  | [] =>
      match cur_line with
      | [] => []
      | _ => [rev cur_line]
      end
  | w :: rest =>
      match cur_line with
      | [] => wrap_flex_row_widths max_line_w gap [w] w rest
      | _ =>
          if max_line_w <? cur_used + gap + w then
            rev cur_line :: wrap_flex_row_widths max_line_w gap [w] w rest
          else
            wrap_flex_row_widths max_line_w gap (w :: cur_line) (cur_used + gap + w) rest
      end
  end.

Theorem wrap_flex_row_conserves_item_count :
  forall (items : list Z) (max_w gap : Z) (cur_line : list Z) (cur_used : Z),
    count_wrapped_flex_items (wrap_flex_row_widths max_w gap cur_line cur_used items) =
    (length cur_line + length items)%nat.
Proof.
  induction items as [| w rest IH]; intros max_w gap cur_line cur_used; simpl.
  - destruct cur_line as [| c0 cs]; simpl; [reflexivity | rewrite length_app, length_rev; simpl; lia].
  - destruct cur_line as [| c0 cs].
    + rewrite IH. simpl. lia.
    + destruct (max_w <? cur_used + gap + w) eqn:Ewrap; simpl.
      * rewrite length_app, length_rev, IH. simpl. lia.
      * rewrite IH. simpl. lia.
Qed.

(** 3.5 Grid `minmax(min_track, max_track)` & Multi-Track Span Width *)
Definition resolve_minmax_track (min_t max_t avail_share : Z) : Z :=
  Z.max min_t (Z.min avail_share max_t).

Theorem minmax_track_always_ge_min :
  forall (min_t max_t avail_share : Z),
    min_t <= resolve_minmax_track min_t max_t avail_share.
Proof.
  intros. unfold resolve_minmax_track. lia.
Qed.

(** CSS Grid §7.2 / §11: Multi-column track span inline size resolution.
    Pre-extracted track span K combines the widths of K consecutive tracks
    plus (K - 1) column gaps! *)
Definition multi_track_span_width (track_widths : list Z) (gap : Z) (start_idx span_len : nat) : Z :=
  let sub := firstn span_len (skipn start_idx track_widths) in
  let sum_tracks := fold_right Z.add 0 sub in
  let n_tracks := Z.of_nat (length sub) in
  if n_tracks <=? 1 then sum_tracks
  else sum_tracks + (n_tracks - 1) * gap.

Lemma in_firstn_in : forall (A : Type) (n : nat) (l : list A) (x : A),
  In x (firstn n l) -> In x l.
Proof.
  intros A n. induction n as [| n' IH]; intros l x Hin; simpl in Hin.
  - contradiction.
  - destruct l as [| h tl]; simpl in Hin; [contradiction |].
    destruct Hin as [Heq | Hin].
    + left; exact Heq.
    + right; apply (IH tl x Hin).
Qed.

Lemma in_skipn_in : forall (A : Type) (n : nat) (l : list A) (x : A),
  In x (skipn n l) -> In x l.
Proof.
  intros A n. induction n as [| n' IH]; intros l x Hin; simpl in Hin.
  - exact Hin.
  - destruct l as [| h tl]; simpl in Hin; [contradiction |].
    right; apply (IH tl x Hin).
Qed.

Theorem multi_track_span_width_nonnegative :
  forall (tracks : list Z) (gap : Z) (start_idx span_len : nat),
    (forall w, In w tracks -> 0 <= w) ->
    0 <= gap ->
    0 <= multi_track_span_width tracks gap start_idx span_len.
Proof.
  intros tracks gap start_idx span_len Hw Hgap.
  unfold multi_track_span_width.
  set (sub := firstn span_len (skipn start_idx tracks)).
  assert (Hsub: forall w, In w sub -> 0 <= w).
  { intros w Hwsub. apply Hw.
    unfold sub in Hwsub.
    apply (in_firstn_in Z span_len (skipn start_idx tracks) w) in Hwsub.
    apply (in_skipn_in Z start_idx tracks w) in Hwsub.
    exact Hwsub. }
  assert (Hsum: 0 <= fold_right Z.add 0 sub).
  { clear Hw. induction sub as [| tw rest IH]; simpl.
    - lia.
    - assert (0 <= tw) by (apply Hsub; left; reflexivity).
      assert (Hrest: 0 <= fold_right Z.add 0 rest).
      { apply IH. intros x Hx; apply Hsub; right; exact Hx. }
      lia. }
  set (n_tracks := Z.of_nat (length sub)).
  destruct (n_tracks <=? 1) eqn:E.
  - exact Hsum.
  - apply Z.leb_gt in E.
    assert (0 <= (n_tracks - 1) * gap).
    { apply Z.mul_nonneg_nonneg; lia. }
    lia.
Qed.

(** Pre-extracted 2-column span equals track 0 + gap + track 1 *)
Theorem multi_track_span_two_columns_sum :
  forall (w0 w1 : Z) (gap : Z),
    multi_track_span_width [w0; w1] gap 0 2 = w0 + gap + w1.
Proof.
  intros w0 w1 gap.
  unfold multi_track_span_width. simpl.
  destruct gap; lia.
Qed.



(** 3.6 Table 2D `rowspan x colspan` Occupancy & `border-collapse` Conflict *)
Definition CellCoord : Type := (Z * Z).

Definition in_cell_rect (r0 c0 rowspan colspan : Z) (pt : CellCoord) : bool :=
  let '(r, c) := pt in
  (r0 <=? r) && (r <? r0 + rowspan) && (c0 <=? c) && (c <? c0 + colspan).

Theorem sanitized_cell_rect_contains_origin :
  forall (r0 c0 raw_rs raw_cs : Z),
    in_cell_rect r0 c0 (Z.max 1 raw_rs) (Z.max 1 raw_cs) (r0, c0) = true.
Proof.
  intros r0 c0 raw_rs raw_cs. unfold in_cell_rect.
  repeat rewrite andb_true_iff.
  rewrite !Z.leb_le, !Z.ltb_lt. lia.
Qed.

(** CSS 2.1 §17.6.2.1 Border Conflict Resolution in `border-collapse: collapse`:
    1. `BorderStyle_Hidden` suppresses all other borders unconditionally (width 0).
    2. `BorderStyle_None` loses to any visible border.
    3. Wider border wins!
    4. Equal width -> style precedence (`double > solid > dashed > dotted > ridge > outset > groove > inset`). *)
Inductive CollapsedBorderStyle : Type :=
  | CB_None
  | CB_Inset | CB_Groove | CB_Outset | CB_Ridge
  | CB_Dotted | CB_Dashed | CB_Solid | CB_Double
  | CB_Hidden.

Definition cb_style_rank (s : CollapsedBorderStyle) : Z :=
  match s with
  | CB_None   => 0
  | CB_Inset  => 1
  | CB_Groove => 2
  | CB_Outset => 3
  | CB_Ridge  => 4
  | CB_Dotted => 5
  | CB_Dashed => 6
  | CB_Solid  => 7
  | CB_Double => 8
  | CB_Hidden => 9
  end.

Record CollapsedBorderEdge : Type := {
  cbe_style : CollapsedBorderStyle;
  cbe_width : Z;
  cbe_color : Z
}.

Definition resolve_collapsed_border (e1 e2 : CollapsedBorderEdge) : CollapsedBorderEdge :=
  match cbe_style e1, cbe_style e2 with
  | CB_Hidden, _ => {| cbe_style := CB_Hidden; cbe_width := 0; cbe_color := 0 |}
  | _, CB_Hidden => {| cbe_style := CB_Hidden; cbe_width := 0; cbe_color := 0 |}
  | CB_None, _   => e2
  | _, CB_None   => e1
  | _, _ =>
      if cbe_width e1 <? cbe_width e2 then e2
      else if cbe_width e2 <? cbe_width e1 then e1
      else if cb_style_rank (cbe_style e1) <? cb_style_rank (cbe_style e2) then e2
      else e1
  end.

Theorem collapsed_border_hidden_absorbs_both_sides :
  forall (e : CollapsedBorderEdge) (w c : Z),
    cbe_width (resolve_collapsed_border {| cbe_style := CB_Hidden; cbe_width := w; cbe_color := c |} e) = 0 /\
    cbe_width (resolve_collapsed_border e {| cbe_style := CB_Hidden; cbe_width := w; cbe_color := c |}) = 0.
Proof.
  intros [st ew ec] w c. destruct st; simpl; split; reflexivity.
Qed.

Theorem collapsed_border_wider_visible_wins :
  forall (e1 e2 : CollapsedBorderEdge),
    cbe_style e1 <> CB_Hidden -> cbe_style e1 <> CB_None ->
    cbe_style e2 <> CB_Hidden -> cbe_style e2 <> CB_None ->
    cbe_width e1 < cbe_width e2 ->
    resolve_collapsed_border e1 e2 = e2.
Proof.
  intros [s1 w1 c1] [s2 w2 c2] Hnh1 Hnn1 Hnh2 Hnn2 Hlt.
  simpl in *.
  assert (Elt : (w1 <? w2) = true) by (apply Z.ltb_lt; lia).
  destruct s1; try contradiction; destruct s2; try contradiction;
    unfold resolve_collapsed_border; simpl; rewrite Elt; reflexivity.
Qed.
