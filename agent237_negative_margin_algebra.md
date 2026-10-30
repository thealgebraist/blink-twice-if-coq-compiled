### 1. Collapsed Margin Algebra (`sum = pos + neg`)

Under **CSS 2.1 §8.3.1 (Collapsing margins)**, the normative rules for computing the collapsed margin value across a set of adjoining margins $M = \{m_1, m_2, \dots, m_k\}$ are:
1. If all $m_i \ge 0$, the collapsed margin is $\max_i(m_i)$.
2. If all $m_i \le 0$, the collapsed margin is $\min_i(m_i)$ (i.e., the most negative value, having the largest absolute magnitude).
3. If $M$ contains both positive and negative margins, the collapsed margin is the algebraic sum of the largest positive margin and the most negative margin.

Chromium Blink’s layout engine (specifically within `MarginStrut` in LayoutNG) implements this specification via a two-accumulator algebra over fixed-point `LayoutUnit` integers:
* **`positive_margin` ($\text{pos}$):** Initialized to $0$. When collapsing a margin $m > 0$, it updates via $\text{pos}' = \max(\text{pos}, m)$.
* **`negative_margin` ($\text{neg}$):** Initialized to $0$. When collapsing a margin $m < 0$, it updates via $\text{neg}' = \min(\text{neg}, m)$.
* **`Sum()` ($\text{sum}$):** Resolved when the margin strut ends, calculated directly as:
  $$\text{sum} = \text{pos} + \text{neg}$$

Because $0$ acts as the identity element for addition and as the floor/ceiling for $\max$/$\min$ respectively, this unified state machine satisfies all three normative clauses of CSS 2.1 §8.3.1 simultaneously without branching on whether positive or negative margins were previously observed.

---

### 2. Invariant Analysis

Let the state of the `MarginStrut` be the pair $(\text{pos}, \text{neg}) \in \mathbb{Z} \times \mathbb{Z}$.

#### State Sign Invariant
At initialization, $\text{pos} = 0 \ge 0$ and $\text{neg} = 0 \le 0$. 
For any incoming margin $m \in \mathbb{Z}$:
* If $m \ge 0$, $\max(\text{pos}, m) \ge \text{pos} \ge 0$, while $\text{neg}$ remains unchanged ($\le 0$).
* If $m < 0$, $\min(\text{neg}, m) \le \text{neg} \le 0$, while $\text{pos}$ remains unchanged ($\ge 0$).

By induction over any finite list of margins, the state invariant $\text{pos} \ge 0 \land \text{neg} \le 0$ holds universally.

#### Collapsed Sum Bounding Invariant
Given the state invariant $\text{pos} \ge 0$ and $\text{neg} \le 0$:
1. **Lower Bound ($\text{neg} \le \text{sum}$):**
   Since $\text{pos} \ge 0$, adding $\text{neg}$ to both sides of the inequality yields:
   $$0 + \text{neg} \le \text{pos} + \text{neg} \implies \text{neg} \le \text{sum}$$
2. **Upper Bound ($\text{sum} \le \text{pos}$):**
   Since $\text{neg} \le 0$, adding $\text{pos}$ to both sides of the inequality yields:
   $$\text{pos} + \text{neg} \le \text{pos} + 0 \implies \text{sum} \le \text{pos}$$

Combining both bounds establishes the primary algebraic safety property:
$$\text{pos} \ge 0 \land \text{neg} \le 0 \implies \text{neg} \le \text{pos} + \text{neg} \le \text{pos}$$
In fixed-point hardware arithmetic (`LayoutUnit`), this guarantees that the final resolution `pos + neg` can never overflow or underflow the representation bounds if `pos` and `neg` are valid `LayoutUnit` values of opposite signs.

---

### 3. Formal Verification in Rocq / Coq

Below is the complete, self-contained formalization for `BlinkNegativeMarginAlgebraSemantics.v` using `ZArith` and `Lia`, containing **0 admits**.

```coq
(** 
  File: BlinkNegativeMarginAlgebraSemantics.v
  Audit: Agent 237 - Chromium Blink Negative Margin Algebra vs CSS 2.1 §8.3.1
*)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** * 1. Blink MarginStrut State and Core Algebra *)

Record MarginStrut : Type := mkMarginStrut {
  pos : Z;
  neg : Z
}.

Definition empty_strut : MarginStrut :=
  mkMarginStrut 0 0.

(** Blink MarginStrut::Sum() implementation: sum = pos + neg *)
Definition collapsed_sum (s : MarginStrut) : Z :=
  (pos s) + (neg s).

(** Blink MarginStrut::Append(LayoutUnit value) implementation *)
Definition append_margin (s : MarginStrut) (m : Z) : MarginStrut :=
  if Z_lt_dec m 0 then
    mkMarginStrut (pos s) (Z.min (neg s) m)
  else
    mkMarginStrut (Z.max (pos s) m) (neg s).

Definition collapse_list (margins : list Z) : MarginStrut :=
  fold_left append_margin margins empty_strut.

(** * 2. Algebraic & Sign Invariants *)

Definition wf_strut (s : MarginStrut) : Prop :=
  pos s >= 0 /\ neg s <= 0.

Theorem empty_strut_wf : wf_strut empty_strut.
Proof.
  unfold wf_strut, empty_strut; simpl; lia.
Qed.

Theorem append_preserves_wf : forall (s : MarginStrut) (m : Z),
  wf_strut s -> wf_strut (append_margin s m).
Proof.
  intros [p n] m [Hp Hn].
  unfold append_margin, wf_strut in *; simpl in *.
  destruct (Z_lt_dec m 0); simpl; lia.
Qed.

Theorem fold_append_preserves_wf : forall (margins : list Z) (s : MarginStrut),
  wf_strut s -> wf_strut (fold_left append_margin margins s).
Proof.
  induction margins as [| m rest IH]; intros s Hwf; simpl.
  - exact Hwf.
  - apply IH. apply append_preserves_wf. exact Hwf.
Qed.

Theorem collapse_list_wf : forall (margins : list Z),
  wf_strut (collapse_list margins).
Proof.
  intros margins.
  unfold collapse_list.
  apply fold_append_preserves_wf.
  apply empty_strut_wf.
Qed.

(** * 3. Primary Bounding Invariant: pos >= 0 /\ neg <= 0 -> neg <= sum <= pos *)

Theorem collapsed_sum_bounds_explicit : forall (p n : Z),
  p >= 0 -> n <= 0 -> n <= p + n <= p.
Proof.
  intros p n Hp Hn.
  lia.
Qed.

Theorem strut_collapsed_sum_bounds : forall (s : MarginStrut),
  wf_strut s -> neg s <= collapsed_sum s <= pos s.
Proof.
  intros [p n] [Hp Hn].
  unfold collapsed_sum; simpl in *.
  lia.
Qed.

Theorem list_collapsed_sum_bounds : forall (margins : list Z),
  let s := collapse_list margins in
  neg s <= collapsed_sum s <= pos s.
Proof.
  intros margins s.
  apply strut_collapsed_sum_bounds.
  apply collapse_list_wf.
Qed.

(** * 4. Monotonicity & Idempotence of Margin Accumulation *)

Theorem append_monotonic_bounds : forall (s : MarginStrut) (m : Z),
  pos s <= pos (append_margin s m) /\ neg (append_margin s m) <= neg s.
Proof.
  intros [p n] m.
  unfold append_margin; simpl.
  destruct (Z_lt_dec m 0); simpl; lia.
Qed.

Theorem append_zero_identity : forall (s : MarginStrut),
  wf_strut s -> append_margin s 0 = s.
Proof.
  intros [p n] [Hp Hn].
  unfold append_margin; simpl in *.
  destruct (Z_lt_dec 0 0) as [Hlt | Hge].
  - lia.
  - f_equal; lia.
Qed.

Theorem append_idempotent : forall (s : MarginStrut) (m : Z),
  append_margin (append_margin s m) m = append_margin s m.
Proof.
  intros [p n] m.
  unfold append_margin; simpl.
  destruct (Z_lt_dec m 0); simpl; f_equal; lia.
Qed.

Theorem append_commutative : forall (s : MarginStrut) (m1 m2 : Z),
  append_margin (append_margin s m1) m2 = append_margin (append_margin s m2) m1.
Proof.
  intros [p n] m1 m2.
  unfold append_margin; simpl.
  destruct (Z_lt_dec m1 0); destruct (Z_lt_dec m2 0); simpl; f_equal; lia.
Qed.

(** * 5. Equivalence to CSS 2.1 §8.3.1 Normative Specification *)

(** CSS 2.1 §8.3.1 defines collapsed margin as the sum of the maximum of 
    non-negative margins (defaulting to 0) and the minimum of non-positive 
    margins (defaulting to 0). *)

Fixpoint css21_max_pos (margins : list Z) : Z :=
  match margins with
  | [] => 0
  | m :: rest => if Z_lt_dec m 0 then css21_max_pos rest else Z.max m (css21_max_pos rest)
  end.

Fixpoint css21_min_neg (margins : list Z) : Z :=
  match margins with
  | [] => 0
  | m :: rest => if Z_lt_dec m 0 then Z.min m (css21_min_neg rest) else css21_min_neg rest
  end.

Definition css21_collapsed_margin (margins : list Z) : Z :=
  (css21_max_pos margins) + (css21_min_neg margins).

Lemma fold_append_characterization : forall (margins : list Z) (p n : Z),
  fold_left append_margin margins (mkMarginStrut p n) =
  mkMarginStrut (Z.max p (css21_max_pos margins)) (Z.min n (css21_min_neg margins)).
Proof.
  induction margins as [| m rest IH]; intros p n; simpl.
  - f_equal; [pose proof (css21_max_pos []) | pose proof (css21_min_neg [])]; simpl in *.
    (* Wait: for base case [], css21_max_pos [] = 0, so Z.max p 0 = p only if p >= 0.
       Let's strengthen the lemma with p >= 0 and n <= 0. *)
Abort.

Lemma css21_max_pos_nonneg : forall (margins : list Z),
  css21_max_pos margins >= 0.
Proof.
  induction margins as [| m rest IH]; simpl.
  - lia.
  - destruct (Z_lt_dec m 0); lia.
Qed.

Lemma css21_min_neg_nonpos : forall (margins : list Z),
  css21_min_neg margins <= 0.
Proof.
  induction margins as [| m rest IH]; simpl.
  - lia.
  - destruct (Z_lt_dec m 0); lia.
Qed.

Lemma fold_append_characterization : forall (margins : list Z) (p n : Z),
  p >= 0 -> n <= 0 ->
  fold_left append_margin margins (mkMarginStrut p n) =
  mkMarginStrut (Z.max p (css21_max_pos margins)) (Z.min n (css21_min_neg margins)).
Proof.
  induction margins as [| m rest IH]; intros p n Hp Hn; simpl.
  - f_equal; lia.
  - unfold append_margin at 2; simpl.
    destruct (Z_lt_dec m 0).
    + rewrite IH by lia.
      f_equal; lia.
    + rewrite IH by lia.
      f_equal; lia.
Qed.

(** Final Audit Theorem: Blink's MarginStrut algebra exactly implements CSS 2.1 §8.3.1 *)
Theorem blink_matches_css21_spec : forall (margins : list Z),
  collapsed_sum (collapse_list margins) = css21_collapsed_margin margins.
Proof.
  intros margins.
  unfold collapse_list, empty_strut, collapsed_sum, css21_collapsed_margin.
  rewrite fold_append_characterization by lia.
  simpl.
  pose proof (css21_max_pos_nonneg margins).
  pose proof (css21_min_neg_nonpos margins).
  lia.
Qed.
```