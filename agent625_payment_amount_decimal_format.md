# Formal Verification Report: W3C Payment Request Decimal Amount Format and Parsing
**Agent**: 625 (Web Payments, Autofill & Form Normalization)  
**Target Theory**: `BlinkPaymentAmountDecimalFormatSemantics.v`  
**Chromium Source**: `third_party/blink/renderer/modules/payments/payment_request.cc`  
**W3C Specification**: Payment Request API §5.5 (`PaymentCurrencyAmount` value syntax)

---

## 1. Normative W3C Payment Request Specification Requirements

In the W3C Payment Request API specification (§5.5 `PaymentCurrencyAmount` dictionary), monetary values are exchanged via the `value` DOMString member. To prevent floating-point representation drift, locale-dependent ambiguity, and injection vectors during payment sheet instantiation, the specification enforces a strict lexical grammar on `PaymentCurrencyAmount.value`.

### 1.1 Normative Syntax Definition
According to Payment Request API §5.5.1 (*Valid decimal monetary value*):
> A string is a **valid decimal monetary value** if it consists of the following components in the exact order specified:
> 1. Optionally, a single U+002D HYPHEN-MINUS character (`-`), to indicate a negative amount.
> 2. One or more characters in the range U+0030 DIGIT ZERO (`0`) to U+0039 DIGIT NINE (`9`).
> 3. Optionally:
>    a. A single U+002E FULL STOP character (`.`).
>    b. One or more characters in the range U+0030 DIGIT ZERO (`0`) to U+0039 DIGIT NINE (`9`).

In ECMAScript Regular Expression notation, the normative grammar is defined exactly as:
```regex
^-?[0-9]+(\.[0-9]+)?$
```

### 1.2 Explicit Exclusions and Validation Semantics
When `new PaymentRequest(methodData, details, options)` or `PaymentRequestUpdateEvent.updateWith(detailsPromise)` is invoked, the user agent must run the *check and canonicalize amount* algorithm (and *check and canonicalize total amount* for `details.total.amount`):
1. **No Leading Plus (`+`)**: Unlike general IEEE 754 or HTML floating-point number syntax, U+002B PLUS SIGN (`+`) is strictly forbidden. If present, the user agent must throw a `TypeError`.
2. **No Whitespace**: Leading or trailing ASCII whitespace (e.g., U+0020 SPACE, U+0009 TAB, U+000A LF) is not stripped; its presence causes validation failure (`TypeError`).
3. **No Empty Integral or Fractional Parts**: Strings such as `".50"` (missing leading digit) or `"50."` (trailing decimal point without fractional digits) are invalid and must throw a `TypeError`.
4. **No Exponential Notation**: Scientific notation (`"1e5"`, `"10E-2"`) is strictly rejected.
5. **Total Amount Non-Negativity**: While line items (`displayItems`, `shippingOptions`, `modifiers`) may contain a leading `-` (representing discounts or refunds), the top-level `details.total.amount.value` has an additional semantic constraint: it must be a valid decimal monetary value *and* its first character must not be U+002D HYPHEN-MINUS (`-`).

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, the validation of `PaymentCurrencyAmount` is implemented in `third_party/blink/renderer/modules/payments/payment_request.cc` (collaborating with `payments_validators.cc`).

### 2.1 Source Architecture in `payment_request.cc`
When validating payment details inside `payment_request.cc`, Blink performs structural and lexical checks before passing Mojo IPC structures (`payments::mojom::blink::PaymentCurrencyAmountPtr`) to the browser process:

```cpp
// Conceptual flow in third_party/blink/renderer/modules/payments/payment_request.cc
static void ValidateAndConvertPaymentDetailsInit(
    const PaymentDetailsInit* input,
    payments::mojom::blink::PaymentDetailsPtr& output,
    String& shipping_option_output,
    ExecutionContext& execution_context,
    ExceptionState& exception_state) {
  // ...
  if (!PaymentsValidators::IsValidAmountFormat(
          execution_context, input->total()->amount()->value(),
          "total amount value", exception_state)) {
    return;
  }

  if (input->total()->amount()->value()[0] == '-') {
    exception_state.ThrowTypeError("Total amount value should be non-negative");
    return;
  }
  // ...
}
```

### 2.2 Lexical Validator State Machine / Regex Equivalence
In Blink (`PaymentsValidators::IsValidAmountFormat` invoked by `payment_request.cc`), validation ensures exact conformance to `^-?[0-9]+(\.[0-9]+)?$`. Whether evaluated via compiled `ScriptRegexp("^-?[0-9]+(\\.[0-9]+)?$", kTextCaseSensitive)` or a deterministic character-by-character state machine, Blink enforces the following critical implementation invariants:

1. **Length Bound**: To prevent Denial-of-Service (DoS) attacks across the Mojo IPC boundary, Blink enforces `value.length() <= PaymentsValidators::kMaximumStringLength` (2048 characters) and non-emptiness (`!value.IsEmpty()`).
2. **Sign Disambiguation Invariant**:
   $$\text{is\_valid\_amount\_str}(s) \iff \text{matches\_decimal}(s) \land \text{no\_leading\_plus}(s)$$
   Where `matches_decimal(s)` represents general signed decimal syntax (permitting optional `+` or `-`), and `no_leading_plus(s)` explicitly rejects U+002B (`+`).
3. **Deterministic Finite Automaton (DFA) Decomposition**:
   Let a string $s \in \Sigma^*$ be a sequence of ASCII character codes. The validation algorithm transitions through states:
   - `S_START`: Expects `'-'` (transitions to `S_SIGN`) or `'0'..'9'` (transitions to `S_INT`). Any other byte (including `'+'` or `'.'`) transitions to `S_ERROR`.
   - `S_SIGN`: Expects `'0'..'9'` (transitions to `S_INT`). Any other byte transitions to `S_ERROR`.
   - `S_INT` (*Accepting*): Expects `'0'..'9'` (stays in `S_INT`) or `'.'` (transitions to `S_DOT`). Any other byte transitions to `S_ERROR`.
   - `S_DOT`: Expects `'0'..'9'` (transitions to `S_FRAC`). Any other byte (including a second `'.'`) transitions to `S_ERROR`.
   - `S_FRAC` (*Accepting*): Expects `'0'..'9'` (stays in `S_FRAC`). Any other byte transitions to `S_ERROR`.

---

## 3. Formal Specification in Rocq / Coq

Below is the self-contained formalization of `BlinkPaymentAmountDecimalFormatSemantics.v`. We model ASCII characters using integer code points (`Z`), define both the declarative structural specification (`matches_decimal` & `no_leading_plus`) and the operational DFA parser (`dfa_validate_amount`), and define semantic parsing into exact scaled integers (`Z * N` representing $\text{mantissa} \times 10^{-\text{scale}}$).

```coq
(** * BlinkPaymentAmountDecimalFormatSemantics.v
    Formal Verification of W3C Payment Request API §5.5 Decimal Amount Syntax
    and Chromium Blink third_party/blink/renderer/modules/payments/payment_request.cc *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Character Code Definitions (ASCII) *)

Definition Char := Z.
Definition String := list Char.

Definition c_plus  : Char := 43. (* '+' *)
Definition c_minus : Char := 45. (* '-' *)
Definition c_dot   : Char := 46. (* '.' *)
Definition c_zero  : Char := 48. (* '0' *)
Definition c_nine  : Char := 57. (* '9' *)

Definition is_digit (c : Char) : bool :=
  (c_zero <=? c) && (c <=? c_nine).

Definition is_sign (c : Char) : bool :=
  (c =? c_minus) || (c =? c_plus).

(** ** 2. Declarative W3C & General Decimal Grammar Predicates *)

(** Checks if a non-empty list of characters consists solely of digits [0-9]+ *)
Definition is_nonempty_digits (s : String) : bool :=
  match s with
  | [] => false
  | _ => forallb is_digit s
  end.

(** Splits a string at the first occurrence of '.' (U+002E) *)
Fixpoint split_at_dot (s : String) : String * option String :=
  match s with
  | [] => ([], None)
  | c :: rest =>
      if c =? c_dot then
        ([], Some rest)
      else
        let (int_part, frac_part) := split_at_dot rest in
        (c :: int_part, frac_part)
  end.

(** Validates an unsigned decimal body: [0-9]+(\.[0-9]+)? *)
Definition matches_unsigned_decimal (s : String) : bool :=
  let (int_part, frac_opt) := split_at_dot s in
  match frac_opt with
  | None => is_nonempty_digits int_part
  | Some frac_part => is_nonempty_digits int_part && is_nonempty_digits frac_part
  end.

(** General signed decimal format: ^[+-]?[0-9]+(\.[0-9]+)?$ *)
Definition matches_decimal (s : String) : bool :=
  match s with
  | [] => false
  | c :: rest =>
      if is_sign c then
        matches_unsigned_decimal rest
      else
        matches_unsigned_decimal s
  end.

(** W3C Payment Request restriction: no leading '+' sign *)
Definition no_leading_plus (s : String) : bool :=
  match s with
  | [] => true
  | c :: _ => negb (c =? c_plus)
  end.

(** Target Mathematical Property:
    is_valid_amount_str(s) = matches_decimal(s) && no_leading_plus(s) *)
Definition is_valid_amount_str (s : String) : bool :=
  matches_decimal s && no_leading_plus s.

(** Total amount validation in payment_request.cc: valid amount and non-negative *)
Definition no_leading_minus (s : String) : bool :=
  match s with
  | [] => true
  | c :: _ => negb (c =? c_minus)
  end.

Definition is_valid_total_amount_str (s : String) : bool :=
  is_valid_amount_str s && no_leading_minus s.

(** ** 3. Operational DFA Model (Blink PaymentsValidators State Machine) *)

Inductive DFAState : Type :=
  | S_Start
  | S_Sign
  | S_Int
  | S_Dot
  | S_Frac
  | S_Error.

Definition dfa_step (st : DFAState) (c : Char) : DFAState :=
  match st with
  | S_Start =>
      if c =? c_minus then S_Sign
      else if is_digit c then S_Int
      else S_Error
  | S_Sign =>
      if is_digit c then S_Int
      else S_Error
  | S_Int =>
      if is_digit c then S_Int
      else if c =? c_dot then S_Dot
      else S_Error
  | S_Dot =>
      if is_digit c then S_Frac
      else S_Error
  | S_Frac =>
      if is_digit c then S_Frac
      else S_Error
  | S_Error => S_Error
  end.

Fixpoint dfa_run (st : DFAState) (s : String) : DFAState :=
  match s with
  | [] => st
  | c :: rest => dfa_run (dfa_step st c) rest
  end.

Definition dfa_accepting (st : DFAState) : bool :=
  match st with
  | S_Int | S_Frac => true
  | _ => false
  end.

Definition blink_dfa_is_valid_amount (s : String) : bool :=
  dfa_accepting (dfa_run S_Start s).

(** ** 4. Exact Decimal Value Parsing Semantics *)

Definition digit_val (c : Char) : Z := c - c_zero.

Fixpoint parse_digits_acc (acc : Z) (s : String) : Z :=
  match s with
  | [] => acc
  | c :: rest => parse_digits_acc (acc * 10 + digit_val c) rest
  end.

(** Represents a parsed monetary amount as (sign_multiplier, scaled_integer, scale) *)
Record ParsedAmount : Type := mkParsedAmount {
  pa_negative : bool;
  pa_mantissa : Z;
  pa_scale    : Z
}.

Definition parse_unsigned_amount (s : String) : ParsedAmount :=
  let (int_part, frac_opt) := split_at_dot s in
  match frac_opt with
  | None =>
      mkParsedAmount false (parse_digits_acc 0 int_part) 0
  | Some frac_part =>
      mkParsedAmount false
        (parse_digits_acc (parse_digits_acc 0 int_part) frac_part)
        (Z.of_nat (List.length frac_part))
  end.

Definition parse_amount (s : String) : option ParsedAmount :=
  if is_valid_amount_str s then
    match s with
    | [] => None
    | c :: rest =>
        if c =? c_minus then
          let p := parse_unsigned_amount rest in
          Some (mkParsedAmount true (pa_mantissa p) (pa_scale p))
        else
          Some (parse_unsigned_amount s)
    end
  else None.
```

---

## 4. Concrete Theorems and Complete Rocq / Coq Proofs

In this section, we state and prove the core verification theorems with **zero admits**. We prove:
1. Disjointness of character classes (`is_digit`, `c_dot`, `c_minus`, `c_plus`).
2. Equivalence between the operational DFA in Blink (`blink_dfa_is_valid_amount`) and the declarative mathematical property (`is_valid_amount_str(s) = matches_decimal(s) && no_leading_plus(s)`).
3. Rejection of leading plus signs, empty strings, bare signs, and trailing/leading dots.
4. Non-neg