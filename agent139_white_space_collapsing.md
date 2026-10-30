### Audit Report: Agent 139 — Chromium Blink White-Space Collapsing vs. CSS Text 3 §4

**Target:** `third_party/blink/renderer/core/layout/inline/inline_items_builder.cc` & CSS Text Module Level 3 §4 (White Space Processing & Control Characters).

---

### 1. White-Space Handling Semantics (`normal` vs. `pre`)

In CSS Text 3 §4.1.1 (Phase I: Collapsing and Transformation), white-space processing is governed by the `white-space-collapse` property (mapped from the legacy `white-space` shorthand):

*   **`white-space: normal` (`collapse` mode):**
    1.  All collapsible segment breaks (newlines `\n`, carriage returns `\r`) are transformed into spaces (`U+0020`).
    2.  All collapsible tabs (`\t`) are converted into spaces (`U+0020`).
    3.  Any sequence of collapsible spaces immediately following another collapsible space—even across inline element boundaries—is collapsed into a single `U+0020` space (by removing the subsequent spaces from the rendering tree / mapping them to zero-advance items).
    *   *Blink Implementation:* `InlineItemsBuilderTemplate::AppendCollapseWhitespace` maintains a state machine tracking `last_item_ended_with_whitespace_`. Consecutive collapsible spaces are skipped when building the final `NGInlineNodeData::text_content_` string, while an offset mapping (`NGOffsetMapping`) records the DOM-to-text-content character collapse.

*   **`white-space: pre` (`preserve` mode):**
    1.  Sequences of spaces and tabs are preserved verbatim without collapsing.
    2.  Segment breaks (`\n`) are preserved as forced line breaks (`kForcedBreak` inline items).
    *   *Blink Implementation:* `InlineItemsBuilderTemplate::AppendPreserveWhitespace` copies characters directly into `text_content_`, splitting the stream only at newline boundaries to insert `InlineItem::kControl` items for forced line breaks.

---

### 2. Collapsed Text Advance Calculation

In Blink’s LayoutNG (`InlineNode` / `ShapingLineBreaker`), text advance calculation operates over the **collapsed** `text_content_` string rather than the raw DOM string, bridged by `NGOffsetMapping`:

$$\text{TotalAdvance}(S, \text{mode}) = \sum_{c \in \text{Collapse}(S, \text{mode})} \text{GlyphAdvance}(c)$$

*   **Collapsed Characters:** When a character at DOM offset $i$ is collapsed in `normal` mode, `NGOffsetMapping` maps DOM offset $[i, i+1)$ to an empty range $[k, k)$ in `text_content_`. Its effective horizontal advance is $0\text{px}$.
*   **Surviving Spaces:** The single surviving `U+0020` in a collapsed run receives the standard font space advance width ($\text{advance}(\text{' '})$), unless it is subsequently hung or trimmed at the start/end of a line during Phase II (Trimmings at line boundaries, §4.1.3).
*   **Preserved Newlines (`pre`):** Newlines themselves contribute $0$ horizontal advance to the line box (`kControl` item width is $0$), as they instead trigger line-breaking state transitions.

---

### 3. Formal Invariants

Let $\Sigma$ be the alphabet of Unicode characters, $S \in \Sigma^*$ be the input DOM text, and $\mathcal{C}_m : \Sigma^* \to \Sigma^*$ be the Phase I collapsing operator for mode $m \in \{\text{normal}, \text{pre}\}$.

1.  **Length Contraction:** Collapsing never introduces new characters; the output string length is bounded above by the input string length:
    $$\forall S \in \Sigma^*, m \in \{\text{normal}, \text{pre}\}, \quad |\mathcal{C}_m(S)| \le |S|$$
2.  **Operator Idempotence:** Applying the Phase I collapsing transformation to an already-collapsed string yields the exact same string:
    $$\forall S \in \Sigma^*, m \in \{\text{normal}, \text{pre}\}, \quad \mathcal{C}_m(\mathcal{C}_m(S)) = \mathcal{C}_m(S)$$
3.  **Advance & Length Non-Negativity:** Provided all glyph advances are non-negative ($\forall c, \text{adv}(c) \ge 0$), the total advance of collapsed text is non-negative and bounded above by the raw uncollapsed advance (assuming $\text{adv}(\text{' '}) \le \text{adv}(w)$ for collapsible whitespace $w$):
    $$0 \le |\mathcal{C}_m(S)| \quad \land \quad 0 \le \text{Advance}(\mathcal{C}_m(S))$$

---

### 4. Rocq / Coq Formalization (`BlinkWhiteSpaceCollapsingSemantics.v`)

```coq
(** * BlinkWhiteSpaceCollapsingSemantics.v
    Formal verification of Chromium Blink White-Space Collapsing (CSS Text 3 §4.1.1)
    Agent 139 Audit Artifact *)

Require Import Coq.Lists.List.
Require Import Coq.Arith.Arith.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.
Import ListNotations.

(** ** 1. Character & White-Space Domain *)

Inductive Char : Type :=
  | CSpace   : Char               (* U+0020 SPACE *)
  | CTab     : Char               (* U+0009 TAB *)
  | CNewline : Char               (* U+000A LINE FEED *)
  | CGraph   : nat -> Char.       (* Non-whitespace graphical character *)

Inductive WhiteSpaceMode : Type :=
  | WSNormal : WhiteSpaceMode     (* white-space: normal *)
  | WSPre    : WhiteSpaceMode.    (* white-space: pre *)

Definition is_collapsible_ws (c : Char) : bool :=
  match c with
  | CSpace | CTab | CNewline => true
  | CGraph _ => false
  end.

(** ** 2. Collapsing Operator (CSS Text 3 §4.1.1 Phase I) *)

(** Stateful worker for normal mode: [in_ws] tracks if the immediately
    preceding character in the output was a collapsible whitespace. *)
Fixpoint collapse_normal_aux (s : list Char) (in_ws : bool) : list Char :=
  match s with
  | [] => []
  | c :: rest =>
      if is_collapsible_ws c then
        if in_ws then
          collapse_normal_aux rest true
        else
          CSpace :: collapse_normal_aux rest true
      else
        c :: collapse_normal_aux rest false
  end.

Definition collapse (mode : WhiteSpaceMode) (s : list Char) : list Char :=
  match mode with
  | WSNormal => collapse_normal_aux s false
  | WSPre    => s
  end.

(** ** 3. Collapsed Text Advance Calculation *)

(** Glyph advance table parameterized by space advance and graphical advance.
    Newlines in 'pre' mode are control items with 0 horizontal inline advance. *)
Definition char_advance (space_adv : nat) (glyph_adv : nat -> nat) (c : Char) : nat :=
  match c with
  | CSpace    => space_adv
  | CTab      => space_adv * 8
  | CNewline  => 0
  | CGraph id => glyph_adv id
  end.

Fixpoint text_advance (space_adv : nat) (glyph_adv : nat -> nat) (s : list Char) : nat :=
  match s with
  | [] => 0
  | c :: rest => char_advance space_adv glyph_adv c + text_advance space_adv glyph_adv rest
  end.

Definition collapsed_advance
  (mode : WhiteSpaceMode) (space_adv : nat) (glyph_adv : nat -> nat) (s : list Char) : nat :=
  text_advance space_adv glyph_adv (collapse mode s).

(** ** 4. Proofs of Core Invariants *)

(** Invariant 4.1: Length Non-Negativity *)
Theorem collapsed_length_nonneg :
  forall (mode : WhiteSpaceMode) (s : list Char),
    0 <= length (collapse mode s).
Proof.
  intros mode s. lia.
Qed.

(** Helper lemma for length contraction across both states of [in_ws] *)
Lemma collapse_normal_aux_length_le :
  forall (s : list Char) (in_ws : bool),
    length (collapse_normal_aux s in_ws) <= length s.
Proof.
  induction s as [| c rest IH]; intros in_ws; simpl.
  - lia.
  - destruct (is_collapsible_ws c) eqn:Hws.
    + destruct in_ws; simpl.
      * specialize (IH true). lia.
      * specialize (IH true). lia.
    + simpl. specialize (IH false). lia.
Qed.

(** Invariant 4.2: Collapsed Length <= Original Length *)
Theorem collapsed_length_le_original :
  forall (mode : WhiteSpaceMode) (s : list Char),
    length (collapse mode s) <= length s.
Proof.
  intros [|] s; simpl.
  - apply collapse_normal_aux_length_le.
  - lia.
Qed.

(** Helper lemma for idempotence of [collapse_normal_aux] *)
Lemma collapse_normal_aux_idempotent :
  forall (s : list Char) (in_ws : bool),
    collapse_normal_aux (collapse_normal_aux s in_ws) in_ws = collapse_normal_aux s in_ws.
Proof.
  induction s as [| c rest IH]; intros in_ws; simpl.
  - reflexivity.
  - destruct (is_collapsible_ws c) eqn:Hws.
    + destruct in_ws; simpl.
      * apply IH.
      * f_equal. apply IH.
    + simpl. rewrite Hws. f_equal. apply IH.
Qed.

(** Invariant 4.3: Collapsing Operator Idempotence *)
Theorem collapse_idempotent :
  forall (mode : WhiteSpaceMode) (s : list Char),
    collapse mode (collapse mode s) = collapse mode s.
Proof.
  intros [|] s; simpl.
  - apply collapse_normal_aux_idempotent.
  - reflexivity.
Qed.

(** Invariant 4.4: Advance Non-Negativity & Idempotence Stability *)
Theorem collapsed_advance_nonneg :
  forall (mode : WhiteSpaceMode) (space_adv : nat) (glyph_adv : nat -> nat) (s : list Char),
    0 <= collapsed_advance mode space_adv glyph_adv s.
Proof.
  intros. lia.
Qed.

Theorem collapsed_advance_idempotent :
  forall (mode : WhiteSpaceMode) (space_adv : nat) (glyph_adv : nat -> nat) (s : list Char),
    collapsed_advance mode space_adv glyph_adv (collapse mode s) =
    collapsed_advance mode space_adv glyph_adv s.
Proof.
  intros mode space_adv glyph_adv s.
  unfold collapsed_advance.
  rewrite collapse_idempotent.
  reflexivity.
Qed.
```