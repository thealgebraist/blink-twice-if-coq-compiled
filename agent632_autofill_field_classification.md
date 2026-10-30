# Formal Verification Report: HTML Autofill Field Name Categories Disjointness

**Agent ID:** 632  
**Specialization:** Web Payments, Autofill & Form Normalization (Chromium Blink / W3C)  
**Target Module:** `components/autofill/core/browser/autofill_field.cc`  
**Formal Theory Target:** `BlinkAutofillFieldClassificationSemantics.v`  
**Mathematical Property:** `category_partition` (Pairwise disjointness of Address, Billing, Credit Card, and Contact classifications)

---

## 1. Normative Specification Requirements

### 1.1 HTML Specification §4.10.18.7 (Autofill)
The WHATWG HTML Living Standard (§4.10.18.7 *Autofill*) defines the processing model and taxonomy for the `autocomplete` attribute on form control elements (`<input>`, `<select>`, `<textarea>`). When an element's autofill expectation mantle is evaluated, the attribute's value is parsed into an ordered sequence of space-separated tokens corresponding to specific syntactic categories:

1. **Optional Section Token:** Matches the prefix `section-*`.
2. **Optional Address Type Token:** Exclusively either `"shipping"` or `"billing"`.
3. **Autofill Field Name Token:** Drawn from a strictly partitioned vocabulary of semantic field targets, optionally preceded by contact modifier tokens (`"home"`, `"work"`, `"mobile"`, `"fax"`, `"pager"`).

The normative grammar mandates that the **Autofill Field Name Tokens** are partitioned into non-overlapping semantic groups:

* **Identity / General:** `name`, `honorific-prefix`, `given-name`, `additional-name`, `family-name`, `honorific-suffix`, `nickname`, `username`, `new-password`, `current-password`, `one-time-code`, `organization-title`, `organization`, `bday`, `bday-day`, `bday-month`, `bday-year`, `sex`, `url`, `photo`, `language`, `impp`.
* **Address Tokens:** `street-address`, `address-line1`, `address-line2`, `address-line3`, `address-level4`, `address-level3`, `address-level2`, `address-level1`, `country`, `country-name`, `postal-code`.
* **Credit Card / Payment Tokens:** `cc-name`, `cc-given-name`, `cc-additional-name`, `cc-family-name`, `cc-number`, `cc-exp`, `cc-exp-month`, `cc-exp-year`, `cc-csc`, `cc-type`, `transaction-currency`, `transaction-amount`.
* **Contact / Digital Communication Tokens:** `tel`, `tel-country-code`, `tel-national`, `tel-area-code`, `tel-local`, `tel-local-prefix`, `tel-local-suffix`, `tel-extension`, `email`.

**Normative Grammar Constraint:** A contact modifier token (`"home"`, `"work"`, etc.) is syntactically permissible *if and only if* the terminal autofill field name token belongs to the **Contact** token set. Conversely, an address type token (`"shipping"`, `"billing"`) scopes the physical or financial routing context of the form control.

### 1.2 W3C Payment Request API Integration
In the W3C Payment Request API, `PaymentAddress` and `BasicCardRequest` (and its successor Payment Handler abstractions) rely on the deterministic disambiguation of form fields during automated checkout flows and DOM-to-PaymentRequest bridging. If a single DOM field could simultaneously satisfy the classification predicates of both a `CreditCard` instrument and a physical `Address` or `Contact` endpoint, sensitive primary account numbers (PAN) or card security codes (`cc-csc`) could be inadvertently exfiltrated into merchant-accessible shipping/contact event payloads (`shippingaddresschange`, `payerdetailchange`) prior to explicit user authorization.

---

## 2. Chromium & Blink Implementation Invariants

In Chromium, the translation from Blink DOM `WebFormControlElement` autocomplete tokens and heuristics into browser-process Autofill states is orchestrated in `components/autofill/core/browser/autofill_field.cc`, backed by the type system in `field_types.h`.

### 2.1 `AutofillType`, `FieldType`, and `FieldTypeGroup`
Every `AutofillField` instance maintains three sources of type classification:
1. `html_type_`: A `HtmlFieldType` enum value paired with a `HtmlFieldMode` (`kNone`, `kBilling`, `kShipping`), derived directly from Blink's parsing of the `autocomplete` attribute (`AutocompleteParsingResult`).
2. `heuristic_type_`: A `FieldType` derived from local regex matching (`FormFieldParser`).
3. `server_type_`: A `FieldType` provisioned by the Chromium Autofill crowdsourcing backend.

`AutofillField::Type()` resolves the active classification by returning an `AutofillType` wrapper. `AutofillField::GetOverallType()` prioritizes `html_type_` (when valid and specified) over `server_type_` and `heuristic_type_`.

### 2.2 The Classification Resolution Invariant
Inside `components/autofill/core/browser/autofill_field.cc` and `autofill_type.cc`, every resolved state maps deterministically to a `FieldTypeGroup` via `GroupTypeOfFieldType(FieldType)` or `GroupTypeOfHtmlFieldType(HtmlFieldType, HtmlFieldMode)`:

```cpp
FieldTypeGroup GroupTypeOfHtmlFieldType(HtmlFieldType field_type,
                                        HtmlFieldMode field_mode) {
  switch (field_type) {
    case HtmlFieldType::kStreetAddress:
    case HtmlFieldType::kAddressLine1:
    case HtmlFieldType::kAddressLine2:
    case HtmlFieldType::kAddressLine3:
    case HtmlFieldType::kAddressLevel1:
    case HtmlFieldType::kAddressLevel2:
    case HtmlFieldType::kAddressLevel3:
    case HtmlFieldType::kCountryCode:
    case HtmlFieldType::kCountryName:
    case HtmlFieldType::kPostalCode:
      return field_mode == HtmlFieldMode::kBilling
                 ? FieldTypeGroup::kAddressBilling // Normalized Billing Partition
                 : FieldTypeGroup::kAddressHome;   // Normalized Address Partition

    case HtmlFieldType::kCreditCardNameFull:
    case HtmlFieldType::kCreditCardNameFirst:
    case HtmlFieldType::kCreditCardNameLast:
    case HtmlFieldType::kCreditCardNumber:
    case HtmlFieldType::kCreditCardExp:
    case HtmlFieldType::kCreditCardExpMonth:
    case HtmlFieldType::kCreditCardExpYear:
    case HtmlFieldType::kCreditCardVerificationCode:
    case HtmlFieldType::kCreditCardType:
      return FieldTypeGroup::kCreditCard;

    case HtmlFieldType::kTel:
    case HtmlFieldType::kTelCountryCode:
    case HtmlFieldType::kTelNational:
    case HtmlFieldType::kTelAreaCode:
    case HtmlFieldType::kTelLocal:
    case HtmlFieldType::kTelLocalPrefix:
    case HtmlFieldType::kTelLocalSuffix:
    case HtmlFieldType::kTelExtension:
      return field_mode == HtmlFieldMode::kBilling
                 ? FieldTypeGroup::kPhoneBilling
                 : FieldTypeGroup::kPhoneHome;

    case HtmlFieldType::kEmail:
      return FieldTypeGroup::kEmail;
    // ...
  }
}
```

### 2.3 Security & Normalization Invariant
During form filling (`FormFiller::FillOrPreviewForm`), fields are partitioned into filling products (`FillingProduct::kAddress`, `FillingProduct::kCreditCard`, etc.). Furthermore, within the normalized HTML Autofill and Payment Request operational semantics:
1. **Credit Card Isolation:** A credit card token (`cc-*`) ignores the `HtmlFieldMode::kBilling` modifier with respect to category migration; it remains strictly in the `CreditCard` category and never bleeds into the `Billing` (address) category.
2. **Billing Promotion:** An address token paired with `HtmlFieldMode::kBilling` (or mapped to historical billing `FieldType` variants) transitions strictly out of the standard `Address` (shipping/home) partition and into the `Billing` partition.
3. **Contact Exclusivity:** Telecommunication and email tokens (`tel*`, `email`) belong exclusively to the `Contact` category unless explicitly isolated. Under the strict W3C token partition, the sets of fields classified as `Address`, `Billing`, `CreditCard`, and `Contact` are **pairwise disjoint**.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of the HTML Autofill field classification semantics (`BlinkAutofillFieldClassificationSemantics.v`). It models the raw HTML tokens, the address mode modifiers, the internal Chromium `FieldType` taxonomy, the `AutofillField::Type()` resolution algorithm, and the four target category predicates.

## 4. Concrete Theorems and Complete Proofs

The following Coq module compiles with zero axioms and zero `Admitted` statements using standard library imports (`ZArith`, `Lia`, `Bool`, `List`).

```coq
(** * BlinkAutofillFieldClassificationSemantics.v
    Formal Verification of HTML Spec §4.10.18.7 & Chromium Autofill Field Classification
    Target: components/autofill/core/browser/autofill_field.cc
    Property: category_partition (Pairwise disjointness of Address, Billing, CreditCard, Contact)
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Syntactic HTML Spec §4.10.18.7 Token Definitions *)

(** Address type tokens defined in HTML §4.10.18.7 *)
Inductive HtmlFieldMode : Type :=
  | ModeNone     : HtmlFieldMode
  | ModeShipping : HtmlFieldMode
  | ModeBilling  : HtmlFieldMode.

Scheme Equality for HtmlFieldMode.

(** Autofill field name tokens (HTML §4.10.18.7 & components/autofill/core/common/mojom/autofill_types.mojom) *)
Inductive HtmlFieldType : Type :=
  (* Unspecified / Unrecognized *)
  | HtmlUnspecified
  (* Street & Physical Address Tokens *)
  | HtmlStreetAddress
  | HtmlAddressLine1
  | HtmlAddressLine2
  | HtmlAddressLine3
  | HtmlAddressLevel1
  | HtmlAddressLevel2
  | HtmlAddressLevel3
  | HtmlAddressLevel4
  | HtmlCountryCode
  | HtmlCountryName
  | HtmlPostalCode
  (* Credit Card / Payment Instrument Tokens *)
  | HtmlCcNameFull
  | HtmlCcNameFirst
  | HtmlCcNameLast
  | HtmlCcNumber
  | HtmlCcExp
  | HtmlCcExpMonth
  | HtmlCcExpYear
  | HtmlCcCsc
  | HtmlCcType
  | HtmlTransactionCurrency
  | HtmlTransactionAmount
  (* Contact Tokens *)
  | HtmlTel
  | HtmlTelCountryCode
  | HtmlTelNational
  | HtmlTelAreaCode
  | HtmlTelLocal
  | HtmlTelLocalPrefix
  | HtmlTelLocalSuffix
  | HtmlTelExtension
  | HtmlEmail
  (* General / Identity Tokens (Outside the 4 core payment routing categories) *)
  | HtmlNameFull
  | HtmlGivenName
  | HtmlAdditionalName
  | HtmlFamilyName
  | HtmlOrganization
  | HtmlUsername
  | HtmlNewPassword
  | HtmlCurrentPassword
  | HtmlOneTimeCode.

Scheme Equality for HtmlFieldType.

(** ** 2. Internal Chromium FieldType Taxonomy (field_types.h) *)

Inductive ServerFieldType : Type :=
  | NO_SERVER_DATA
  | UNKNOWN_TYPE
  (* Standard Address Types *)
  | ADDRESS_HOME_STREET_ADDRESS
  | ADDRESS_HOME_LINE1
  | ADDRESS_HOME_LINE2
  | ADDRESS_HOME_LINE3
  | ADDRESS_HOME_STATE
  | ADDRESS_HOME_CITY
  | ADDRESS_HOME_DEPENDENT_LOCALITY
  | ADDRESS_HOME_SUBPREMISE
  | ADDRESS_HOME_COUNTRY
  | ADDRESS_HOME_ZIP
  (* Billing Address Types (Normalized in AutofillField) *)
  | ADDRESS_BILLING_STREET_ADDRESS
  | ADDRESS_BILLING_LINE1
  | ADDRESS_BILLING_LINE2
  | ADDRESS_BILLING_LINE3
  | ADDRESS_BILLING_STATE
  | ADDRESS_BILLING_CITY
  | ADDRESS_BILLING_DEPENDENT_LOCALITY
  | ADDRESS_BILLING_SUBPREMISE
  | ADDRESS_BILLING_COUNTRY
  | ADDRESS_BILLING_ZIP
  (* Credit Card Types *)
  | CREDIT_CARD_NAME_FULL
  | CREDIT_CARD_NAME_FIRST
  | CREDIT_CARD_NAME_LAST
  | CREDIT_CARD_NUMBER
  | CREDIT_CARD_EXP_DATE_4_DIGIT_YEAR
  | CREDIT_CARD_EXP_MONTH
  | CREDIT_CARD_EXP_4_DIGIT_YEAR
  | CREDIT_CARD_VERIFICATION_CODE
  | CREDIT_CARD_TYPE
  (* Contact Types *)
  | PHONE_HOME_WHOLE_NUMBER
  | PHONE_HOME_COUNTRY_CODE
  | PHONE_HOME_CITY_AND_NUMBER
  | PHONE_HOME_CITY_CODE
  | PHONE_HOME_NUMBER
  | PHONE_HOME_NUMBER_PREFIX
  | PHONE_HOME_NUMBER_SUFFIX
  | PHONE_HOME_EXTENSION
  | EMAIL_ADDRESS
  (* Other Non-Payment/Identity Types *)
  | NAME_FULL
  | NAME_FIRST
  | NAME_MIDDLE
  | NAME_LAST
  | COMPANY_NAME
  | USERNAME
  | PASSWORD
  | ACCOUNT_CREATION_PASSWORD
  | ONE_TIME_CODE.

Scheme Equality for ServerFieldType.

(** ** 3. Semantic Category Partition Target *)

Inductive FieldCategory : Type :=
  | CatAddress    : FieldCategory
  | CatBilling    : FieldCategory
  | CatCreditCard : FieldCategory
  | CatContact    : FieldCategory
  | CatOther      : FieldCategory.

Scheme Equality for FieldCategory.

(** Assigns a unique integer ID to each category to leverage ZArith / Lia *)
Definition category_id (c : FieldCategory) : Z :=
  match c with
  | CatAddress    => 1
  | CatBilling    => 2
  | CatCreditCard => 3
  | CatContact    => 4
  | CatOther      => 0
  end.

Lemma category_id_injective : forall c1 c2 : FieldCategory,
  category_id c1 = category_id c2 -> c1 = c2.
Proof.
  intros c1 c2 H.
  destruct c1, c2; simpl in H; try reflexivity; lia.
Qed.

(** ** 4. Chromium AutofillField State and Type Resolution (autofill_field.cc) *)

Record AutofillField : Type := mkAutofillField {
  field_id       : Z;
  html_type      : HtmlFieldType;
  html_mode      : HtmlFieldMode;
  heuristic_type : ServerFieldType;
  server_type    : ServerFieldType
}.

(** Maps (HtmlFieldType, HtmlFieldMode)