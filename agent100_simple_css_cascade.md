### 1. Core Data Structures in Blink Style Cascade

In Chromium’s Blink engine (`third_party/blink/renderer/core/css/resolver/`), the style resolution pipeline transforms matched CSS rules into a concrete `ComputedStyle` via a tightly packed, bit-level priority system.

*   **`MatchResult` (`match_result.h`)**: Accumulates the output of the `ElementRuleCollector`. It stores `MatchedProperties` vectors partitioned by origin (User-Agent, User, Author) and tree scope (Shadow DOM encapsulation). Each entry contains a `CSSPropertyValueSet` along with metadata concerning cascade layer order, inline status, and cascade origin.
*   **`CascadePriority` (`cascade_priority.h`)**: A 64-bit unsigned integer (`uint64_t`) encoding the sorting key specified in CSS Cascading and Inheritance Level 4 (§6.1). Blink packs origin, importance, tree-scope order, cascade layer order, inline style flag, specificity, and position of appearance into bitfields. This allows comparing the precedence of any two declarations in $O(1)$ time using a single integer comparison (`>=`).
*   **`StyleCascade` (`style_cascade.h`)**: Consumes a `MatchResult` and holds a `CascadeMap`—a specialized hash/array mapping each `CSSPropertyID` (and custom property AtomicString) to its highest-winning `CascadePriority`. During the `Apply()` phase, `StyleCascade` iterates through the winning declarations, resolves dependencies (`var()`, `em`, `lh`), and invokes the generated `StyleBuilder` to write values into the target `StyleResolverState`.
*   **`ComputedStyle` (`computed_style.h`)**: An immutable, ref-counted value object representing the final resolved values of all CSS properties for a DOM node. For memory efficiency, Blink splits data into `InheritedData` (shared via pointer copy from parent to child if unmodified) and `NonInheritedData` (initialized to specification initial values via DataRef copy-on-write structs).

---

### 2. Cascade Origin & Layer Precedence

Excluding `!important` overrides, animations, and transitions, the simplified normal cascade order (CSS Cascading 4 §6.1) forms a strict total order across declaration sources:

$$\text{User-Agent (UA) Defaults} \prec \text{Author Stylesheets} \prec \text{Inline Style Attributes}$$

1.  **User-Agent (UA) Default Styles (`Origin::kUserAgent`)**: Lowest priority. Loaded from Blink's internal resources (e.g., `html.css`). Establishes base element semantics (e.g., `div { display: block }`).
2.  **Author Stylesheet Rules (`Origin::kAuthor`, `is_inline = false`)**: Overrides UA rules. Collected from `<style>` blocks and external `<link rel="stylesheet">` resources.
3.  **Inline Style Attributes (`Origin::kAuthor`, `is_inline = true`)**: Highest priority in the normal author origin. Extracted directly from an element's `style="..."` attribute (`Element::InlineStyle()`). In Blink’s `CascadePriority`, inline declarations set a dedicated bit situated higher than stylesheet specificity and layer bits, guaranteeing they dominate non-important stylesheet rules regardless of selector specificity.

---

### 3. Property Inheritance Mechanics

Per CSS Cascading 4 §4 (Defaulting), when the cascade yields no winning declaration for a given property on an element, its value is determined by its inheritance classification in `css_properties.json5`:

*   **Inherited Properties (`font-size`, `color`, `text-align`)**:
    If no declaration wins in `CascadeMap`, the property defaults to `inherit`. In Blink, `StyleResolver::InitStyle` initializes the child's `ComputedStyleBuilder` by copying the `InheritedData` pointers directly from the parent element's `ComputedStyle`. If the root element (`<html>`) has no cascaded value, it falls back to the property's initial value.
*   **Non-Inherited Properties (`margin-*`, `padding-*`, `border-*`, `width`, `height`, `display`)**:
    If no declaration wins in `CascadeMap`, the property defaults to `initial`. Blink initializes `NonInheritedData` from a static singleton `ComputedStyle::InitialStyle()`. Even if a parent has `width: 100px` or `border: 1px solid black`, the child receives `width: auto` and `border: none` unless explicitly cascaded on the child (or forced via the `inherit` keyword).

---

### 4. Mathematical Invariants

Let $\mathcal{P}$ be the set of CSS properties, $\mathcal{V}$ be the domain of property values, and $\mathcal{O} = \{\text{UA}, \text{Author}, \text{Inline}\}$ be the totally ordered set of origins with $\text{UA} < \text{Author} < \text{Inline}$.

1.  **Override Dominance of Higher-Priority Layers**:
    For any element $e$, property $p \in \mathcal{P}$, and declaration map $D_e : \mathcal{O} \times \mathcal{P} \rightharpoonup \mathcal{V}$, if $D_e(o_2, p) = \lfloor v_2 \rfloor$ for some origin $o_2$, then for all $o_1 < o_2$, the value $D_e(o_1, p)$ has zero effect on the cascaded value $\text{Cascade}(D_e, p)$. Specifically:
    $$D_e(\text{Inline}, p) = \lfloor v \rfloor \implies \text{Cascade}(D_e, p) = \lfloor v \rfloor$$
2.  **Transitivity of Property Inheritance**:
    For any inherited property $p$ ($\text{is\_inherited}(p) = \top$) and a path of DOM elements $e_0 \to e_1 \to \dots \to e_k$ where $e_{i}$ is the parent of $e_{i+1}$: if no element $e_i$ for $1 \le i \le k$ contains any matching declaration for $p$ across any origin ($\forall o \in \mathcal{O}, D_{e_i}(o, p) = \bot$), then:
    $$\text{ComputedStyle}(e_k, p) = \text{ComputedStyle}(e_0, p)$$
3.  **Determinism of Style Resolution**:
    The style resolution function $f_{\text{resolve}}$ is a pure, total function. Given an identical parent `ComputedStyle` $S_{\text{parent}}$ and an identical set of declarations $D_e$, resolving the style for $e$ always yields the exact same `ComputedStyle` $S_e$:
    $$\forall S_1, S_2.\; S_{\text{parent},1} = S_{\text{parent},2} \land D_{e,1} = D_{e,2} \implies f_{\text{resolve}}(S_{\text{parent},1}, D_{e,1}) = f_{\text{resolve}}(S_{\text{parent},2}, D_{e,2})$$

---

### 5. Rocq / Coq Formalization (`BlinkSimpleCSSCascadeSemantics.v`)

```coq
(** * BlinkSimpleCSSCascadeSemantics.v
    Formal Audit of Chromium Blink Simple CSS Cascade vs CSS Cascading 4 §3/§4 *)

From Coq Require Import Bool.Bool.
From Coq Require Import Init.Nat.
From Coq Require Import Lists.List.
Import ListNotations.

(** ** 1. Properties and Inheritance Classification *)

Inductive CSSProperty : Type :=
  (* Inherited properties *)
  | PropFontSize
  | PropColor
  | PropTextAlign
  (* Non-inherited properties *)
  | PropMargin
  | PropPadding
  | PropBorder
  | PropWidth
  | PropHeight
  | PropDisplay.

Definition is_inherited (p : CSSProperty) : bool :=
  match p with
  | PropFontSize | PropColor | PropTextAlign => true
  | PropMargin | PropPadding | PropBorder
  | PropWidth | PropHeight | PropDisplay => false
  end.

(** Abstract representation of resolved CSS Values *)
Inductive CSSValue : Type :=
  | ValInitial (p : CSSProperty)
  | ValPx (n : nat)
  | ValColorRGB (r g b : nat)
  | ValKeyword (id : nat).

(** ** 2. Cascade Origins and Priority (CascadePriority) *)

Inductive CascadeOrigin : Type :=
  | OriginUA
  | OriginAuthor
  | OriginInline.

Definition origin_priority (o : CascadeOrigin) : nat :=
  match o with
  | OriginUA => 1
  | OriginAuthor => 2
  | OriginInline => 3
  end.

(** ** 3. MatchResult, StyleCascade, and ComputedStyle *)

(** A MatchResult for a single element maps (Origin, Property) to an optional CSSValue *)
Definition MatchResult := CascadeOrigin -> CSSProperty -> option CSSValue.

(** ComputedStyle is a total map from CSSProperty to CSSValue *)
Definition ComputedStyle := CSSProperty -> CSSValue.

(** Initial style singleton (ComputedStyle::InitialStyle()) *)
Definition initial_style : ComputedStyle :=
  fun p => ValInitial p.

(** Blink's StyleCascade resolution for a single property:
    Inline > Author > UA *)
Definition cascade_property (mr : MatchResult) (p : CSSProperty) : option CSSValue :=
  match mr OriginInline p with
  | Some v => Some v
  | None =>
      match mr OriginAuthor p with
      | Some v => Some v
      | None => mr OriginUA p
      end
  end.

(** Defaulting & Inheritance (CSS Cascading 4 §4):
    Combines cascaded value with parent ComputedStyle *)
Definition resolve_property
  (parent_style : option ComputedStyle)
  (mr : MatchResult)
  (p : CSSProperty) : CSSValue :=
  match cascade_property mr p with
  | Some v => v
  | None =>
      if is_inherited p then
        match parent_style with
        | Some ps => ps p
        | None => initial_style p
        end
      else
        initial_style p
  end.

(** Complete StyleResolver::StyleForElement step *)
Definition compute_style
  (parent_style : option ComputedStyle)
  (mr : MatchResult) : ComputedStyle :=
  fun p => resolve_property parent_style mr p.

(** ** 4. Formal Verification of Mathematical Invariants *)

(** Theorem 1a: Inline Style Dominance
    An inline style declaration unconditionally overrides Author and UA declarations. *)
Theorem inline_dominates_author_and_ua :
  forall (parent : option ComputedStyle) (mr : MatchResult) (p : CSSProperty) (v : CSSValue),
    mr OriginInline p = Some v ->
    compute_style parent mr p = v.
Proof.
  intros parent mr p v H_inline.
  unfold compute_style, resolve_property, cascade_property.
  rewrite H_inline.
  reflexivity.
Qed.

(** Theorem 1b: Author Stylesheet Dominance over UA
    In the absence of inline styles, Author rules unconditionally override UA defaults. *)
Theorem author_dominates_ua :
  forall (parent : option ComputedStyle) (mr : MatchResult) (p : CSSProperty) (v : CSSValue),
    mr OriginInline p = None ->
    mr OriginAuthor p = Some v ->
    compute_style parent mr p = v.
Proof.
  intros parent mr p v H_no_inline H_author.
  unfold compute_style, resolve_property, cascade_property.
  rewrite H_no_inline, H_author.
  reflexivity.
Qed.

(** Predicate stating an element has no matched declarations for property [p] *)
Definition no_declarations_for (mr : MatchResult) (p : CSSProperty) : Prop :=
  mr OriginInline p = None /\
  mr OriginAuthor p = None /\
  mr OriginUA p = None.

(** Lemma: Single-step inheritance preservation *)
Lemma inheritance_single_step :
  forall (parent_style : ComputedStyle) (mr : MatchResult) (p : CSSProperty),
    is_inherited p = true ->
    no_declarations_for mr p ->
    compute_style (Some parent_style) mr p = parent_style p.
Proof.
  intros parent_style mr p H_inh [H_in [H_au H_ua]].
  unfold compute_style, resolve_property, cascade_property.
  rewrite H_in, H_au, H_ua, H_inh.
  reflexivity.
Qed.

(** Recursive resolution over a DOM ancestor chain (from child up to root's children) *)
Fixpoint resolve_chain
  (root_style : ComputedStyle)
  (chain : list MatchResult) : ComputedStyle :=
  match chain with
  | [] => root_style
  | mr :: rest => compute_style (Some (resolve_chain root_style rest)) mr
  end.

(** Theorem 2: Transitivity of Property Inheritance across arbitrary DOM depth *)
Theorem inheritance_transitivity :
  forall (root_style : ComputedStyle) (chain : list MatchResult) (p : CSSProperty),
    is_inherited p = true ->
    Forall (fun mr => no_declarations_for mr p) chain ->
    resolve_chain root_style chain p = root_style p.
Proof.
  intros root_style chain p H_inh H_forall.
  induction chain as [| mr rest IH].
  - reflexivity.
  - simpl.
    inversion H_forall as [| ? ? H_head H_tail]; subst.
    rewrite inheritance_single_step; [| exact H_inh | exact H_head].
    apply IH. exact H_tail.
Qed.

(** Theorem 3: Non-inherited Isolation
    Non-inherited properties never read from parent_style when un-cascaded. *)
Theorem non_inherited_isolation :
  forall (ps1 ps2 : ComputedStyle) (mr : MatchResult) (p : CSSProperty),
    is_inherited p = false ->
    no_declarations_for mr p ->
    compute_style (Some ps1) mr p = ValInitial p /\
    compute_style (Some ps1) mr p = compute_style (Some ps2) mr p.
Proof.
  intros ps1 ps2 mr p H_non_inh [H_in [H_au H_ua]].
  unfold compute_style, resolve_property, cascade_property, initial_style.
  rewrite H_in, H_au, H_ua, H_non_inh.
  split; reflexivity.
Qed.

(** Theorem 4: Determinism of Cascade and Style Resolution *)
Theorem cascade_determinism :
  forall (p1 p2 : option ComputedStyle) (mr1 mr2 : MatchResult) (p : CSSProperty),
    (forall o, mr1 o p = mr2 o p) ->
    ( match p1, p2 with
      | Some s1, Some s2 => s1 p = s2 p
      | None, None => True
      | _, _ => False
      end ) ->
    compute_style p1 mr1 p = compute_style p2 mr2 p.
Proof.
  intros p1 p2 mr1 mr2 p H_mr H_parent.
  unfold compute_style, resolve_property, cascade_property.
  repeat rewrite H_mr.
