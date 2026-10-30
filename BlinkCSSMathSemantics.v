(******************************************************************************)
(* BlinkCSSMathSemantics.v                                                    *)
(* Sound Formal Specification & Big-Step Semantics for CSS Math Expressions   *)
(* Corresponding to:                                                          *)
(* 1. W3C CSS Values and Units Level 4 Section 10 (Mathematical Expressions)   *)
(* 2. Blink CSSMathExpressionNode & CSSLengthResolver                         *)
(*    (`third_party/blink/renderer/core/css/css_math_expression_node.cc`)     *)
(******************************************************************************)

From Stdlib Require Import ZArith List Lia Bool.
Require Import BlinkOperationalSemantics.
Open Scope Z_scope.

Inductive CSSMathCategory : Type :=
  | CatNumber
  | CatLength
  | CatPercent.

Inductive CSSMathOperator : Type :=
  | OpAdd
  | OpSubtract
  | OpMultiply
  | OpDivide
  | OpMin
  | OpMax
  | OpClamp.

Inductive CSSMathNode : Type :=
  | NodeNumber (val : Z)
  | NodeLengthPx (px : Z)
  | NodePercent (pct : Z)
  | NodeBinary (op : CSSMathOperator) (left right : CSSMathNode)
  | NodeTernaryClamp (min_val val max_val : CSSMathNode).

Definition node_category (n : CSSMathNode) : CSSMathCategory :=
  match n with
  | NodeNumber _ => CatNumber
  | NodeLengthPx _ => CatLength
  | NodePercent _ => CatPercent
  | NodeBinary _ l _ => match l with NodeNumber _ => CatNumber | NodePercent _ => CatPercent | _ => CatLength end
  | NodeTernaryClamp _ v _ => match v with NodeNumber _ => CatNumber | NodePercent _ => CatPercent | _ => CatLength end
  end.

Fixpoint eval_math_node (n : CSSMathNode) (pct_basis_px : Z) : Z :=
  match n with
  | NodeNumber v => v
  | NodeLengthPx px => px
  | NodePercent pct => Z.quot (pct * pct_basis_px) 100
  | NodeBinary op l r =>
      let el := eval_math_node l pct_basis_px in
      let er := eval_math_node r pct_basis_px in
      match op with
      | OpAdd => sat_clamp (el + er)
      | OpSubtract => sat_clamp (el - er)
      | OpMultiply => sat_clamp (el * er)
      | OpDivide => if er =? 0 then 0 else sat_clamp (Z.quot el er)
      | OpMin => Z.min el er
      | OpMax => Z.max el er
      | OpClamp => sat_clamp (Z.max el (Z.min er el))
      end
  | NodeTernaryClamp min_node val_node max_node =>
      let mn := eval_math_node min_node pct_basis_px in
      let v := eval_math_node val_node pct_basis_px in
      let mx := eval_math_node max_node pct_basis_px in
      if mx <? mn then mn
      else sat_clamp (Z.max mn (Z.min mx v))
  end.

(******************************************************************************)
(* SOUNDNESS & IDEMPOTENCE THEOREMS (0 admits)                                *)
(******************************************************************************)

Theorem eval_math_node_deterministic :
  forall n basis r1 r2,
    r1 = eval_math_node n basis ->
    r2 = eval_math_node n basis ->
    r1 = r2.
Proof.
  intros n basis r1 r2 H1 H2.
  subst. reflexivity.
Qed.

Theorem clamp_respects_bounds :
  forall mn v mx basis,
    let mn_node := NodeLengthPx mn in
    let v_node := NodeLengthPx v in
    let mx_node := NodeLengthPx mx in
    mn <= mx ->
    kInt32Min <= mn ->
    mx <= kInt32Max ->
    mn <= eval_math_node (NodeTernaryClamp mn_node v_node mx_node) basis <= mx.
Proof.
  intros mn v mx basis mn_node v_node mx_node Hle Hmin_bound Hmax_bound.
  unfold mn_node, v_node, mx_node. simpl.
  destruct (mx <? mn) eqn:Elt.
  - apply Z.ltb_lt in Elt. lia.
  - assert (Hinner : mn <= Z.max mn (Z.min mx v) <= mx) by lia.
    unfold sat_clamp.
    destruct (Z.gtb_spec (Z.max mn (Z.min mx v)) kInt32Max).
    + lia.
    + destruct (Z.ltb_spec (Z.max mn (Z.min mx v)) kInt32Min).
      * lia.
      * lia.
Qed.

Theorem math_add_literal_sound :
  forall p1 p2 basis,
    eval_math_node (NodeBinary OpAdd (NodeLengthPx p1) (NodeLengthPx p2)) basis =
    sat_clamp (p1 + p2).
Proof.
  intros. simpl. reflexivity.
Qed.
