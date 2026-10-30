### Audit Report: Agent 264 — Chromium Blink Font-Weight Normalization vs CSS Fonts 4 §5

#### 1. Normalization Semantics
According to **CSS Fonts Module Level 4, §5 (Font Weight: the `font-weight` property)**, absolute font weights accept `<number [1,1000]>`. Values less than `1` or greater than `1000` are invalid at parse time, or—when computed via `calc()` or passed through internal engine interfaces—must be clamped to the closed interval `[1, 1000]`.

In **Chromium Blink** (`third_party/blink/renderer/platform/fonts/font_selection_types.h` and `css_parsing_utils.cc`), font weight normalization enforces this boundary condition via hard clamping:

$$\text{NormalizeWeight}(w) = \text{clamp}(1, 1000, w) = \min(1000, \max(1, w))$$

Where:
* Minimum legal font weight ($W_{\min}$) = $1$
* Maximum legal font weight ($W_{\max}$) = $1000$
* If $w < 1$, the normalized weight resolves to $1$.
* If $w > 1000$, the normalized weight resolves to $1000$.
* Otherwise, the weight $w$ is preserved unchanged.

---

#### 2. Verified Invariants
The formalization establishes the following core invariants for Blink's font-weight clamping mechanism over integer representations ($\mathbb{Z}$, mapping directly to fixed-point and integer paths in Blink):

1. **Range Soundness (`clamp_weight_bounds`):** For any arbitrary input weight $w \in \mathbb{Z}$, the normalized output always satisfies $1 \le \text{clamp\_weight}(w) \le 1000$.
2. **Valid-Input Identity (`clamp_weight_identity`):** For any input weight $w$ already residing within the valid CSS Fonts 4 range $[1, 1000]$, normalization acts as an identity function: $\text{clamp\_weight}(w) = w$.
3. **Idempotence (`clamp_weight_idempotent`):** Normalizing an already normalized weight yields no further change: $\text{clamp\_weight}(\text{clamp\_weight}(w)) = \text{clamp\_weight}(w)$.
4. **Monotonicity (`clamp_weight_monotonic`):** Normalization preserves ordering: $w_1 \le w_2 \implies \text{clamp\_weight}(w_1) \le \text{clamp\_weight}(w_2)$.

---

#### 3. Concrete Rocq / Coq Formalization (`BlinkFontWeightClampingSemantics.v`)

The following file compiles cleanly in Rocq/Coq (8.16+) with **0 admits**.

```coq
(** * BlinkFontWeightClampingSemantics.v
    Audit Agent 264: Chromium Blink Font-Weight Normalization vs CSS Fonts 4 §5.
    Formal verification of clamp(1, 1000, w) semantics and invariants. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.

Open Scope Z_scope.

Section BlinkFontWeightClamping.

  (** CSS Fonts 4 §5 Constants *)
  Definition kMinFontWeight : Z := 1.
  Definition kMaxFontWeight : Z := 1000.

  (** General clamp combinator: clamp(min_val, max_val, x) *)
  Definition clamp (min_val max_val x : Z) : Z :=
    Z.min max_val (Z.max min_val x).

  (** Chromium Blink Font-Weight Normalization: clamp(1, 1000, w) *)
  Definition clamp_weight (w : Z) : Z :=
    clamp kMinFontWeight kMaxFontWeight w.

  (** Predicate defining valid CSS Fonts 4 §5 font-weight domain [1, 1000] *)
  Definition is_valid_font_weight (w : Z) : Prop :=
    kMinFontWeight <= w <= kMaxFontWeight.

  (** Invariant 1: Clamped weight is always within [1, 1000]. *)
  Theorem clamp_weight_bounds : forall (w : Z),
    is_valid_font_weight (clamp_weight w).
  Proof.
    intros w.
    unfold is_valid_font_weight, clamp_weight, clamp, kMinFontWeight, kMaxFontWeight.
    lia.
  Qed.

  (** Invariant 2: Identity on values already within [1, 1000]. *)
  Theorem clamp_weight_identity : forall (w : Z),
    is_valid_font_weight w ->
    clamp_weight w = w.
  Proof.
    intros w Hvalid.
    unfold is_valid_font_weight, clamp_weight, clamp, kMinFontWeight, kMaxFontWeight in *.
    lia.
  Qed.

  (** Auxiliary Invariant 3: Clamping is idempotent. *)
  Theorem clamp_weight_idempotent : forall (w : Z),
    clamp_weight (clamp_weight w) = clamp_weight w.
  Proof.
    intros w.
    apply clamp_weight_identity.
    apply clamp_weight_bounds.
  Qed.

  (** Auxiliary Invariant 4: Clamping is monotonic (order-preserving). *)
  Theorem clamp_weight_monotonic : forall (w1 w2 : Z),
    w1 <= w2 ->
    clamp_weight w1 <= clamp_weight w2.
  Proof.
    intros w1 w2 Hle.
    unfold clamp_weight, clamp, kMinFontWeight, kMaxFontWeight.
    lia.
  Qed.

  (** Auxiliary Invariant 5: Lower bound saturation. *)
  Theorem clamp_weight_saturates_low : forall (w : Z),
    w <= kMinFontWeight ->
    clamp_weight w = kMinFontWeight.
  Proof.
    intros w Hlow.
    unfold clamp_weight, clamp, kMinFontWeight, kMaxFontWeight in *.
    lia.
  Qed.

  (** Auxiliary Invariant 6: Upper bound saturation. *)
  Theorem clamp_weight_saturates_high : forall (w : Z),
    kMaxFontWeight <= w ->
    clamp_weight w = kMaxFontWeight.
  Proof.
    intros w Hhigh.
    unfold clamp_weight, clamp, kMinFontWeight, kMaxFontWeight in *.
    lia.
  Qed.

End BlinkFontWeightClamping.
```