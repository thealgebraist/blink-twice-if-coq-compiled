# Formal Verification Report: W3C Payment Request `PaymentDetailsModifier` Total Override Semantics

**Agent**: Formal Verification Agent 629 (Web Payments, Autofill & Form Normalization)  
**Target Theory**: `BlinkPaymentDetailsModifierOverrideSemantics.v`  
**Chromium Component**: `third_party/blink/renderer/modules/payments/`  
**Specification**: W3C Payment Request API §5.7 (`PaymentDetailsModifier` dictionary) & §9.4 (Payment Method Matching and Total Calculation)

---

## 1. Normative W3C Payment Request Specification Requirements

Within the W3C Payment Request API, merchants declare a base transaction total inside `PaymentDetailsInit` (and dynamically via `PaymentDetailsUpdate`), alongside an optional sequence of `PaymentDetailsModifier` dictionaries. Each modifier specifies conditional surcharges, discounts, and an overridden total that apply exclusively when the end-user selects a matching payment method identifier (PMI).

### 1.1 WebIDL Dictionary Definitions (§5.4 & §5.7)
```webidl
dictionary PaymentDetailsBase {
  sequence<PaymentItem> displayItems;
  sequence<PaymentShippingOption> shippingOptions;
  sequence<PaymentDetailsModifier> modifiers;
};

dictionary PaymentDetailsInit : PaymentDetailsBase {
  DOMString id;
  required PaymentItem total;
};

dictionary PaymentDetailsModifier {
  required DOMString supportedMethods;
  PaymentItem total;
  sequence<PaymentItem> additionalDisplayItems;
  object data;
};
```

### 1.2 Normative Total Override & Method Matching Semantics
When the user selects a payment handler corresponding to a standardized or URL-based payment method identifier $m \in \text{PMI}$, the user agent must resolve the effective transaction total presented on the payment sheet and authorized in the resulting `PaymentResponse`:

1. **Sequential First-Match Resolution**: Let $M = [d_0, d_1, \dots, d_{n-1}]$ be the internal slot `[[modifiers]]` storing validated `PaymentDetailsModifier` instances in declaration order. The user agent searches $M$ linearly from index $0$ to $n-1$ for the first modifier $d_k$ where $d_k.\text{supportedMethods} = m$ (exact ASCII string equality for standardized PMIs or canonicalized URL equality for URL-based PMIs).
2. **Optional Total Override**:
   - If no modifier $d_k \in M$ matches $m$, the effective total item is the base total $T_{\text{base}}$.
   - If a first matching modifier $d_k$ exists and $d_k.\text{total}$ is present (`Some` $T_{\text{mod}}$), the effective total item is $T_{\text{mod}}$.
   - If a first matching modifier $d_k$ exists, but $d_k.\text{total}$ is omitted (`None` / `undefined`), the effective total item falls back to $T_{\text{base}}$ (even if a subsequent matching modifier $d_j$ with $j > k$ defines a non-null `total`).
3. **Monetary Validation Invariants**: Both $T_{\text{base}}.\text{amount}.\text{value}$ and every present $d_k.\text{total}.\text{amount}.\text{value}$ must be validated against the valid decimal monetary value grammar (`^-?[0-9]+(\.[0-9]+)?$`) and must **not** begin with `'-'` (non-negative total requirement, §8.2 "Check and canonicalize total").

Mathematically, the specification mandates:
$$\text{effective\_total}(T_{\text{base}}, M, m) = \text{ unwrap\_or}\big(\text{bind}(\text{find}(\lambda d.\, d.\text{method} = m, M), \lambda d.\, d.\text{total}),\, T_{\text{base}}\big)$$

---

## 2. Chromium Blink Implementation & Invariants

In Chromium Blink (`third_party/blink/renderer/modules/payments/`), payment request initialization, modifier validation, Mojo serialization, and `PaymentResponse` synthesis enforce these exact semantics across the renderer/browser boundary.

### 2.1 Renderer Validation & Mojo Marshaling (`payment_request.cc`)
During `PaymentRequest::Create` and `PaymentRequest::OnUpdatePaymentDetails`:
- `ValidateAndConvertPaymentDetailsBase` iterates over `PaymentDetailsBase::modifiers()`.
- Each modifier's `supportedMethods` is validated via `PaymentsValidators::IsValidMethodFormat`.
- If `modifier->hasTotal()` is true, `ValidateAndConvertTotal` validates that `modifier->total()->amount()->value()` is a well-formed non-negative decimal monetary value. If absent, the Mojo struct `payments::mojom::blink::PaymentDetailsModifierPtr` leaves its `total` pointer field as `nullptr`.

### 2.2 Response Synthesis & Total Resolution (`payment_response.cc`)
When the browser process returns `payments::mojom::blink::PaymentResponsePtr` to `PaymentRequest::OnPaymentResponse`, Blink constructs the script-exposed `PaymentResponse` object in `third_party/blink/renderer/modules/payments/payment_response.cc`:

- `PaymentResponse::methodName()` stores the exact selected payment method identifier (`response->method_name`).
- The payment sheet and payment handler invocation resolve the active modifier against `response->method_name` by scanning the `modifiers` vector in index order:

```cpp
// Conceptual invariant enforced across Blink PaymentRequest / PaymentAppService
// and verified in payment_response.cc / payment_request.cc:
const PaymentItem* ResolveEffectiveTotal(
    const PaymentItem* base_total,
    const HeapVector<Member<PaymentDetailsModifier>>& modifiers,
    const String& selected_method) {
  for (const auto& modifier : modifiers) {
    if (modifier->supportedMethods() == selected_method) {
      return modifier->hasTotal() ? modifier->total() : base_total;
    }
  }
  return base_total;
}
```

### 2.3 Key Implementation Invariants
1. **First-Match Shadowing**: Because the loop returns immediately upon `modifier->supportedMethods() == selected_method`, any modifier at index $j > k$ with the same `supportedMethods` is shadowed—even if modifier $k$ has `hasTotal() == false` and modifier $j$ has `hasTotal() == true`.
2. **Non-Negativity Preservation**: Because `ValidateAndConvertTotal` rejects negative totals on both `details.total` and every present `modifier.total` prior to populating internal state, the resolved effective total for `PaymentResponse` is guaranteed to be non-negative for all possible `selected_method` strings.
3. **Disjoint Method Independence**: Appending or modifying a `PaymentDetailsModifier` for payment method $m_1$ leaves the effective total for any $m_2 \neq m_1$ strictly invariant.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkPaymentDetailsModifierOverrideSemantics.v`. We model payment methods as discrete identifiers (`nat`), monetary amounts as arbitrary-precision integers (`Z` representing minor currency units/cents), `PaymentItem` records, and `PaymentDetailsModifier` records.

## 4. Complete Rocq / Coq Theory and Proofs

```coq
(** * BlinkPaymentDetailsModifierOverrideSemantics.v
    Formal Verification of W3C Payment Request API §5.7 PaymentDetailsModifier
    Total Override Semantics in Chromium Blink. *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Domain Types and Data Structures *)

(** Payment Method Identifier (PMI), represented as discrete natural identifiers. *)
Definition PaymentMethod := nat.

(** Decidable equality on PaymentMethod. *)
Definition method_eqb (m1 m2 : PaymentMethod) : bool :=
  Nat.eqb m1 m2.

Lemma method_eqb_eq : forall m1 m2 : PaymentMethod,
  method_eqb m1 m2 = true <-> m1 = m2.
Proof.
  intros m1 m2. unfold method_eqb. apply Nat.eqb_eq.
Qed.

Lemma method_eqb_neq : forall m1 m2 : PaymentMethod,
  method_eqb m1 m2 = false <-> m1 <> m2.
Proof.
  intros m1 m2. unfold method_eqb. apply Nat.eqb_neq.
Qed.

Lemma method_eqb_refl : forall m : PaymentMethod,
  method_eqb m m = true.
Proof.
  intro m. unfold method_eqb. apply Nat.eqb_refl.
Qed.

(** W3C PaymentCurrencyAmount & PaymentItem representation.
    Currency is represented by an identifier; value is in minor units (Z). *)
Record PaymentItem := mkPaymentItem {
  item_currency : nat;
  item_value    : Z
}.

(** W3C §8.2 Check and canonicalize total: total value must be non-negative. *)
Definition valid_total_item (item : PaymentItem) : Prop :=
  0 <= item_value item.

(** W3C §5.7 PaymentDetailsModifier dictionary. *)
Record PaymentDetailsModifier := mkModifier {
  mod_supported_method : PaymentMethod;
  mod_total            : option PaymentItem;
  mod_additional_items : list PaymentItem
}.

(** A modifier is well-formed iff its optional total, when present, is non-negative. *)
Definition valid_modifier (m : PaymentDetailsModifier) : Prop :=
  match mod_total m with
  | Some t => valid_total_item t
  | None   => True
  end.

(** ** 2. Specification Functions (W3C §5.7 & Blink Resolution) *)

(** Option combinator modelling C++ std::optional::value_or / Blink fallback. *)
Definition option_value_or {A : Type} (opt : option A) (default : A) : A :=
  match opt with
  | Some v => v
  | None   => default
  end.

(** Find the first modifier matching the selected payment method. *)
Fixpoint match_mod (mods : list PaymentDetailsModifier) (method : PaymentMethod)
  : option PaymentDetailsModifier :=
  match mods with
  | [] => None
  | m :: rest =>
      if method_eqb (mod_supported_method m) method then
        Some m
      else
        match_mod rest method
  end.

(** Extract the optional total from an optional matched modifier. *)
Definition matched_mod_total (mods : list PaymentDetailsModifier) (method : PaymentMethod)
  : option PaymentItem :=
  match match_mod mods method with
  | Some m => mod_total m
  | None   => None
  end.

(** Specification-level effective_total:
    effective_total(base, mods, method) = match_mod(mods, method).total.value_or(base) *)
Definition effective_total
  (base : PaymentItem)
  (mods : list PaymentDetailsModifier)
  (method : PaymentMethod) : PaymentItem :=
  option_value_or (matched_mod_total mods method) base.

(** Blink imperative loop implementation in payment_response.cc / payment_request.cc. *)
Fixpoint blink_resolve_effective_total
  (base : PaymentItem)
  (mods : list PaymentDetailsModifier)
  (method : PaymentMethod) : PaymentItem :=
  match mods with
  | [] => base
  | m :: rest =>
      if method_eqb (mod_supported_method m) method then
        match mod_total m with
        | Some t => t
        | None   => base
        end
      else
        blink_resolve_effective_total base rest method
  end.

(** ** 3. Core Theorems and Formal Proofs *)

(** Theorem 1: Exact Equivalence between Blink's imperative loop and the
    functional W3C specification formula:
    effective_total(base, mods, method) = match_mod(mods, method).total.value_or(base). *)
Theorem blink_implements_effective_total :
  forall (base : PaymentItem) (mods : list PaymentDetailsModifier) (method : PaymentMethod),
    blink_resolve_effective_total base mods method = effective_total base mods method.
Proof.
  intros base mods method.
  unfold effective_total, matched_mod_total, option_value_or.
  induction mods as [| m rest IH]; simpl.
  - reflexivity.
  - destruct (method_eqb (mod_supported_method m) method) eqn:Heq.
    + destruct (mod_total m); reflexivity.
    + exact IH.
Qed.

(** Theorem 2: Empty Modifiers Fallback.
    When no modifiers are provided, effective_total always returns base. *)
Theorem effective_total_nil :
  forall (base : PaymentItem) (method : PaymentMethod),
    effective_total base [] method = base.
Proof.
  intros base method.
  reflexivity.
Qed.

(** Theorem 3: Disjoint Payment Method Fallback.
    If no modifier in `mods` supports `method`, `effective_total` equals `base`. *)
Theorem effective_total_no_match_fallback :
  forall (base : PaymentItem) (mods : list PaymentDetailsModifier) (method : PaymentMethod),
    Forall (fun m => mod_supported_method m <> method) mods ->
    effective_total base mods method = base.
Proof.
  intros base mods method Hforall.
  rewrite <- blink_implements_effective_total.
  induction mods as [| m rest IH]; simpl.
  - reflexivity.
  - inversion Hforall as [| m' rest' Hneq Hrest]; subst.
    apply method_eqb_neq in Hneq.
    rewrite Hneq.
    apply IH.
    exact Hrest.
Qed.

(** Theorem 4: First-Match Total Override & Shadowing Semantics.
    If the head modifier matches `method`, its optional total (or `base` if `None`)
    determines the result immediately, completely shadowing `rest`. *)
Theorem effective_total_first_match_shadows :
  forall (base : PaymentItem) (m : PaymentDetailsModifier)
         (rest : list PaymentDetailsModifier) (method : PaymentMethod),
    mod_supported_method m = method ->
    effective_total base (m :: rest) method = option_value_or (mod_total m) base.
Proof.
  intros base m rest method Hmatch.
  unfold effective_total, matched_mod_total.
  simpl.
   subst method.
  rewrite method_eqb_refl.
  reflexivity.
Qed.

(** Corollary 4a: First-Match with Null Total Still Shadows Later Modifiers.
    Even if a later modifier in `rest` has a `Some t` override for `method`,
    an earlier matching modifier with `mod_total = None` forces fallback to `base`. *)
Corollary first_match_none_shadows_later_some :
  forall (base t_later : PaymentItem) (m1 m2 : PaymentDetailsModifier)
         (rest : list PaymentDetailsModifier) (method : PaymentMethod),
    mod_supported_method m1 = method ->
    mod_total m1 = None ->
    mod