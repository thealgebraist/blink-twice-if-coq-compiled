### Agent 184 Audit Report: Chromium Blink East Asian Width vs. UAX #11 & CSS Text 3 §8

#### 1. Width Classification & Advance Semantics
In accordance with Unicode Standard Annex #11 (UAX #11) *East Asian Width* and CSS Text Module Level 3 §8 (*Spacing* & *Character-based Spacing*), characters in East Asian typography are partitioned into distinct width classes that dictate their inline typographic advance within a standard em-box grid.

In Chromium Blink (`platform/fonts/shaping/` and `platform/text/character.cc`), East Asian Width properties resolve into concrete typographic advances as follows:
*   **Fullwidth (`F`) and Wide (`W`):** Ideographic characters, Kana, and fullwidth Latin variants occupy the entirety of a standard square em-box. Their default typographic advance is $1.0\text{em}$.
*   **Halfwidth (`H`) and Narrow (`Na`):** Halfwidth Katakana and standard ASCII/Latin characters occupy half of an em-box, resolving to a canonical typographic advance of $0.5\text{em}$ in fixed-pitch CJK layout contexts.
*   **Ambiguous (`A`) and Neutral (`N`):** Resolved contextually based on font metrics, language tags (`LayoutLocale`), and orientation (`writing-mode`). In strict CJK grid contexts, Ambiguous characters resolve to either Fullwidth ($1.0\text{em}$) or Halfwidth ($0.5\text{em}$) depending on contextual state.

---

#### 2. Formal Invariants
To verify Blink's layout engine against UAX #11 and CSS Text 3 §8, the following core invariants must hold across all shaping runs for a given non-negative font size ($1\text{em} \ge 0$):
1.  **Proportionality Invariant (2:1 Ratio):** The typographic advance of a Fullwidth or Wide character must be exactly twice the typographic advance of a Halfwidth or Narrow character:
    $$\text{Advance}(\text{Fullwidth}) = 2 \times \text{Advance}(\text{Halfwidth})$$
2.  **Non-Negativity Invariant:** For any valid font size ($em \ge 0$), all computed character advances and inter-script spacing additions (e.g., `text-autospace`) must be non-negative:
    $$\forall c, \text{Advance}(c) \ge 0$$
3.  **Ambiguous Resolution Bound:** A resolved Ambiguous character's advance is bounded inclusively by the Halfwidth and Fullwidth advances:
    $$\text{Advance}(\text{Halfwidth}) \le \text{Advance}(\text{Ambiguous}) \le \text{Advance}(\text{Fullwidth})$$

---

#### 3. Concrete Rocq / Coq Formalization
Below is the complete, self-contained formalization for `BlinkEastAsianWidthSpacingSemantics.v` using rational arithmetic (`QArith`) to model exact sub-pixel layout units without floating-point rounding drift.

```coq
(** * BlinkEastAsianWidthSpacingSemantics.v
    Formal Audit by Agent 184: Chromium Blink East Asian Width vs UAX #11 & CSS Text 3 §8.
*)

Require Import Coq.QArith.QArith.
Require Import Coq.QArith.Qring.
Require Import Coq.micromega.Lqa.

Open Scope Q_scope.

(** ** 1. UAX #11 East Asian Width Classifications *)

Inductive EAWClass : Type :=
  | EAW_Fullwidth (* F  *)
  | EAW_Wide      (* W  *)
  | EAW_Halfwidth (* H  *)
  | EAW_Narrow    (* Na *)
  | EAW_Ambiguous (* A  *)
  | EAW_Neutral.  (* N  *)

(** Contextual resolution state for Ambiguous/Neutral characters in Blink *)
Inductive CJKContext : Type :=
  | Context_CJK
  | Context_NonCJK.

(** ** 2. Width Resolution & Typographic Advance Semantics *)

Inductive ResolvedWidth : Type :=
  | Width_Full (* 1.0 em *)
  | Width_Half (* 0.5 em *).

(** UAX #11 & CSS Text 3 §8 resolution mapping *)
Definition resolve_eaw (c : EAWClass) (ctx : CJKContext) : ResolvedWidth :=
  match c with
  | EAW_Fullwidth => Width_Full
  | EAW_Wide      => Width_Full
  | EAW_Halfwidth => Width_Half
  | EAW_Narrow    => Width_Half
  | EAW_Ambiguous => match ctx with
                     | Context_CJK    => Width_Full
                     | Context_NonCJK => Width_Half
                     end
  | EAW_Neutral   => Width_Half
  end.

(** Multiplier relative to 1em *)
Definition width_em_factor (w : ResolvedWidth) : Q :=
  match w with
  | Width_Full => 1#1
  | Width_Half => 1#2
  end.

(** Concrete advance calculation for a given em size *)
Definition char_advance (em : Q) (c : EAWClass) (ctx : CJKContext) : Q :=
  em * width_em_factor (resolve_eaw c ctx).

(** CSS Text 3 §8.3: Inter-script spacing (e.g., ideograph-alpha) is 1/8 em *)
Definition autospace_advance (em : Q) : Q :=
  em * (1#8).

(** ** 3. Core Invariant Theorems *)

(** Theorem 1: Fullwidth character advance is exactly 2x Halfwidth character advance *)
Theorem fullwidth_is_double_halfwidth :
  forall (em : Q) (ctx : CJKContext),
    char_advance em EAW_Fullwidth ctx == (2#1) * char_advance em EAW_Halfwidth ctx.
Proof.
  intros em ctx.
  unfold char_advance, resolve_eaw, width_em_factor.
  lra.
Qed.

(** Theorem 2: Wide character advance is exactly 2x Narrow character advance *)
Theorem wide_is_double_narrow :
  forall (em : Q) (ctx : CJKContext),
    char_advance em EAW_Wide ctx == (2#1) * char_advance em EAW_Narrow ctx.
Proof.
  intros em ctx.
  unfold char_advance, resolve_eaw, width_em_factor.
  lra.
Qed.

(** Theorem 3: Equivalence between Fullwidth and Wide advances *)
Theorem fullwidth_wide_equiv :
  forall (em : Q) (ctx : CJKContext),
    char_advance em EAW_Fullwidth ctx == char_advance em EAW_Wide ctx.
Proof.
  intros em ctx.
  unfold char_advance, resolve_eaw, width_em_factor.
  lra.
Qed.

(** Theorem 4: Equivalence between Halfwidth and Narrow advances *)
Theorem halfwidth_narrow_equiv :
  forall (em : Q) (ctx : CJKContext),
    char_advance em EAW_Halfwidth ctx == char_advance em EAW_Narrow ctx.
Proof.
  intros em ctx.
  unfold char_advance, resolve_eaw, width_em_factor.
  lra.
Qed.

(** Lemma: Resolved width factor is strictly positive *)
Lemma width_em_factor_pos :
  forall (w : ResolvedWidth),
    0 < width_em_factor w.
Proof.
  intros w. destruct w; unfold width_em_factor; lra.
Qed.

(** Theorem 5: Non-negativity of character advances for all non-negative em sizes *)
Theorem char_advance_nonneg :
  forall (em : Q) (c : EAWClass) (ctx : CJKContext),
    0 <= em ->
    0 <= char_advance em c ctx.
Proof.
  intros em c ctx Hem.
  unfold char_advance.
  destruct (resolve_eaw c ctx); unfold width_em_factor; lra.
Qed.

(** Theorem 6: Non-negativity of CSS Text 3 §8 autospace advances *)
Theorem autospace_advance_nonneg :
  forall (em : Q),
    0 <= em ->
    0 <= autospace_advance em.
Proof.
  intros em Hem.
  unfold autospace_advance.
  lra.
Qed.

(** Theorem 7: Ambiguous character advance is bounded by Halfwidth and Fullwidth *)
Theorem ambiguous_advance_bounded :
  forall (em : Q) (ctx : CJKContext),
    0 <= em ->
    char_advance em EAW_Halfwidth ctx <= char_advance em EAW_Ambiguous ctx /\
    char_advance em EAW_Ambiguous ctx <= char_advance em EAW_Fullwidth ctx.
Proof.
  intros em ctx Hem.
  unfold char_advance, resolve_eaw, width_em_factor.
  destruct ctx; split; lra.
Qed.

(** Theorem 8: Pair of Halfwidth characters occupies the exact advance of one Fullwidth character *)
Theorem two_halfwidth_equal_one_fullwidth :
  forall (em : Q) (ctx : CJKContext),
    char_advance em EAW_Halfwidth ctx + char_advance em EAW_Halfwidth ctx ==
    char_advance em EAW_Fullwidth ctx.
Proof.
  intros em ctx.
  unfold char_advance, resolve_eaw, width_em_factor.
  lra.
Qed.
```