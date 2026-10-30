import os
import time
import concurrent.futures
from google import genai
from google.genai import types

API_KEY = os.environ.get("GEMINI_API_KEY")
if not API_KEY and os.path.exists("key.txt"):
    with open("key.txt", "r") as f:
        API_KEY = f.read().strip()

client = genai.Client(api_key=API_KEY)
MODEL_NAME = "gemini-4-argon"

AGENTS = [
    {
        "id": 625,
        "filename": "agent625_payment_amount_decimal_format.md",
        "topic": "W3C Payment Request decimal amount format and parsing",
        "source": "third_party/blink/renderer/modules/payments/payment_request.cc",
        "spec": "Payment Request API §5.5 PaymentCurrencyAmount value syntax",
        "theory": "BlinkPaymentAmountDecimalFormatSemantics.v",
        "math": "is_valid_amount_str(s) = matches_decimal(s) && no_leading_plus."
    },
    {
        "id": 626,
        "filename": "agent626_payment_total_non_negativity.md",
        "topic": "W3C Payment Request total amount non-negativity constraint",
        "source": "third_party/blink/renderer/modules/payments/payment_request.cc",
        "spec": "Payment Request API §5.5 total.amount.value must not be negative",
        "theory": "BlinkPaymentTotalNonNegativitySemantics.v",
        "math": "total_non_negative(val) = val >= 0; negative total throws TypeError."
    },
    {
        "id": 627,
        "filename": "agent627_payment_shipping_option_uniqueness.md",
        "topic": "W3C Payment Request shipping options ID uniqueness",
        "source": "third_party/blink/renderer/modules/payments/payment_request.cc",
        "spec": "Payment Request API §5.6 shippingOptions ID uniqueness",
        "theory": "BlinkPaymentShippingOptionUniquenessSemantics.v",
        "math": "all_unique_ids(opts) = forall i <> j, opts[i].id <> opts[j].id."
    },
    {
        "id": 628,
        "filename": "agent628_payment_method_identifier_validation.md",
        "topic": "W3C Payment Request payment method identifier syntax validation",
        "source": "third_party/blink/renderer/modules/payments/payment_request.cc",
        "spec": "Payment Method Identifiers §2 (standardized vs URL-based)",
        "theory": "BlinkPaymentMethodIdentifierSemantics.v",
        "math": "is_valid_method_id(id) = is_standardized(id) || (is_absolute_url(id) && is_https(id))."
    },
    {
        "id": 629,
        "filename": "agent629_payment_details_modifier_override.md",
        "topic": "W3C Payment Request PaymentDetailsModifier total override semantics",
        "source": "third_party/blink/renderer/modules/payments/payment_response.cc",
        "spec": "Payment Request API §5.7 PaymentDetailsModifier method matching",
        "theory": "BlinkPaymentDetailsModifierOverrideSemantics.v",
        "math": "effective_total(base, mods, method) = match_mod(mods, method).total.value_or(base)."
    },
    {
        "id": 630,
        "filename": "agent630_payment_validation_errors_empty.md",
        "topic": "W3C Payment Request PaymentValidationErrors emptiness check",
        "source": "third_party/blink/renderer/modules/payments/payment_request.cc",
        "spec": "Payment Request API §5.8 PaymentValidationErrors dictionary",
        "theory": "BlinkPaymentValidationErrorsSemantics.v",
        "math": "has_no_errors(errs) = (errs.error == None /\ errs.shippingAddress == None)."
    },
    {
        "id": 631,
        "filename": "agent631_payment_response_complete_status.md",
        "topic": "W3C Payment Request complete() terminal state transition",
        "source": "third_party/blink/renderer/modules/payments/payment_response.cc",
        "spec": "Payment Request API §6.2 PaymentResponse.complete(result)",
        "theory": "BlinkPaymentResponseCompleteStatusSemantics.v",
        "math": "complete(state, res) transitions from Responding to Closed; cannot complete twice."
    },
    {
        "id": 632,
        "filename": "agent632_autofill_field_classification.md",
        "topic": "HTML Autofill field name categories disjointness",
        "source": "components/autofill/core/browser/autofill_field.cc",
        "spec": "HTML Spec §4.10.18.7 autofill field name tokens",
        "theory": "BlinkAutofillFieldClassificationSemantics.v",
        "math": "category_partition: address, billing, credit_card, contact are pairwise disjoint."
    },
    {
        "id": 633,
        "filename": "agent633_autofill_section_prefix_scoping.md",
        "topic": "HTML Autofill section-* prefix scoping and separation",
        "source": "components/autofill/core/browser/autofill_field.cc",
        "spec": "HTML Spec §4.10.18.7 section-* prefix token",
        "theory": "BlinkAutofillSectionPrefixSemantics.v",
        "math": "parse_section(tok) = if starts_with('section-', tok) then Some(strip(tok)) else Default."
    },
    {
        "id": 634,
        "filename": "agent634_credit_card_expiry_normalization.md",
        "topic": "Autofill credit card expiry date normalization and clamping",
        "source": "components/autofill/core/browser/data_model/credit_card.cc",
        "spec": "Autofill credit card expiration month [1, 12] and 2-to-4 digit year expansion",
        "theory": "BlinkCreditCardExpiryNormalizationSemantics.v",
        "math": "norm_year(yy) = if yy < 100 then 2000 + yy else yy; 1 <= mm <= 12."
    },
    {
        "id": 635,
        "filename": "agent635_luhn_checksum_algorithm.md",
        "topic": "Credit card Luhn mod 10 checksum algorithm soundness",
        "source": "components/autofill/core/browser/validation.cc",
        "spec": "ISO/IEC 7812-1 / Luhn mod 10 formula",
        "theory": "BlinkLuhnChecksumAlgorithmSemantics.v",
        "math": "luhn_sum(digits) mod 10 = 0 <-> valid card number checksum."
    },
    {
        "id": 636,
        "filename": "agent636_phone_number_e164_normalization.md",
        "topic": "Autofill phone number E.164 ITU-T format normalization",
        "source": "components/autofill/core/browser/data_model/phone_number.cc",
        "spec": "ITU-T E.164 phone number international format",
        "theory": "BlinkPhoneNumberE164NormalizationSemantics.v",
        "math": "is_valid_e164(p) = starts_with_plus(p) && (1 <= digit_count(p) <= 15)."
    },
    {
        "id": 637,
        "filename": "agent637_payment_request_show_user_gesture.md",
        "topic": "PaymentRequest show() user activation requirement",
        "source": "third_party/blink/renderer/modules/payments/payment_request.cc",
        "spec": "Payment Request API §5.2 show() transient user activation",
        "theory": "BlinkPaymentRequestShowUserGestureSemantics.v",
        "math": "can_show(has_gesture, is_active) = has_gesture && !is_active."
    },
    {
        "id": 638,
        "filename": "agent638_payment_request_active_exclusivity.md",
        "topic": "PaymentRequest at most one active request exclusivity",
        "source": "third_party/blink/renderer/modules/payments/payment_request.cc",
        "spec": "Payment Request API §5.2 only one PaymentRequest active at once",
        "theory": "BlinkPaymentRequestActiveExclusivitySemantics.v",
        "math": "active_count(state) <= 1."
    },
    {
        "id": 639,
        "filename": "agent639_payment_handler_delegation_origin.md",
        "topic": "Payment Handler API delegated payment client origin match",
        "source": "third_party/blink/renderer/modules/payments/payment_handler_utils.cc",
        "spec": "Payment Handler API §4.1 delegated payment client origin validation",
        "theory": "BlinkPaymentHandlerDelegationOriginSemantics.v",
        "math": "is_authorized_delegation(client_origin, handler_origin) = (client_origin == handler_origin)."
    },
    {
        "id": 640,
        "filename": "agent640_can_make_payment_boolean_determinism.md",
        "topic": "PaymentRequest canMakePayment() boolean determinism",
        "source": "third_party/blink/renderer/modules/payments/payment_request.cc",
        "spec": "Payment Request API §5.3 canMakePayment() query idempotence",
        "theory": "BlinkCanMakePaymentBooleanDeterminismSemantics.v",
        "math": "state_after_query = state_before_query; returns true or false deterministically."
    }
]

def run_agent(agent):
    prompt = f"""You are formal verification Agent {agent['id']} specializing in Web Payments, Autofill & Form Normalization in Chromium Blink and W3C specifications.
Topic: {agent['topic']}
Chromium Source: {agent['source']}
Specification: {agent['spec']}
Formal Theory Target: {agent['theory']}
Mathematical Property: {agent['math']}

Write a comprehensive research report in Markdown covering:
1. Exact normative W3C Payment Request / HTML Autofill specification requirements.
2. Blink implementation details and invariants in {agent['source']}.
3. Formal specification definitions in Rocq/Coq (types, functions, predicates).
4. Concrete theorems with complete, admitted-free Rocq/Coq proofs using ZArith/Lia/Bool/List.
5. Verification analysis proving 0 admits and preservation of payment invariants.

Respond with the report in Markdown format."""

    config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_budget=2048),
        max_output_tokens=3500,
        temperature=0.2,
    )
    
    t0 = time.time()
    try:
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=prompt,
            config=config,
        )
        duration = time.time() - t0
        content = response.text
        with open(agent["filename"], "w") as f:
            f.write(content)
        
        usage = response.usage_metadata
        prompt_tokens = usage.prompt_token_count if usage else 0
        cand_tokens = usage.candidates_token_count if usage else 0
        print(f"[Agent {agent['id']}] Done in {duration:.1f}s | tokens: in={prompt_tokens}, out={cand_tokens}")
        with open("token_usage.log", "a") as f:
            f.write(f"Wave45-Agent{agent['id']},{MODEL_NAME},{prompt_tokens},{cand_tokens},{duration:.2f}\n")
        return True
    except Exception as e:
        print(f"[Agent {agent['id']}] FAILED: {e}")
        return False

print(f"Launching 16 concurrent agents for Wave 45 using {MODEL_NAME}...")
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
    futures = [executor.submit(run_agent, agent) for agent in AGENTS]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

print(f"Wave 45 complete: {sum(results)}/16 succeeded.")
