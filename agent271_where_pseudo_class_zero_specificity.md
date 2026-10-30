### Audit Report: Agent 271
**Subject:** Chromium Blink `:where()` Specificity Implementation vs. CSS Selectors Level 4 §4.3 / §17  
**Target Artifact:** `BlinkWherePseudoClassZeroSpecificitySemantics.v`  

---

### 1. Zero Specificity Semantics: $\text{spec}(\texttt{:where}(s)) = (0, 0, 0)$

#### W3C Specification Requirement
Per **CSS Selectors Level 4 §4.3 (The Zero-Specificity Pseudo-class: `:where()`)** and **§17 (Calculating a selector’s specificity)**:
> *"The `:where()` pseudo-class has the exact same syntax and semantics as `:is()`, except that neither the `:where()` pseudo-class itself nor any of its arguments contribute to the specificity of the selector: its specificity is always zero."*

Formally, if a specificity tuple is represented in base-$\infty$ lexicographical space $\mathbb{N}^3$ as $(A, B, C)$ corresponding to (ID selectors, Class/Attribute/Pseudo-class selectors, Type/Pseudo-element selectors), then for any selector list $S = [s_1, s_2, \dots, s_n]$:
$$\text{spec}(\texttt{:where}(S)) = (0, 0, 0)$$
This holds invariant of the structural depth, nesting of `:is()`/`:not()`, or high-specificity tokens (e.g., `#id`) within $S$.

#### Chromium Blink Implementation Analysis
In Chromium Blink (`third_party/blink/renderer/core/css/css_selector.cc`), specificity is computed by `CSSSelector::Specificity()` and `CSSSelector::SpecificityForOneSelector()`. 

While standard pseudo-classes fall through to return `kClassLikeSpecificity` ($B = 1$) or delegate to sub-selectors (like `kPseudoIs` and `kPseudoNot`, which compute `MaximumSpecificity(SelectorList())`), `kPseudoWhere` is explicitly intercepted:

```cpp
// third_party/blink/renderer/core/css/css_selector.cc
unsigned CSSSelector::SpecificityForOneSelector() const {
  // ...
  switch (match_) {
    // ...
    case kPseudoClass:
      switch (GetPseudoType()) {
        case kPseudoWhere:
          return 0; // Explicitly suppresses traversal of SelectorList()
        case kPseudoIs:
        case kPseudoNot:
        case kPseudoHas:
          return MaximumSpecificity(SelectorList());
        // ...
      }
  }
}
```
Blink packs $(A, B, C)$ into a 24-bit unsigned integer (`0xAABBCC`), clamping each component at `0xFF`. Returning `0` yields `(0, 0, 0)`, strictly satisfying the specification without evaluating the inner `CSSSelectorList`.

---

### 2. Core Invariants

1. **Additive Identity Invariant (Neutrality in Compound Selectors):**  
   Appending `:where(S)` to any compound or complex selector $Q$ acts as the additive identity $(0, 0, 0)$ under component-wise specificity addition $\oplus$:
   $$\forall Q, S, \quad \text{spec}(Q \cdot \texttt{:where}(S)) = \text{spec}(Q) \oplus \text{spec}(\texttt{:where}(S)) = \text{spec}(Q) \oplus (0,0,0) = \text{spec}(Q)$$

2. **Lower-Bound Dominance Invariant:**  
   Under standard lexicographical ordering $\le_{\text{spec}}$ on $\mathbb{N}^3$, `:where(S)` forms the absolute bottom element $\bot = (0,0,0)$ of the specificity lattice. Any selector $Q$ has specificity greater than or equal to `:where(S)`:
   $$\forall Q, S, \quad \text{spec}(\texttt{:where}(S)) \le_{\text{spec}} \text{spec}(Q)$$
   Furthermore, for any selector $Q$ containing at least one non-universal, non-`:where()` simple selector (i.e., strictly positive specificity), $Q$ strictly dominates `:where(S)$:
   $$\text{spec}(Q) \neq (0,0,0) \implies \text{spec}(\texttt{:where}(S)) <_{\text{spec}} \text{spec}(Q)$$

---

### 3. Formal Verification in Rocq / Coq

Below is the complete, self-contained formalization `BlinkWherePseudoClassZeroSpecificitySemantics.v`. It models the AST of CSS Selectors Level 4, contrasts `:is()`/`:not()` maximum-list evaluation against `:where()` zeroing, and proves all required invariants with **0 admits**.

```coq
(** * BlinkWherePseudoClassZeroSpecificitySemantics.v
    Formal Audit of Chromium Blink :where() Specificity vs CSS Selectors 4 §4.3.
    Agent 271 Verification Artifact. *)

From Coq Require Import Arith PeanoNat List Bool Lia.
Import ListNotations.

(** ** 1. Specificity Domain & Operations *)

Record Specificity : Type := mkSpec {
  spec_a : nat; (* ID selectors *)
  spec_b : nat; (* Class, attribute, and pseudo-class selectors *)
  spec_c : nat  (* Type selectors and pseudo-elements *)
}.

Definition zero_spec : Specificity := mkSpec 0 0 0.

Definition add_spec (s1 s2 : Specificity) : Specificity :=
  mkSpec (spec_a s1 + spec_a s2)
         (spec_b s1 + spec_b s2)
         (spec_c s1 + spec_c s2).

(** Lexicographical comparison for Specificity:
    Returns true iff s1 <= s2 in CSS specificity order. *)
Definition spec_le (s1 s2 : Specificity) : Prop :=
  (spec_a s1 < spec_a s2) \/
  (spec_a s1 = spec_a s2 /\ spec_b s1 < spec_b s2) \/
  (spec_a s1 = spec_a s2 /\ spec_b s1 = spec_b s2 /\ spec_c s1 <= spec_c s2).

(** Strict lexicographical inequality: s1 < s2 *)
Definition spec_lt (s1 s2 : Specificity) : Prop :=
  (spec_a s1 < spec_a s2) \/
  (spec_a s1 = spec_a s2 /\ spec_b s1 < spec_b s2) \/
  (spec_a s1 = spec_a s2 /\ spec_b s1 = spec_b s2 /\ spec_c s1 < spec_c s2).

(** Decidable boolean strict comparison for max calculation *)
Definition spec_ltb (s1 s2 : Specificity) : bool :=
  if spec_a s1 <? spec_a s2 then true
  else if spec_a s1 =? spec_a s2 then
    if spec_b s1 <? spec_b s2 then true
    else if spec_b s1 =? spec_b s2 then
      spec_c s1 <? spec_c s2
    else false
  else false.

Definition max_spec (s1 s2 : Specificity) : Specificity :=
  if spec_ltb s1 s2 then s2 else s1.

(** ** 2. CSS Selector AST (Level 4 Fragment) *)

Inductive SimpleSelector : Type :=
  | SelUniversal : SimpleSelector                                (* * *)
  | SelType      : SimpleSelector                                (* div, span, ::before *)
  | SelClassLike : SimpleSelector                                (* .cls, [attr], :hover *)
  | SelId        : SimpleSelector                                (* #id *)
  | SelIs        : list (list SimpleSelector) -> SimpleSelector  (* :is(s1, s2, ...) *)
  | SelNot       : list (list SimpleSelector) -> SimpleSelector  (* :not(s1, s2, ...) *)
  | SelWhere     : list (list SimpleSelector) -> SimpleSelector. (* :where(s1, s2, ...) *)

(** A Complex/Compound Selector is modeled as a sequence of SimpleSelectors
    (ignoring combinators, which do not affect specificity per §17). *)
Definition Selector := list SimpleSelector.
Definition SelectorList := list Selector.

(** ** 3. Blink & W3C §17 Specificity Evaluation Semantics *)

Fixpoint simple_specificity (ss : SimpleSelector) : Specificity :=
  let fix selector_spec (sel : Selector) : Specificity :=
    match sel with
    | [] => zero_spec
    | x :: xs => add_spec (simple_specificity x) (selector_spec xs)
    end
  in
  let fix list_max_spec (slist : SelectorList) : Specificity :=
    match slist with
    | [] => zero_spec
    | s :: ss_rest => max_spec (selector_spec s) (list_max_spec ss_rest)
    end
  in
  match ss with
  | SelUniversal     => mkSpec 0 0 0
  | SelType          => mkSpec 0 0 1
  | SelClassLike     => mkSpec 0 1 0
  | SelId            => mkSpec 1 0 0
  | SelIs slist      => list_max_spec slist
  | SelNot slist     => list_max_spec slist
  | SelWhere _       => zero_spec (* Blink CSSSelector::SpecificityForOneSelector kPseudoWhere *)
  end.

Fixpoint selector_specificity (sel : Selector) : Specificity :=
  match sel with
  | [] => zero_spec
  | ss :: rest => add_spec (simple_specificity ss) (selector_specificity rest)
  end.

(** ** 4. Fundamental Algebraic Lemmas *)

Lemma add_spec_zero_l : forall s,
  add_spec zero_spec s = s.
Proof.
  intros [a b c]. unfold add_spec, zero_spec. simpl. reflexivity.
Qed.

Lemma add_spec_zero_r : forall s,
  add_spec s zero_spec = s.
Proof.
  intros [a b c]. unfold add_spec, zero_spec. simpl.
  rewrite !Nat.add_0_r. reflexivity.
Qed.

Lemma add_spec_assoc : forall s1 s2 s3,
  add_spec s1 (add_spec s2 s3) = add_spec (add_spec s1 s2) s3.
Proof.
  intros [a1 b1 c1] [a2 b2 c2] [a3 b3 c3].
  unfold add_spec. simpl.
  rewrite !Nat.add_assoc. reflexivity.
Qed.

Lemma add_spec_comm : forall s1 s2,
  add_spec s1 s2 = add_spec s2 s1.
Proof.
  intros [a1 b1 c1] [a2 b2 c2].
  unfold add_spec. simpl.
  f_equal; lia.
Qed.

Lemma selector_specificity_app : forall s1 s2,
  selector_specificity (s1 ++ s2) =
  add_spec (selector_specificity s1) (selector_specificity s2).
Proof.
  induction s1 as [|x xs IH]; intros s2; simpl.
  - symmetry. apply add_spec_zero_l.
  - rewrite IH. apply add_spec_assoc.
Qed.

(** ** 5. Audit Requirement 1: Zero Specificity of :where() *)

(** Theorem 1a: The simple selector :where(slist) always evaluates to (0, 0, 0),
    regardless of the complexity or depth of slist. *)
Theorem blink_where_simple_zero_specificity : forall (slist : SelectorList),
  simple_specificity (SelWhere slist) = mkSpec 0 0 0.
Proof.
  intros slist. simpl. reflexivity.
Qed.

(** Theorem 1b: A standalone selector consisting solely of :where(slist)
    has specificity (0, 0, 0). *)
Theorem blink_where_selector_zero_specificity : forall (slist : SelectorList),
  selector_specificity [SelWhere slist] = mkSpec 0 0 0.
Proof.
  intros slist. simpl. reflexivity.
Qed.

(** Theorem 1c: Even if :where() wraps high-specificity selectors (e.g., #id),
    its specificity remains strictly (0, 0, 0), unlike :is() or :not(). *)
Theorem blink_where_vs_is_contrast : forall (slist : SelectorList),
  slist = [[SelId; SelClassLike; SelType]] ->
  simple_specificity (SelWhere slist) = mkSpec 0 0 0 /\
  simple_specificity (SelIs slist) = mkSpec 1 1 1.
Proof.
  intros slist H. subst slist. simpl. split; reflexivity.
Qed.

(** ** 6. Audit Requirement 2: Specificity Invariants *)

(** Invariant 2a (Prefix Neutrality): Prepending :where(slist) to any selector
    never alters its specificity sum. *)
Theorem where_prefix_specificity_invariant : forall (slist : SelectorList) (sel : Selector),
  selector_specificity (SelWhere slist :: sel) = selector_specificity sel.
Proof.
  intros slist sel. simpl. apply add_spec_zero_l.
Qed.

(** Invariant 2b (Suffix Neutrality): Appending :where(slist) to any selector
    never alters its specificity sum. *)
Theorem where_suffix_specificity_invariant : forall (slist : SelectorList) (sel : Selector),
  selector_specificity (sel ++ [SelWhere slist]) = selector_specificity sel.
Proof.
  intros slist sel.
  rewrite selector_specificity_app.
  rewrite blink_where_selector_zero_specificity.
  apply add_spec_zero_r.
Qed.

(** Invariant 2c (Arbitrary Insertion Neutrality): Inserting :where(slist) anywhere
    inside a compound/complex selector preserves exact specificity. *)
Theorem where_insertion_specificity_invariant :
  forall (slist : SelectorList) (prefix suffix : Selector),
  selector_specificity (prefix ++ SelWhere slist :: suffix) =
  selector_specificity (prefix ++ suffix).
Proof.
  intros slist prefix suffix.
  rewrite !selector_specificity_app.
  simpl.
  reflexivity.
Qed.

(** Invariant 2d (Universal Lower Bound): Any selector (even empty or universal)
    has specificity >= :where(slist). *)
Theorem any_selector_ge_where : forall (sel : Selector) (slist : SelectorList),
  spec_le (selector_specificity [SelWhere slist]) (selector_specificity sel).
Proof.
  intros sel slist.
  rewrite blink_where_selector_zero_specificity.
  unfold spec_le. simpl.
  destruct (selector_specificity sel) as [a b c]. simpl.
  destruct a as [|a'].
  - destruct b as [|b'].
    + right. right. repeat split; lia.
    