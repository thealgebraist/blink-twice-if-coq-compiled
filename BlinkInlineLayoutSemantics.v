(******************************************************************************)
(* BlinkInlineLayoutSemantics.v                                               *)
(* Sound Formal Big-Step Operational Semantics for CSS Inline Layout & Line   *)
(* Breaking (W3C CSS Text 3 / Inline Layout & Blink LayoutNG InlineItem/Line) *)
(*                                                                            *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Text Module Level 3 (§4 Line Breaking, §5 Spacing)              *)
(* 2. W3C CSS Inline Layout Module Level 3 (§2 Inline Box Model)              *)
(* 3. Blink InlineLayoutAlgorithm (`inline_layout_algorithm.cc`),             *)
(*    LineBreaker (`line_breaker.cc`), LineInfo (`line_info.cc`)             *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool PeanoNat.
Require Import BlinkOperationalSemantics.
Require Import BlinkPhysicalFragment.
Import ListNotations.
Open Scope Z_scope.

Inductive InlineItemKind : Type :=
  | ItemText (char_len : Z) (raw_w : Z)
  | ItemControlBreak                        (* Forced <br> *)
  | ItemAtomicInline (atom_w atom_h : Z).   (* Inline block / replaced *)

Record InlineItem := mkInlineItem {
  ii_kind : InlineItemKind;
  ii_margin_inline : Z;
  ii_padding_inline : Z
}.

Definition item_width (item : InlineItem) : Z :=
  match ii_kind item with
  | ItemText _ w => sat_clamp (w + ii_margin_inline item + ii_padding_inline item)
  | ItemControlBreak => 0
  | ItemAtomicInline w _ => sat_clamp (w + ii_margin_inline item + ii_padding_inline item)
  end.

Lemma item_width_nonneg : forall it,
  0 <= ii_margin_inline it ->
  0 <= ii_padding_inline it ->
  (match ii_kind it with ItemText _ w => 0 <= w | ItemAtomicInline w _ => 0 <= w | ItemControlBreak => True end) ->
  0 <= item_width it.
Proof.
  intros it Hm Hp Hw.
  unfold item_width.
  destruct (ii_kind it).
  - unfold sat_clamp.
    destruct (Z.gtb_spec (raw_w + ii_margin_inline it + ii_padding_inline it) kInt32Max); [unfold kInt32Max; lia |].
    destruct (Z.ltb_spec (raw_w + ii_margin_inline it + ii_padding_inline it) kInt32Min); [unfold kInt32Min in *; lia | lia].
  - lia.
  - unfold sat_clamp.
    destruct (Z.gtb_spec (atom_w + ii_margin_inline it + ii_padding_inline it) kInt32Max); [unfold kInt32Max; lia |].
    destruct (Z.ltb_spec (atom_w + ii_margin_inline it + ii_padding_inline it) kInt32Min); [unfold kInt32Min in *; lia | lia].
Qed.

Record LineBoxFragment := mkLineBoxFragment {
  lbf_x : Z;
  lbf_y : Z;
  lbf_width : Z;
  lbf_height : Z;
  lbf_item_count : Z
}.

(******************************************************************************)
(* LINE BREAKER GREEDY ALGORITHM (Blink LineBreaker::BreakNextLine)           *)
(******************************************************************************)

Fixpoint break_next_line (items : list InlineItem) (available_width : Z)
                         (cur_w : Z) (line_items : list InlineItem) : (list InlineItem * list InlineItem * Z) :=
  match items with
  | [] => (rev line_items, [], cur_w)
  | it :: rest =>
      match ii_kind it with
      | ItemControlBreak =>
          (rev (it :: line_items), rest, cur_w)
      | _ =>
          let w := item_width it in
          if (cur_w + w <=? available_width) || (cur_w =? 0) then
            break_next_line rest available_width (cur_w + w) (it :: line_items)
          else
            (rev line_items, items, cur_w)
      end
  end.

(******************************************************************************)
(* FULL INLINE FLOW LAYOUT: Breaks items into multiple lines                  *)
(******************************************************************************)

Inductive inline_flow_layout : list InlineItem -> Z -> Z -> Z -> list LineBoxFragment -> Z -> Prop :=
  | IFL_Nil : forall avail_w line_height cursor_y,
      inline_flow_layout [] avail_w line_height cursor_y [] cursor_y
  | IFL_Line : forall items avail_w line_height cursor_y taken_items rest_items line_w line_frag lines final_y,
      items <> [] ->
      break_next_line items avail_w 0 [] = (taken_items, rest_items, line_w) ->
      line_frag = mkLineBoxFragment 0 cursor_y line_w line_height (Z.of_nat (length taken_items)) ->
      inline_flow_layout rest_items avail_w line_height (cursor_y + line_height) lines final_y ->
      inline_flow_layout items avail_w line_height cursor_y (line_frag :: lines) final_y.

(******************************************************************************)
(* SOUNDNESS & PROGRESS THEOREMS                                              *)
(******************************************************************************)

Lemma break_next_line_rest_len : forall items avail_w cur_w acc,
  let '(_, rest, _) := break_next_line items avail_w cur_w acc in
  (length rest <= length items)%nat.
Proof.
  induction items as [| it items' IH]; intros avail_w cur_w acc.
  - simpl. lia.
  - simpl.
    destruct (ii_kind it).
    + destruct ((cur_w + item_width it <=? avail_w) || (cur_w =? 0)).
      * specialize (IH avail_w (cur_w + item_width it) (it :: acc)).
        destruct (break_next_line items' avail_w (cur_w + item_width it) (it :: acc)) as [[tk rs] w].
        simpl. lia.
      * simpl. lia.
    + simpl. lia.
    + destruct ((cur_w + item_width it <=? avail_w) || (cur_w =? 0)).
      * specialize (IH avail_w (cur_w + item_width it) (it :: acc)).
        destruct (break_next_line items' avail_w (cur_w + item_width it) (it :: acc)) as [[tk rs] w].
        simpl. lia.
      * simpl. lia.
Qed.

Theorem line_breaker_strictly_progresses :
  forall it items avail_w,
    let '(_, rest, _) := break_next_line (it :: items) avail_w 0 [] in
    (length rest < length (it :: items))%nat.
Proof.
  intros it items avail_w.
  change (break_next_line (it :: items) avail_w 0 []) with
    (match ii_kind it with
     | ItemControlBreak => (rev [it], items, 0)
     | _ =>
         if (0 + item_width it <=? avail_w) || (0 =? 0)
         then break_next_line items avail_w (0 + item_width it) [it]
         else (rev [], it :: items, 0)
     end).
  destruct (ii_kind it).
  - assert (Hcond : ((0 + item_width it <=? avail_w) || (0 =? 0)) = true).
    { rewrite orb_true_iff. right. reflexivity. }
    rewrite Hcond.
    assert (Hle := break_next_line_rest_len items avail_w (0 + item_width it) [it]).
    destruct (break_next_line items avail_w (0 + item_width it) [it]) as [[tk rs] w].
    simpl in *. lia.
  - simpl. lia.
  - assert (Hcond : ((0 + item_width it <=? avail_w) || (0 =? 0)) = true).
    { rewrite orb_true_iff. right. reflexivity. }
    rewrite Hcond.
    assert (Hle := break_next_line_rest_len items avail_w (0 + item_width it) [it]).
    destruct (break_next_line items avail_w (0 + item_width it) [it]) as [[tk rs] w].
    simpl in *. lia.
Qed.

Theorem line_breaker_deterministic :
  forall items avail_w w acc r1 r2,
    break_next_line items avail_w w acc = r1 ->
    break_next_line items avail_w w acc = r2 ->
    r1 = r2.
Proof.
  intros items avail_w w acc r1 r2 H1 H2.
  subst. reflexivity.
Qed.
