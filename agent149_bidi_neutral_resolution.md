## 1. Directional Types in Blink (`BidiParagraph` / `BidiResolver`)

In Chromium's Blink rendering engine, inline bidirectional layout is governed by `BidiParagraph` (in LayoutNG, integrated with ICU's `UBiDi` implementation) and the legacy `BidiResolver` (`third_party/blink/renderer/platform/text/bidi_resolver.h`). Characters are mapped to Unicode Bidirectional Algorithm (UAX #9) character classes (`UCharDirection`), which fall into three primary operational categories during neutral resolution:

*   **`L` (Strong Left-to-Right)**: Includes `U_LEFT_TO_RIGHT` (`L`). Represents scripts such as Latin, Greek, Cyrillic, and CJK characters. Also serves as the resolved post-W1–W7 state for numbers in LTR contexts (`L` after `W7`).
*   **`R` (Strong Right-to-Left)**: Includes `U_RIGHT_TO_LEFT` (`R`) and `U_RIGHT_TO_LEFT_ARABIC` (`AL`, which resolves to `R` at rule W3). Represents scripts such as Hebrew, Arabic, Syriac, and Thaana. per UAX #9 rule N0/N1, European Numbers (`EN`) and Arabic Numbers (`AN`) also act as strong `R` when adjacent to neutrals.
*   **`N` (Neutral and Isolate Formatting)**: Encompasses `U_WHITE_SPACE_NEUTRAL` (`WS`), `U_OTHER_NEUTRAL` (`ON`), `U_SEGMENT_SEPARATOR` (`S`), `U_BLOCK_SEPARATOR` (`B`), and neutral isolate formatting characters (`FSI`, `LRI`, `RLI`, `PDI`). In `BidiResolver` and ICU `ubidi.cpp`, these are normalized to an internal neutral class (`ON` or `BidiClass::N`) prior to executing the N-rules.

---

## 2. Neutral Character Resolution (UAX #9 Rules N1 & N2 / CSS Writing Modes 3 §2)

CSS Writing Modes Level 3 §2 ("Inline Direction and Bidirectionality") normatively references the Unicode Bidirectional Algorithm (UAX #9). After resolving explicit embedding levels (X1–X8), isolating run sequences (X9–X10), and weak types (W1–W7), Blink resolves remaining neutral characters (`N`) within each **Isolating Run Sequence** at a uniform embedding level:

1.  **Rule N0 (Bracket Pairs)**: Paired brackets are resolved first based on the embedding direction and enclosed strong types. Remaining unresolved brackets stay `N`.
2.  **Rule N1 (Bounded Neutral Sequences)**: A contiguous sequence of neutrals (`NI` in UAX #9) bounded on both sides by strong characters of the **same** directionality resolves to that shared strong directionality:
    *   $\text{L} + \text{N}^+ + \text{L} \longrightarrow \text{L} + \text{L}^+ + \text{L}$
    *   $\text{R} + \text{N}^+ + \text{R} \longrightarrow \text{R} + \text{R}^+ + \text{R}$
    *   *(Note: Under UAX #9, start-of-sequence `sos` and end-of-sequence `eos` types—computed from the higher of the adjacent levels—act as synthetic bounding strong types at the boundaries of an isolating run sequence).*
3.  **Rule N2 (Conflicting Strong Boundaries)**: Any remaining contiguous sequence of neutrals (i.e., bounded by $\text{L}$ on one side and $\text{R}$ on the other: $\text{L} + \text{N}^+ + \text{R}$ or $\text{R} + \text{N}^+ + \text{L}$) resolves to the **embedding direction** ($e$) of the current run:
    *   $\text{Even level } (\text{LTR}) \implies e = \text{L}$
    *   $\text{Odd level } (\text{RTL}) \implies e = \text{R}$

---

## 3. Core Invariants in Blink & UAX #9

1.  **Embedding Level Bounds**: Per UAX #9 §3.1 (`BD2`) and ICU's `UBIDI_MAX_EXPLICIT_LEVEL`, explicit embedding levels are strictly bounded within $[0, 125]$ (`max_depth = 125`). During implicit level resolution (Rules I1/I2), a level may temporarily reach $126$ or $127$ for numbers, but the baseline run embedding level fed into N1/N2 always satisfies $0 \le \text{level} \le 125$.
2.  **Parity-to-Direction Mapping**:
    *   $\text{level} \bmod 2 = 0 \iff \text{LTR}$ (`e = L`, visual progression left-to-right).
    *   $\text{level} \bmod 2 = 1 \iff \text{RTL}$ (`e = R`, visual progression right-to-left).
3.  **Completeness (Elimination of Neutrals)**: After N1 and N2 finish executing over an isolating run sequence, no character in the sequence retains the type `N`; every character is strictly `L` or `R`.
4.  **Length & Strong-Type Preservation**: Neutral resolution is a length-preserving map that acts as the identity function on indices originally holding `L` or `R`.

---

## 4. Formal Verification in Rocq/Coq (`BlinkBidiNeutralResolutionSemantics.v`)

Below is a complete, self-contained Rocq/Coq formalization of Blink's UAX #9 N1/N2 neutral resolution pass, its level invariants, and the proofs for `L N+ L -> L L+ L` and `R N+ R -> R R+ R`.

```coq
(** * BlinkBidiNeutralResolutionSemantics.v
    Formal Audit of Chromium Blink BiDi Neutral Resolution (UAX #9 N1/N2 & CSS Writing Modes 3 §2)
    Agent 149 *)

From Coq Require Import Arith PeanoNat Bool List Lia.
Import ListNotations.

(** ** 1. Directional Types & Embedding Levels *)

Inductive BidiType : Type :=
  | L : BidiType (* Strong Left-to-Right *)
  | R : BidiType (* Strong Right-to-Left *)
  | N : BidiType (* Neutral: WS, ON, S, B, Isolates *).

Scheme Equality for BidiType.

Definition Bidi Type_eqb (t1 t2 : BidiType) : bool :=
  match t1, t2 with
  | L, L => true
  | R, R => true
  | N, N => true
  | _, _ => false
  end.

Definition is_strong (t : BidiType) : bool :=
  match t with
  | L | R => true
  | N     => false
  end.

(** UAX #9 BD2: Max explicit embedding level is 125. *)
Definition max_embedding_level : nat := 125.

Record EmbeddingLevel : Type := mkLevel {
  level_val : nat;
  level_bound : level_val <= max_embedding_level
}.

(** Parity invariant: Even levels are LTR (L), Odd levels are RTL (R). *)
Definition embedding_direction (lvl : nat) : BidiType :=
  if Nat.even lvl then L else R.

(** ** 2. Neutral Resolution Semantics (UAX #9 Rules N1 & N2) *)

(** Given the preceding strong type [prev], the following strong type [next],
    and the run's embedding level [lvl], resolve a single Neutral according to N1 & N2. *)
Definition resolve_neutral_type (prev next : BidiType) (lvl : nat) : BidiType :=
  match prev, next with
  | L, L => L (* Rule N1: L N+ L -> L L+ L *)
  | R, R => R (* Rule N1: R N+ R -> R R+ R *)
  | _, _ => embedding_direction lvl (* Rule N2: conflicting strong types -> e *)
  end.

(** Look ahead in the sequence to find the next strong type, defaulting to [eos]
    (end-of-sequence strong type) if only neutrals remain. *)
Fixpoint next_strong (seq : list BidiType) (eos : BidiType) : BidiType :=
  match seq with
  | []      => eos
  | L :: _  => L
  | R :: _  => R
  | N :: xs => next_strong xs eos
  end.

(** Resolve a full isolating run sequence given [prev] (initialized to [sos]),
    [eos], and the run's embedding level [lvl]. *)
Fixpoint resolve_neutrals_aux (seq : list BidiType) (prev eos : BidiType) (lvl : nat) : list BidiType :=
  match seq with
  | []      => []
  | L :: xs => L :: resolve_neutrals_aux xs L eos lvl
  | R :: xs => R :: resolve_neutrals_aux xs R eos lvl
  | N :: xs =>
      let resolved := resolve_neutral_type prev (next_strong xs eos) lvl in
      resolved :: resolve_neutrals_aux xs prev eos lvl
  end.

Definition resolve_neutrals (seq : list BidiType) (sos eos : BidiType) (lvl : nat) : list BidiType :=
  resolve_neutrals_aux seq sos eos lvl.

(** ** 3. Structural & Level Invariants *)

Lemma embedding_direction_is_strong : forall lvl,
  is_strong (embedding_direction lvl) = true.
Proof.
  intros lvl. unfold embedding_direction.
  destruct (Nat.even lvl); reflexivity.
Qed.

Lemma even_level_is_LTR : forall lvl,
  Nat.even lvl = true -> embedding_direction lvl = L.
Proof.
  intros lvl Heven. unfold embedding_direction. rewrite Heven. reflexivity.
Qed.

Lemma odd_level_is_RTL : forall lvl,
  Nat.even lvl = false -> embedding_direction lvl = R.
Proof.
  intros lvl Hodd. unfold embedding_direction. rewrite Hodd. reflexivity.
Qed.

Lemma resolve_neutral_type_is_strong : forall prev next lvl,
  is_strong (resolve_neutral_type prev next lvl) = true.
Proof.
  intros prev next lvl. unfold resolve_neutral_type.
  destruct prev, next; try reflexivity; apply embedding_direction_is_strong.
Qed.

(** Theorem: Length is strictly preserved during neutral resolution. *)
Theorem resolve_neutrals_length : forall seq prev eos lvl,
  length (resolve_neutrals_aux seq prev eos lvl) = length seq.
Proof.
  induction seq as [| x xs IH]; intros prev eos lvl; simpl.
  - reflexivity.
  - destruct x; simpl; f_equal; apply IH.
Qed.

(** Theorem: Completeness (No Neutrals remain after N1/N2 resolution). *)
Theorem resolve_neutrals_no_N : forall seq prev eos lvl,
  forallb is_strong (resolve_neutrals_aux seq prev eos lvl) = true.
Proof.
  induction seq as [| x xs IH]; intros prev eos lvl; simpl.
  - reflexivity.
  - destruct x; simpl.
    + apply IH.
    + apply IH.
    + rewrite resolve_neutral_type_is_strong. simpl. apply IH.
Qed.

(** ** 4. Verification of Rule N1 (L N+ L -> L L+ L and R N+ R -> R R+ R) *)

Lemma next_strong_repeat_N : forall k rest eos,
  next_strong (repeat N k ++ rest) eos = next_strong rest eos.
Proof.
  induction k as [| k' IH]; intros rest eos; simpl.
  - reflexivity.
  - apply IH.
Qed.

Lemma resolve_neutrals_repeat_N : forall k prev eos lvl rest,
  let target := resolve_neutral_type prev (next_strong rest eos) lvl in
  resolve_neutrals_aux (repeat N k ++ rest) prev eos lvl =
  repeat target k ++ resolve_neutrals_aux rest prev eos lvl.
Proof.
  induction k as [| k' IH]; intros prev eos lvl rest target; simpl.
  - reflexivity.
  - rewrite next_strong_repeat_N.
    fold target. f_equal. apply IH.
Qed.

(** Theorem (Rule N1 for L): Any sequence of k neutrals bounded by L (L ++ N^k ++ L)
    resolves to (L ++ L^k ++ L) regardless of embedding level. *)
Theorem rule_N1_L_N_L : forall k tail prev eos lvl,
  resolve_neutrals_aux (L :: repeat N k ++ L :: tail) prev eos lvl =
  L :: repeat L k ++ L :: resolve_neutrals_aux tail L eos lvl.
Proof.
  intros k tail prev eos lvl. simpl.
  f_equal.
  rewrite resolve_neutrals_repeat_N.
  simpl. reflexivity.
Qed.

(** Theorem (Rule N1 for R): Any sequence of k neutrals bounded by R (R ++ N^k ++ R)
    resolves to (R ++ R^k ++ R) regardless of embedding level. *)
Theorem rule_N1_R_N_R : forall k tail prev eos lvl,
  resolve_neutrals_aux (R :: repeat N k ++ R :: tail) prev eos lvl =
  R :: repeat R k ++ R :: resolve_neutrals_aux tail R eos lvl.
Proof.
  intros k tail prev eos lvl. simpl.
  f_equal.
  rewrite resolve_neutrals_repeat_N.
  simpl. reflexivity.
Qed.

(** Corollary: Concrete 3-element cases [L; N; L] -> [L; L; L] and [R; N; R] -> [R; R; R]. *)
Corollary rule_N1_LNL_concrete : forall sos eos lvl,
  resolve_neutrals [L; N; L] sos eos lvl = [L; L; L].
Proof.
  intros. reflexivity.
Qed.

Corollary rule_N1_RNR_concrete : forall sos eos lvl,
  resolve_neutrals [R; N; R] sos eos lvl = [R; R; R].
Proof.
  intros. reflexivity.
Qed.

(** Theorem (Rule N2): A sequence of k neutrals between conflicting strong types
    (L ++ N^k ++ R) resolves the neutrals to the embedding direction (lvl). *)
Theorem rule_N2_L_N_R : forall k tail prev eos lvl,
  resolve_neutrals_aux (L :: repeat N k ++ R :: tail) prev eos lvl =
  L :: repeat (embedding_direction lvl) k ++ R :: resolve_neutrals_aux tail R eos lvl.
Proof.
  intros k tail prev eos lvl. simpl.
  f_equal.
  rewrite resolve_neutrals_repeat_N.
  simpl. reflexivity.
Qed.
```