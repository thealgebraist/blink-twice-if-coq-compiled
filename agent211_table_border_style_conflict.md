### 1. Style Precedence Ranking & Specification Audit

In CSS 2.1 §17.6.2.1 (Border conflict resolution), when two borders of identical width (or governed by the special suppression rules of `hidden` and `none`) meet at an edge in a collapsing border model (`border-collapse: collapse`), the style precedence ranking determines the winning style. Chromium's Blink engine (`CollapsedBorderValue::Precedence` / `CollapsedBorderValue::LessThan`) implements this resolution.

For the subset of border styles under audit (`hidden`, `double`, `solid`, `dashed`, `none`), the style precedence ranking maps each style to a strictly ordered numeric rank:

*   **`hidden` (Rank 5)**: Highest priority. Unconditionally suppresses any conflicting border at that edge, regardless of width.
*   **`double` (Rank 4)**: Highest priority among visible styles.
*   **`solid` (Rank 3)**: Secondary visible priority.
*   **`dashed` (Rank 2)**: Tertiary visible priority (outranks `dotted`, `ridge`, `outset`, `groove`, `inset` in full CSS 2.1).
*   **`none` (Rank 0)**: Lowest priority. Unconditionally yields to any visible border or `hidden`.

---

### 2. Core Invariants

1.  **Maximum Precedence Rank (`resolve_style_max_rank`)**: Given any two conflicting border styles $s_1$ and $s_2$ of equal width (or under style-only conflict resolution), the resolved winning style $s_{win}$ possesses a precedence rank strictly equal to $\max(\text{rank}(s_1), \text{rank}(s_2))$.
2.  **Unconditional Suppression by `hidden` (`hidden_dominates_left`, `hidden_dominates_right`, `hidden_suppresses_border`)**: If either conflicting border has the style `hidden`, the resolved border style is guaranteed to be `hidden`, and the resulting rendered border visibility is unconditionally suppressed (`false`).
3.  **Identity of `none` (`none_yields_left`, `none_yields_right`)**: The `none` style acts as the bottom identity element of the conflict resolution lattice; resolving `none` against any style $s$ always yields $s$.

---

### 3. Rocq / Coq Formalization (`BlinkTableBorderStyleConflictSemantics.v`)

The following file is completely self-contained, requires only the standard library (`Arith`, `Lia`, `Bool`), and compiles with **0 admits**.

```coq
(** * BlinkTableBorderStyleConflictSemantics.v
    Formal Audit of Chromium Blink Table Border Style Conflict Resolution
    against CSS 2.1 Section 17.6.2.1.
    Agent 211 Verification Artifact. *)

From Coq Require Import Arith.Arith.
From Coq Require Import Bool.Bool.
From Coq Require Import micromega.Lia.

(** ** 1. Border Style Representation and Precedence Ranking *)

Inductive BorderStyle : Type :=
  | BS_None   : BorderStyle
  | BS_Dashed : BorderStyle
  | BS_Solid  : BorderStyle
  | BS_Double : BorderStyle
  | BS_Hidden : BorderStyle.

(** Scheme for decidable equality on BorderStyle. *)
Definition border_style_eq_dec (s1 s2 : BorderStyle) : {s1 = s2} + {s1 <> s2}.
Proof.
  decide equality.
Defined.

(** Precedence ranking per specification:
    - hidden : rank 5 (highest)
    - double : rank 4
    - solid  : rank 3
    - dashed : rank 2
    - none   : rank 0 (lowest) *)
Definition style_rank (s : BorderStyle) : nat :=
  match s with
  | BS_Hidden => 5
  | BS_Double => 4
  | BS_Solid  => 3
  | BS_Dashed => 2
  | BS_None   => 0
  end.

(** Injectivity of style_rank: distinct styles have distinct ranks. *)
Lemma style_rank_injective : forall s1 s2 : BorderStyle,
  style_rank s1 = style_rank s2 -> s1 = s2.
Proof.
  intros s1 s2 H.
  destruct s1, s2; simpl in H; try reflexivity; discriminate H.
Qed.

(** ** 2. Conflict Resolution Semantics *)

(** Resolves a style conflict between an existing border [s1] and a candidate
    border [s2]. Following Blink's [CollapsedBorderValue] comparison, if [s1]
    has a rank greater than or equal to [s2], [s1] is retained; otherwise [s2]
    wins. (Since ranks are unique per style, ties only occur when s1 = s2). *)
Definition resolve_style (s1 s2 : BorderStyle) : BorderStyle :=
  if Nat.leb (style_rank s2) (style_rank s1) then s1 else s2.

(** A border is visibly rendered if and only if its resolved style is neither
    [BS_Hidden] nor [BS_None]. *)
Definition is_border_visible (s : BorderStyle) : bool :=
  match s with
  | BS_Hidden => false
  | BS_None   => false
  | _         => true
  end.

(** ** 3. Structural and Algebraic Properties of Resolution *)

Theorem resolve_style_idempotent : forall s : BorderStyle,
  resolve_style s s = s.
Proof.
  intro s. unfold resolve_style.
  rewrite Nat.leb_refl. reflexivity.
Qed.

Theorem resolve_style_commutative : forall s1 s2 : BorderStyle,
  resolve_style s1 s2 = resolve_style s2 s1.
Proof.
  intros s1 s2.
  destruct s1, s2; simpl; reflexivity.
Qed.

Theorem resolve_style_associative : forall s1 s2 s3 : BorderStyle,
  resolve_style (resolve_style s1 s2) s3 = resolve_style s1 (resolve_style s2 s3).
Proof.
  intros s1 s2 s3.
  destruct s1, s2, s3; simpl; reflexivity.
Qed.

(** ** 4. Primary Audit Invariants (CSS 2.1 §17.6.2.1) *)

(** Invariant 1: The winning style always has the maximum precedence rank
    of the two conflicting styles. *)
Theorem resolve_style_max_rank : forall s1 s2 : BorderStyle,
  style_rank (resolve_style s1 s2) = Nat.max (style_rank s1) (style_rank s2).
Proof.
  intros s1 s2.
  unfold resolve_style.
  destruct (Nat.leb_spec (style_rank s2) (style_rank s1)) as [Hle | Hgt].
  - rewrite Nat.max_l; [reflexivity | exact Hle].
  - rewrite Nat.max_r; [reflexivity | lia].
Qed.

(** Corollary: The winning style's rank is at least as large as both inputs. *)
Theorem resolve_style_rank_ge : forall s1 s2 : BorderStyle,
  style_rank s1 <= style_rank (resolve_style s1 s2) /\
  style_rank s2 <= style_rank (resolve_style s1 s2).
Proof.
  intros s1 s2.
  rewrite resolve_style_max_rank.
  split; [apply Nat.le_max_l | apply Nat.le_max_r].
Qed.

(** Invariant 2a: [BS_Hidden] unconditionally dominates any style on the left. *)
Theorem hidden_dominates_left : forall s : BorderStyle,
  resolve_style BS_Hidden s = BS_Hidden.
Proof.
  intro s. destruct s; simpl; reflexivity.
Qed.

(** Invariant 2b: [BS_Hidden] unconditionally dominates any style on the right. *)
Theorem hidden_dominates_right : forall s : BorderStyle,
  resolve_style s BS_Hidden = BS_Hidden.
Proof.
  intro s. destruct s; simpl; reflexivity.
Qed.

(** Invariant 2c: Unconditional border suppression by [BS_Hidden].
    If either conflicting style is [BS_Hidden], the resolved border is
    guaranteed not to be visibly rendered. *)
Theorem hidden_suppresses_border : forall s1 s2 : BorderStyle,
  s1 = BS_Hidden \/ s2 = BS_Hidden ->
  is_border_visible (resolve_style s1 s2) = false.
Proof.
  intros s1 s2 [H1 | H2].
  - subst s1. rewrite hidden_dominates_left. simpl. reflexivity.
  - subst s2. rewrite hidden_dominates_right. simpl. reflexivity.
Qed.

(** Invariant 3a: [BS_None] has the lowest priority and always yields on the left. *)
Theorem none_yields_left : forall s : BorderStyle,
  resolve_style BS_None s = s.
Proof.
  intro s. destruct s; simpl; reflexivity.
Qed.

(** Invariant 3b: [BS_None] has the lowest priority and always yields on the right. *)
Theorem none_yields_right : forall s : BorderStyle,
  resolve_style s BS_None = s.
Proof.
  intro s. destruct s; simpl; reflexivity.
Qed.

(** ** 5. Width-Integrated Conflict Resolution (Full CSS 2.1 §17.6.2.1 Step 1-3) *)

Record CollapsedBorder : Type := mkBorder {
  cb_style : BorderStyle;
  cb_width : nat
}.

(** Computes the effective visual width of a border. Per CSS 2.1, if the style
    is [BS_None] or [BS_Hidden], the effective border width is 0. *)
Definition effective_width (b : CollapsedBorder) : nat :=
  match cb_style b with
  | BS_None   => 0
  | BS_Hidden => 0
  | _         => cb_width b
  end.

(** Full conflict resolution between two borders (Steps 1, 2, and 3 of §17.6.2.1):
    1. If either border has style [BS_Hidden], [BS_Hidden] wins (width 0).
    2. If either border has style [BS_None], the other wins.
    3. Otherwise, the wider border wins; on equal width, higher style rank wins. *)
Definition resolve_border (b1 b2 : CollapsedBorder) : CollapsedBorder :=
  match cb_style b1, cb_style b2 with
  | BS_Hidden, _ => mkBorder BS_Hidden 0
  | _, BS_Hidden => mkBorder BS_Hidden 0
  | BS_None, _   => b2
  | _, BS_None   => b1
  | s1, s2       =>
      if Nat.ltb (cb_width b1) (cb_width b2) then b2
      else if Nat.ltb (cb_width b2) (cb_width b1) then b1
      else mkBorder (resolve_style s1 s2) (cb_width b1)
  end.

(** Theorem: In full border resolution, [BS_Hidden] unconditionally suppresses
    the resulting border regardless of the opposing border's width. *)
Theorem full_hidden_unconditional_suppression : forall b1 b2 : CollapsedBorder,
  cb_style b1 = BS_Hidden \/ cb_style b2 = BS_Hidden ->
  cb_style (resolve_border b1 b2) = BS_Hidden /\
  effective_width (resolve_border b1 b2) = 0 /\
  is_border_visible (cb_style (resolve_border b1 b2)) = false.
Proof.
  intros [s1 w1] [s2 w2] [H1 | H2]; simpl in *.
  - subst s1. simpl. repeat split; reflexivity.
  - subst s2. destruct s1; simpl; repeat split; reflexivity.
Qed.

(** Theorem: When two non-hidden, non-none borders have equal width,
    [resolve_border] reduces exactly to [resolve_style] and maximizes style rank. *)
Theorem equal_width_reduces_to_style_rank : forall s1 s2 w,
  cb_style (resolve_border (mkBorder s1 w) (mkBorder s2 w)) = resolve_style s1 s2.
Proof.
  intros s1 s2 w.
  destruct s1, s2; simpl; try rewrite Nat.ltb_irrefl; simpl; reflexivity.
Qed.
```