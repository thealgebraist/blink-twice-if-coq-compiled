### 1. Audit Summary: Chromium Blink Viewport Units Resolution vs CSS Values 4 §6.1

Per **CSS Values and Units Module Level 4 §6.1 (Viewport-percentage Lengths)**, the viewport-relative units (`vw`, `vh`, `vi`, `vb`, `vmin`, `vmax` and their `s*`, `l*`, `d*` variants) represent percentages of the respective reference viewport dimensions. Specifically, `1vw` equals `1%` of the width of the initial containing block (or reference viewport width $v_w$).

In **Chromium Blink** (`third_party/blink/renderer/core/css/css_to_length_conversion_data.cc`), viewport unit resolution computes the resolved pixel length via real/floating-point arithmetic:
$$\text{resolve\_vw}(\text{vw\_count}, v_w) = \frac{\text{vw\_count} \cdot v_w}{100}$$

### 2. Core Invariants
1. **Full Viewport Identity (`100vw = v_w`)**: Resolving `100vw` against any viewport width $v_w$ yields exactly $v_w$.
2. **Zero Viewport Identity**: Resolving `0vw` yields `0px`, and resolving any `vw_count` against a `0px` viewport yields `0px`.
3. **Linearity / Homogeneity**: Scaling `vw_count` or $v_w$ scales the resolved length proportionally, and `resolve_vw` distributes over addition of `vw_count`.
4. **Monotonicity in Viewport Width ($v_w$)**: For any non-negative `vw_count` ($\ge 0$), if $v_{w1} \le v_{w2}$, then $\text{resolve\_vw}(\text{vw\_count}, v_{w1}) \le \text{resolve\_vw}(\text{vw\_count}, v_{w2})$.

---

### 3. Rocq / Coq Formalization (`BlinkViewportUnitsResolutionSemantics.v`)

The following complete, self-contained Rocq mechanization formalizes the resolution semantics over exact real numbers (`R`) and proves all specification invariants with zero admits.

```coq
(** * BlinkViewportUnitsResolutionSemantics.v
    Formalization of Chromium Blink Viewport Units Resolution
    audited against CSS Values and Units Module Level 4 §6.1.
*)

From Coq Require Import Reals Lra.
Open Scope R_scope.

Section ViewportUnitsResolution.

  (** [resolve_vw vw_count v_w] resolves [vw_count] viewport-width units
      against a viewport width [v_w] (in canonical px units).
      CSS Values 4 §6.1: 1vw = 1% of viewport width. *)
  Definition resolve_vw (vw_count v_w : R) : R :=
    (vw_count * v_w) / 100.

  (** [resolve_vh vh_count v_h] resolves [vh_count] viewport-height units
      against a viewport height [v_h]. *)
  Definition resolve_vh (vh_count v_h : R) : R :=
    (vh_count * v_h) / 100.

  (** [resolve_vmin count v_w v_h] resolves [vmin] units against the smaller
      dimension of [v_w] and [v_h]. *)
  Definition resolve_vmin (count v_w v_h : R) : R :=
    (count * Rmin v_w v_h) / 100.

  (** [resolve_vmax count v_w v_h] resolves [vmax] units against the larger
      dimension of [v_w] and [v_h]. *)
  Definition resolve_vmax (count v_w v_h : R) : R :=
    (count * Rmax v_w v_h) / 100.

  (** ** Invariant 1: 100vw = v_w *)
  Theorem resolve_vw_100 :
    forall v_w : R,
      resolve_vw 100 v_w = v_w.
  Proof.
    intros v_w.
    unfold resolve_vw.
    lra.
  Qed.

  (** ** Invariant 2: Zero identities *)
  Theorem resolve_vw_0_count :
    forall v_w : R,
      resolve_vw 0 v_w = 0.
  Proof.
    intros v_w.
    unfold resolve_vw.
    lra.
  Qed.

  Theorem resolve_vw_0_viewport :
    forall vw_count : R,
      resolve_vw vw_count 0 = 0.
  Proof.
    intros vw_count.
    unfold resolve_vw.
    lra.
  Qed.

  (** ** Invariant 3: Monotonicity in viewport width [v_w] *)
  Theorem resolve_vw_monotonic_viewport_w :
    forall vw_count v_w1 v_w2 : R,
      0 <= vw_count ->
      v_w1 <= v_w2 ->
      resolve_vw vw_count v_w1 <= resolve_vw vw_count v_w2.
  Proof.
    intros vw_count v_w1 v_w2 Hcount Hvw.
    unfold resolve_vw.
    assert (Hmul : vw_count * v_w1 <= vw_count * v_w2).
    { apply Rmult_le_compat_l; assumption. }
    lra.
  Qed.

  (** ** Invariant 4: Strict monotonicity in viewport width for positive [vw_count] *)
  Theorem resolve_vw_strict_monotonic_viewport_w :
    forall vw_count v_w1 v_w2 : R,
      0 < vw_count ->
      v_w1 < v_w2 ->
      resolve_vw vw_count v_w1 < resolve_vw vw_count v_w2.
  Proof.
    intros vw_count v_w1 v_w2 Hcount Hvw.
    unfold resolve_vw.
    assert (Hmul : vw_count * v_w1 < vw_count * v_w2).
    { apply Rmult_lt_compat_l; assumption. }
    lra.
  Qed.

  (** ** Invariant 5: Monotonicity in [vw_count] for non-negative viewport width *)
  Theorem resolve_vw_monotonic_count :
    forall vw_count1 vw_count2 v_w : R,
      0 <= v_w ->
      vw_count1 <= vw_count2 ->
      resolve_vw vw_count1 v_w <= resolve_vw vw_count2 v_w.
  Proof.
    intros vw_count1 vw_count2 v_w Hvw Hcount.
    unfold resolve_vw.
    assert (Hmul : vw_count1 * v_w <= vw_count2 * v_w).
    { apply Rmult_le_compat_r; assumption. }
    lra.
  Qed.

  (** ** Invariant 6: Non-negativity preservation *)
  Theorem resolve_vw_nonneg :
    forall vw_count v_w : R,
      0 <= vw_count ->
      0 <= v_w ->
      0 <= resolve_vw vw_count v_w.
  Proof.
    intros vw_count v_w Hcount Hvw.
    rewrite <- (resolve_vw_0_viewport vw_count).
    apply resolve_vw_monotonic_viewport_w; assumption.
  Qed.

  (** ** Invariant 7: Additivity / Linearity in [vw_count] *)
  Theorem resolve_vw_additive :
    forall c1 c2 v_w : R,
      resolve_vw (c1 + c2) v_w = resolve_vw c1 v_w + resolve_vw c2 v_w.
  Proof.
    intros c1 c2 v_w.
    unfold resolve_vw.
    lra.
  Qed.

  Theorem resolve_vw_scale :
    forall k vw_count v_w : R,
      resolve_vw (k * vw_count) v_w = k * resolve_vw vw_count v_w.
  Proof.
    intros k vw_count v_w.
    unfold resolve_vw.
    lra.
  Qed.

  (** ** Invariant 8: [vmin] <= [vw] <= [vmax] for non-negative count *)
  Theorem resolve_vmin_le_vw_le_vmax :
    forall count v_w v_h : R,
      0 <= count ->
      resolve_vmin count v_w v_h <= resolve_vw count v_w /\
      resolve_vw count v_w <= resolve_vmax count v_w v_h.
  Proof.
    intros count v_w v_h Hcount.
    unfold resolve_vmin, resolve_vw, resolve_vmax.
    pose proof (Rmin_l v_w v_h) as Hmin.
    pose proof (Rmax_l v_w v_h) as Hmax.
    assert (H1 : count * Rmin v_w v_h <= count * v_w).
    { apply Rmult_le_compat_l; assumption. }
    assert (H2 : count * v_w <= count * Rmax v_w v_h).
    { apply Rmult_le_compat_l; assumption. }
    split; lra.
  Qed.

End ViewportUnitsResolution.
```