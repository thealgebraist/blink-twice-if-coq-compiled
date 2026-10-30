### Agent 186 Audit Report: Chromium Blink Font Fallback Chain vs. CSS Fonts Module Level 3 (§5)

In Chromium's Blink rendering engine (primarily located within `third_party/blink/renderer/platform/fonts/font_fallback_list.cc` and `font_fallback_iterator.cc`), font selection and fallback resolve a prioritized list of `font-family` descriptors down to a concrete `SimpleFontData` instance capable of rendering a target Unicode code point $U$.

---

### 1. Fallback Chain Traversal

According to **CSS Fonts Module Level 3 §5 (Font Matching Algorithm)**, the user agent must iterate over the prioritized list of font families specified by the `font-family` property. For a given character $U$:

1. **Family Resolution:** Blink maintains a `FontFallbackList` backed by a `FontDescription` (containing the `FontFamily` linked list). The traversal uses a cursor index $i$ starting at $0$.
2. **Candidate Evaluation:** At index $i$, Blink fetches the `FontData` (either a single `SimpleFontData` or a composite `SegmentedFontData` corresponding to `@font-face` `unicode-range` definitions) via `FontFallbackList::FontDataAt(i)`.
3. **Glyph Coverage Check:** Blink queries whether the candidate font covers character $U$ (`FontData::ContainsCharacter(U)`).
   - **Hit:** If the candidate supports $U$, traversal immediately yields this font.
   - **Miss:** If the candidate does not support $U$, the cursor increments ($i \leftarrow i + 1$) to evaluate the next family in the author-specified list.
4. **System Fallback:** If the end of the author-specified `FontFamily` list is reached without finding a supporting font ($i \ge \text{length}(L)$), Blink transitions to system-level fallback (`FontCache::GetFontDataForCharacter`), ultimately terminating at the platform's Last Resort / System Default font.

---

### 2. Core Invariants

In auditing Blink's `FontFallbackIterator` against CSS Fonts 3 §5, two critical execution invariants must hold:

* **Invariant 1 (Strict Monotonicity of Fallback Index):** 
  During the resolution of a single character $U$ against an immutable `FontFallbackList`, the active family index $i$ strictly increases with each failed probe ($i_{\text{next}} = i_{\text{current}} + 1$). There are no backward jumps or cycles in the fallback chain.
* **Invariant 2 (Guaranteed Termination):** 
  Because the author-specified fallback list $L$ is finite, and the index $i$ monotonically increases bounded by $\text{length}(L)$, the traversal is guaranteed to terminate in at most $\text{length}(L)$ steps. It either returns a matching font from $L$ at some index $i < \text{length}(L)$, or exhausts $L$ ($i = \text{length}(L)$) and deterministically returns the `SystemDefault` font.

---

### 3. Concrete Rocq/Coq Formalization

The following self-contained Rocq (Coq) module formalizes the state machine, traversal semantics, monotonicity, and termination proofs for Blink's font fallback resolution.

#### `BlinkFontFallbackChainSemantics.v`

```coq
(** * BlinkFontFallbackChainSemantics.v
    Formal Audit by Agent 186: Chromium Blink Font Fallback Chain vs CSS Fonts 3 §5 *)

Require Import Coq.Lists.List.
Require Import Coq.Arith.PeanoNat.
Require Import Coq.Arith.Wf_nat.
Require Import Coq.micromega.Lia.
Import ListNotations.

(** ** 1. Domain Definitions *)

(** Unicode Code Point (Uchar32 in Blink) *)
Definition CodePoint := nat.

(** Abstract representation of Blink's SimpleFontData / FontData *)
Record FontData : Type := mkFontData {
  font_id : nat;
  supports_char : CodePoint -> bool
}.

(** A FontFallbackList is an ordered list of candidate fonts *)
Definition FallbackChain := list FontData.

(** The final resolved font: either a matched candidate or the System Default *)
Inductive FallbackResult : Type :=
  | MatchedFont (f : FontData) (idx : nat)
  | SystemDefaultFont.

(** Traversal state tracking the chain, target character, and current index *)
Record FallbackState : Type := mkState {
  chain : FallbackChain;
  target_char : CodePoint;
  current_idx : nat
}.

(** ** 2. Small-Step & Functional Traversal Semantics *)

(** Outcome of a single probe step in FontFallbackIterator *)
Inductive StepResult : Type :=
  | StepContinue (next_state : FallbackState)
  | StepTerminate (res : FallbackResult).

(** Single step of the fallback state machine *)
Definition fallback_step (st : FallbackState) : StepResult :=
  match nth_error (chain st) (current_idx st) with
  | Some font =>
      if supports_char font (target_char st) then
        StepTerminate (MatchedFont font (current_idx st))
      else
        StepContinue (mkState (chain st) (target_char st) (S (current_idx st)))
  | None =>
      StepTerminate SystemDefaultFont
  end.

(** Fuel-based recursive evaluation modeling the complete traversal loop *)
Fixpoint traverse_with_fuel (fuel : nat) (st : FallbackState) : option FallbackResult :=
  match fuel with
  | 0 => None (* Out of fuel *)
  | S fuel' =>
      match fallback_step st with
      | StepTerminate res => Some res
      | StepContinue next_st => traverse_with_fuel fuel' next_st
      end
  end.

(** Top-level Blink Font Fallback Resolver *)
Definition resolve_font (L : FallbackChain) (u : CodePoint) : option FallbackResult :=
  let init_state := mkState L u 0 in
  traverse_with_fuel (S (length L)) init_state.

(** ** 3. Audit Theorems and Invariants *)

(** *** Invariant 1: Fallback Index Monotonicity
    Whenever the traversal does not terminate in the current step, the fallback 
    index strictly increases. *)
Theorem fallback_index_strictly_monotonic :
  forall (st next_st : FallbackState),
    fallback_step st = StepContinue next_st ->
    current_idx st < current_idx next_st /\
    chain next_st = chain st /\
    target_char next_st = target_char st.
Proof.
  intros st next_st Hstep.
  unfold fallback_step in Hstep.
  destruct (nth_error (chain st) (current_idx st)) as [font|] eqn:Hnth; [|discriminate].
  destruct (supports_char font (target_char st)) eqn:Hsup; [discriminate|].
  inversion Hstep; subst; clear Hstep.
  simpl. split; [lia | split; reflexivity].
Qed.

(** Helper Lemma: Sufficient fuel guarantees termination *)
Lemma traverse_fuel_sufficient :
  forall (fuel : nat) (st : FallbackState),
    length (chain st) - current_idx st < fuel ->
    exists (res : FallbackResult), traverse_with_fuel fuel st = Some res.
Proof.
  induction fuel as [|fuel' IH]; intros st Hbound.
  - lia. (* Contradiction: nat cannot be strictly less than 0 *)
  - simpl. unfold fallback_step.
    destruct (nth_error (chain st) (current_idx st)) as [font|] eqn:Hnth.
    + destruct (supports_char font (target_char st)) eqn:Hsup.
      * exists (MatchedFont font (current_idx st)). reflexivity.
      * assert (Hlen : current_idx st < length (chain st)).
        { apply nth_error_Some. rewrite Hnth. discriminate. }
        apply IH. simpl. lia.
    + exists SystemDefaultFont. reflexivity.
Qed.

(** *** Invariant 2a: Total Termination
    For any finite fallback chain and character U, resolve_font never diverges 
    (always returns Some result). *)
Theorem fallback_always_terminates :
  forall (L : FallbackChain) (u : CodePoint),
    exists (res : FallbackResult), resolve_font L u = Some res.
Proof.
  intros L u.
  unfold resolve_font.
  apply traverse_fuel_sufficient.
  simpl. lia.
Qed.

(** *** Invariant 2b: Soundness of Resolution (CSS Fonts 3 §5 Compliance)
    Any resolved result is either:
    (1) A font from the chain at index `idx` that supports `u`, where all prior 
        fonts `< idx` failed to support `u` (First-Match Semantics).
    (2) The SystemDefaultFont, meaning no font in the chain supports `u`. *)

Lemma traverse_soundness_general :
  forall (fuel : nat) (st : FallbackState) (res : FallbackResult),
    traverse_with_fuel fuel st = Some res ->
    (forall k font, k < current_idx st -> nth_error (chain st) k = Some font ->
       supports_char font (target_char st) = false) ->
    match res with
    | MatchedFont f idx =>
        nth_error (chain st) idx = Some f /\
        supports_char f (target_char st) = true /\
        (forall k font, k < idx -> nth_error (chain st) k = Some font ->
           supports_char font (target_char st) = false)
    | SystemDefaultFont =>
        forall k font, nth_error (chain st) k = Some font ->
          supports_char font (target_char st) = false
    end.
Proof.
  induction fuel as [|fuel' IH]; intros st res Htrav Hprior.
  - simpl in Htrav. discriminate.
  - simpl in Htrav. unfold fallback_step in Htrav.
    destruct (nth_error (chain st) (current_idx st)) as [font|] eqn:Hnth.
    + destruct (supports_char font (target_char st)) eqn:Hsup.
      * inversion Htrav; subst; clear Htrav.
        split; [exact Hnth | split; [exact Hsup | exact Hprior]].
      * apply IH in Htrav.
        -- simpl in Htrav. exact Htrav.
        -- simpl. intros k f' Hk Hnth'.
           assert (k < current_idx st \/ k = current_idx st) as [Hlt | Heq] by lia.
           ++ apply Hprior with (k := k); assumption.
           ++ subst k. rewrite Hnth in Hnth'. inversion Hnth'; subst. exact Hsup.
    + inversion Htrav; subst; clear Htrav.
      intros k font Hnth'.
      assert (Hlen : current_idx st >= length (chain st)).
      { apply nth_error_None. exact Hnth. }
      assert (Hklen : k < length (chain st)).
      { apply nth_error_Some. rewrite Hnth'. discriminate. }
      apply Hprior with (k := k); [lia | exact Hnth'].
Qed.

Theorem css_fonts_3_section_5_correctness :
  forall (L : FallbackChain) (u : CodePoint) (res : FallbackResult),
    resolve_font L u = Some res ->
    match res with
    | MatchedFont f idx =>
        nth_error L idx = Some f /\
        supports_char f u = true /\
        (forall k font, k < idx -> nth_error L k = Some font -> supports_char font u = false)
    | SystemDefaultFont =>
        forall k font, nth_error L k = Some font -> supports_char font u = false
    end.
Proof.
  intros L u res Hres.
  unfold resolve_font in Hres.
  pose proof (traverse_soundness_general (S (length L)) (mkState L u 0) res Hres) as Hsound.
  simpl in Hsound.
  apply Hsound.
  intros k font Hk. lia.
Qed.
```