# Formal Verification Report: W3C Payment Request Total Amount Non-Negativity Constraint

**Agent:** Formal Verification Agent 626 (Web Payments, Autofill & Form Normalization)  
**Topic:** W3C Payment Request Total Amount Non-Negativity Constraint  
**Chromium Source:** `third_party/blink/renderer/modules/payments/payment_request.cc`  
**Specification:** W3C Payment Request API §5.5 (`PaymentRequest` constructor & `PaymentDetailsInit` validation)  
**Formal Theory Target:** `BlinkPaymentTotalNonNegativitySemantics.v`  

---

## 1. Normative W3C Payment Request Specification Requirements

Within the W3C Payment Request API specification, monetary amounts are represented via the `PaymentCurrencyAmount` dictionary, which contains a `currency` string and a `value` string. While individual line items (`displayItems`) or shipping options (`shippingOptions`) may carry negative values (e.g., to represent discounts, promotional credits, or tax adjustments), the top-level **total** amount charged to the user must never be negative.

### 1.1 Normative Algorithm (§5.5 and §8.3 "Check and Canonicalize Total")
According to W3C Payment Request API §5.5 (*The PaymentRequest Constructor*) and the associated abstract operation *Check and canonicalize total*:

1. Let `total` be `details.total`.
2. Check and canonicalize `total.amount`. If this throws an exception, rethrow that exception.
3. **Non-Negativity Constraint:** If the first code point of `total.amount.value` is U+002D HYPHEN-MINUS (`-`), then throw a **`TypeError`** DOMException.

Formally, the valid decimal monetary string grammar is defined by the regular expression:
$$\text{ValidDecimalMonetaryValue} = \texttt{\textasciicircum -?[0-9]+(\textbackslash .[0-9]+)?\$}$$

For any general `PaymentItem` $i \in \text{displayItems}$, its value $v_i$ satisfies:
$$v_i \in L(\text{ValidDecimalMonetaryValue}) \iff \text{val}(v_i) \in \mathbb{Q}$$

However, for the specific distinguished item `details.total`, the specification enforces a strict subset constraint:
$$v_{\text{total}} \in L(\text{ValidDecimalMonetaryValue}) \land v_{\text{total}}[0] \neq \texttt{'-'} \iff \text{val}(v_{\text{total}}) \ge 0$$

### 1.2 Invariant Preservation Across Updates
This requirement is not restricted to the `PaymentRequest` constructor. When a merchant responds to `shippingaddresschange`, `shippingoptionchange`, or `paymentmethodchange` events via `PaymentRequestUpdateEvent.updateWith(detailsPromise)`, the resolved `PaymentDetailsUpdate` dictionary may contain a new `total` member. If `details.total` is present during an update, the exact same non-negativity validation must be executed; if violated, the update promise is rejected with a `TypeError` and the payment sheet is aborted.

---

## 2. Chromium Blink Implementation & Invariants

In Chromium's Blink rendering engine, the validation of `PaymentDetailsInit` and `PaymentDetailsUpdate` is centralized in `third_party/blink/renderer/modules/payments/payment_request.cc` (working alongside `payments_validators.cc`).

### 2.1 Blink Source Code Architecture
In `payment_request.cc`, the helper function `ValidateAndConvertPaymentDetailsInit` (and `ValidateAndConvertPaymentDetailsUpdate`) calls `ValidateAndConvertTotal`:

```cpp
// third_party/blink/renderer/modules/payments/payment_request.cc

static void ValidateAndConvertTotal(const PaymentItem* input,
                                    const String& item_name,
                                    PaymentItemPtr& output,
                                    ExecutionContext& execution_context,
                                    ExceptionState& exception_state) {
  if (!input->hasLabel() || !input->hasAmount() ||
      !input->amount()->hasCurrency() || !input->amount()->hasValue()) {
    exception_state.ThrowTypeError("Required member is missing in " + item_name);
    return;
  }

  // 1. Validate general monetary value format: ^-?[0-9]+(\.[0-9]+)?$
  String error_message;
  if (!PaymentsValidators::IsValidAmountFormat(
          execution_context, input->amount()->value(), item_name,
          &error_message)) {
    exception_state.ThrowTypeError(error_message);
    return;
  }

  // 2. Enforce W3C §5.5 Non-Negativity Constraint on Total
  if (input->amount()->value()[0] == '-') {
    exception_state.ThrowTypeError("Total amount value should be non-negative");
    return;
  }

  // 3. Validate Currency Code (ISO 4217 / Well-formed currency code)
  if (!PaymentsValidators::IsValidCurrencyCodeFormat(
          execution_context, input->amount()->currency(), &error_message)) {
    exception_state.ThrowTypeError(error_message);
    return;
  }
  ...
}
```

### 2.2 Implementation Invariants
1. **Format Precedence Invariant:** `PaymentsValidators::IsValidAmountFormat` executes *before* the leading `'-'` check. Because `IsValidAmountFormat` rejects empty strings (`""`), whitespace-padded strings (`" -1.00"`), and malformed numbers (`"-"` or `"-.5"`), checking `value[0] == '-'` is both memory-safe (guaranteed length $\ge 1$) and semantically equivalent to arithmetic negativity (except for `"-0"` or `"-0.00"`, which the W3C specification explicitly forbids via the syntax check `value[0] == '-'`).
2. **Asymmetry Invariant (`Total` vs `DisplayItems`):** In `ValidateAndConvertDisplayItems`, `PaymentsValidators::IsValidAmountFormat` is called, **without** the `value[0] == '-'` check. Thus, Blink permits negative `displayItems` while strictly rejecting negative `total` values.
3. **Exception Atomicity:** If `input->amount()->value()[0] == '-'` evaluates to true, `exception_state.ThrowTypeError(...)` is invoked immediately, preventing IPC serialization of `mojom::blink::PaymentItemPtr` to the browser process.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization in `BlinkPaymentTotalNonNegativitySemantics.v`. We model both the **syntactic level** (character prefix and sign tokenizing as performed by Blink's `value[0] == '-'` check) and the **semantic level** (arbitrary-precision scaled integer/decimal arithmetic over $\mathbb{Z}$), proving their exact behavioral correspondence and invariant preservation.

```coq
(** * BlinkPaymentTotalNonNegativitySemantics.v
    Formal Verification of W3C Payment Request API §5.5 & Blink payment_request.cc
    Target: Total Amount Non-Negativity Constraint & TypeError Semantics *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Syntactic and Semantic Domain Definitions *)

(** A parsed decimal monetary value after passing PaymentsValidators::IsValidAmountFormat.
    Note: W3C spec syntax check specifically checks if the first code point is U+002D ('-').
    Even "-0.00" has a leading minus sign and is rejected by the spec and Blink.
    We therefore model the representation with an explicit syntactic sign flag
    coupled with a non-negative scaled integer magnitude (in minor units / micro-units)
    and its numeric projection. *)

Record MonetaryAmount := mkMonetaryAmount {
  has_leading_minus : bool;
  magnitude : Z; (* Scaled integer magnitude, e.g., cents; well-formedness requires >= 0 *)
}.

(** Well-formedness predicate guaranteed by PaymentsValidators::IsValidAmountFormat:
    The regex ^-?[0-9]+(\.[0-9]+)?$ guarantees that the digits form a non-negative integer
    when scaled, and the leading minus is captured by [has_leading_minus]. *)
Definition wf_amount (amt : MonetaryAmount) : Prop :=
  amt.(magnitude) >= 0.

(** Numeric evaluation of a MonetaryAmount into Z. *)
Definition eval_amount (amt : MonetaryAmount) : Z :=
  if amt.(has_leading_minus) then - amt.(magnitude) else amt.(magnitude).

(** Purely numeric non-negativity predicate: total_non_negative(val) = val >= 0 *)
Definition total_non_negative_Z (val : Z) : Prop :=
  val >= 0.

Definition total_non_negative_bool (val : Z) : bool :=
  val >=? 0.

(** Syntactic non-negativity check as implemented in Blink payment_request.cc:
    `if (input->amount()->value()[0] == '-')` *)
Definition blink_is_negative_syntax (amt : MonetaryAmount) : bool :=
  amt.(has_leading_minus).

(** ** 2. Payment Structures and Validation Results *)

Inductive DOMException : Type :=
  | TypeError
  | RangeError
  | InvalidStateError.

Inductive ValidationResult (A : Type) : Type :=
  | Ok (val : A)
  | Throw (ex : DOMException).

Arguments Ok {A} _.
Arguments Throw {A} _.

Record PaymentItem := mkPaymentItem {
  item_amount : MonetaryAmount;
  item_is_wf  : bool; (* Result of IsValidAmountFormat && IsValidCurrencyCodeFormat *)
}.

Record PaymentDetailsInit := mkPaymentDetailsInit {
  details_total : PaymentItem;
  details_display_items : list PaymentItem;
}.

Record ValidatedPaymentDetails := mkValidatedPaymentDetails {
  valid_total : Z;
  valid_display_items : list Z;
}.

(** ** 3. Blink Validation Functions (third_party/blink/renderer/modules/payments/payment_request.cc) *)

(** Validation of a pure numeric total value (Abstract Mathematical Model) *)
Definition validate_total_numeric (val : Z) : ValidationResult Z :=
  if total_non_negative_bool val then
    Ok val
  else
    Throw TypeError.

(** Validation of `total` in Blink (`ValidateAndConvertTotal`) *)
Definition blink_validate_total (item : PaymentItem) : ValidationResult Z :=
  if negb item.(item_is_wf) then
    Throw TypeError
  else if blink_is_negative_syntax item.(item_amount) then
    Throw TypeError
  else
    Ok (eval_amount item.(item_amount)).

(** Validation of a single display item in Blink (`ValidateAndConvertDisplayItems`):
    Note that display items allow negative values (e.g., discounts), so
    `blink_is_negative_syntax` is NOT checked here. *)
Definition blink_validate_display_item (item : PaymentItem) : ValidationResult Z :=
  if negb item.(item_is_wf) then
    Throw TypeError
  else
    Ok (eval_amount item.(item_amount)).

Fixpoint blink_validate_display_items (items : list PaymentItem) : ValidationResult (list Z) :=
  match items with
  | [] => Ok []
  | x :: xs =>
      match blink_validate_display_item x with
      | Ok v =>
          match blink_validate_display_items xs with
          | Ok vs => Ok (v :: vs)
          | Throw e => Throw e
          end
      | Throw e => Throw e
      end
  end.

(** Full `ValidateAndConvertPaymentDetailsInit` model *)
Definition blink_validate_payment_details
  (details : PaymentDetailsInit) : ValidationResult ValidatedPaymentDetails :=
  match blink_validate_total details.(details_total) with
  | Throw e => Throw e
  | Ok tot_val =>
      match blink_validate_display_items details.(details_display_items) with
      | Throw e => Throw e
      | Ok disp_vals =>
          Ok (mkValidatedPaymentDetails tot_val disp_vals)
      end
  end.

(** State transition model for `PaymentRequestUpdateEvent.updateWith` *)
Record PaymentRequestState := mkPaymentRequestState {
  current_total : Z;
  current_items : list Z;
}.

Definition StateInvariant (st : PaymentRequestState) : Prop :=
  total_non_negative_Z st.(current_total).

Definition blink_update_payment_details
  (st : PaymentRequestState)
  (new_details : PaymentDetailsInit) : ValidationResult PaymentRequestState :=
  match blink_validate_payment_details new_details with
  | Ok validated =>
      Ok (mkPaymentRequestState validated.(valid_total) validated.(valid_display_items))
  | Throw e =>
      Throw e
  end.
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

We now state and prove the core verification theorems establishing the correctness of the mathematical model, the Blink implementation in `payment_request.cc`, the asymmetry between `total` and `displayItems`, and state invariant preservation across payment lifecycle updates.

```coq
(** ** 4. Formal Verification Theorems & Proofs *)

(** Theorem 1: Reflection equivalence between boolean check and Z non-negativity predicate. *)
Theorem total_non_negative_reflect : forall (val : Z),
  total_non_negative_bool val = true <-> total_non_negative_Z val.
Proof.
  intros val.
  unfold total_non_negative_bool, total_non_negative_Z.
  rewrite Z.geb_le.
  lia.
Qed.

(** Theorem 2: Pure numeric validation throws TypeError if and only if val < 0. *)
Theorem numeric_negative_total_throws_type_error : forall (val : Z),
  val < 0 <-> validate_total_numeric val = Throw TypeError.
Proof.
  intros val.
  unfold validate_total_numeric, total_non_negative_bool.
  destruct (val >=? 0) eqn:Heq.
  - rewrite Z.geb_le in Heq.
    split; intros H.
    + lia.
    + discriminate H.
  - rewrite Z.geb_leb in Heq.
    rewrite Z.leb_gt in Heq.
    split; intros H.
    + reflexivity.
    + lia.
Qed.

(** Theorem 3: Pure numeric validation succeeds with Ok val if and only if total_non_negative_Z val. *)
Theorem numeric_non_negative_total_succeeds : forall (val : Z),
  total_non_negative_Z val <-> validate_total_numeric val = Ok val.
Proof.
  intros val.
  unfold validate_total_numeric, total_non_negative_bool, total_non_negative_Z.
  destruct (val >=? 0) eqn:Heq.
  - rewrite Z.geb_le in Heq.
    split; intros H.
    + reflexivity.
    + lia.
  - rewrite Z.geb_leb in Heq.