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
        "id": 593,
        "filename": "agent593_webauthn_rp_id_domain_match.md",
        "topic": "WebAuthn Relying Party ID origin domain suffix match",
        "source": "third_party/blink/renderer/modules/credentialmanagement/credential_manager_type_converters.cc",
        "spec": "WebAuthn Level 3 §5.1.3",
        "theory": "BlinkWebAuthnRPSuffixMatchSemantics.v",
        "math": "rp_id_valid(rp, origin) = is_suffix(rp, origin) && not_public_suffix(rp)."
    },
    {
        "id": 594,
        "filename": "agent594_webauthn_client_data_json_hash.md",
        "topic": "WebAuthn clientDataJSON challenge SHA-256 byte digest size",
        "source": "third_party/blink/renderer/modules/credentialmanagement/authenticator_common.cc",
        "spec": "WebAuthn Level 3 §5.8.1",
        "theory": "BlinkWebAuthnClientDataHashSemantics.v",
        "math": "client_data_hash_length = 32 bytes (SHA-256)."
    },
    {
        "id": 595,
        "filename": "agent595_webauthn_authenticator_data_flags.md",
        "topic": "WebAuthn authenticatorData flags bitmask verification",
        "source": "device/fido/authenticator_data.cc",
        "spec": "WebAuthn Level 3 §6.1",
        "theory": "BlinkWebAuthnAuthDataFlagsSemantics.v",
        "math": "UP=0x01, UV=0x04, BE=0x08, BS=0x10, AT=0x40, ED=0x80; bitwise flag checks."
    },
    {
        "id": 596,
        "filename": "agent596_webauthn_sign_count_monotonic.md",
        "topic": "WebAuthn signCount strictly increasing monotonicity",
        "source": "device/fido/authenticator_data.cc",
        "spec": "WebAuthn Level 3 §6.1",
        "theory": "BlinkWebAuthnSignCountMonotonicitySemantics.v",
        "math": "sign_count_valid(prev, next) = (prev =? 0) || (prev <? next)."
    },
    {
        "id": 597,
        "filename": "agent597_webauthn_attestation_format.md",
        "topic": "WebAuthn attestation statement format validation",
        "source": "device/fido/attestation_statement_formats.cc",
        "spec": "WebAuthn Level 3 §8",
        "theory": "BlinkWebAuthnAttestationFormatSemantics.v",
        "math": "formats: none(0), packed(1), fido_u2f(2), tpm(3), android_key(4)."
    },
    {
        "id": 598,
        "filename": "agent598_webauthn_user_verification_requirement.md",
        "topic": "WebAuthn userVerification requirement satisfiability",
        "source": "third_party/blink/renderer/modules/credentialmanagement/credential_manager_type_converters.cc",
        "spec": "WebAuthn Level 3 §5.1.2",
        "theory": "BlinkWebAuthnUserVerificationSemantics.v",
        "math": "uv_satisfied(req, uv_flag) = (req =? DISCOURAGED) || ((req =? PREFERRED) || (uv_flag =? true))."
    },
    {
        "id": 599,
        "filename": "agent599_webauthn_resident_key_flag.md",
        "topic": "WebAuthn residentKey / discoverable credential flag consistency",
        "source": "device/fido/authenticator_data.cc",
        "spec": "WebAuthn Level 3 §5.1.2",
        "theory": "BlinkWebAuthnResidentKeyFlagSemantics.v",
        "math": "resident_key_consistent(rk_req, be_flag) = ...;"
    },
    {
        "id": 600,
        "filename": "agent600_webauthn_cose_algorithm.md",
        "topic": "WebAuthn public key COSE algorithm identifier matching",
        "source": "device/fido/fido_constants.cc",
        "spec": "RFC 9053 §2.1",
        "theory": "BlinkWebAuthnCOSEAlgorithmSemantics.v",
        "math": "COSE_ES256 = -7; COSE_RS256 = -257; COSE_EDDSA = -8."
    },
    {
        "id": 601,
        "filename": "agent601_webauthn_credential_id_length.md",
        "topic": "WebAuthn credential ID length bounds (length <= 1023 bytes)",
        "source": "device/fido/fido_constants.cc",
        "spec": "WebAuthn Level 3 §5.1.3",
        "theory": "BlinkWebAuthnCredentialIDLengthSemantics.v",
        "math": "valid_cred_id_len(l) = (0 <? l) && (l <=? 1023)."
    },
    {
        "id": 602,
        "filename": "agent602_webauthn_extension_outputs_idempotent.md",
        "topic": "WebAuthn extension outputs evaluation idempotence",
        "source": "third_party/blink/renderer/modules/credentialmanagement/credential_manager_type_converters.cc",
        "spec": "WebAuthn Level 3 §9",
        "theory": "BlinkWebAuthnExtensionOutputsSemantics.v",
        "math": "extension_output_eval(inputs) == extension_output_eval(inputs); idempotent evaluation."
    },
    {
        "id": 603,
        "filename": "agent603_credentials_mediation_mode.md",
        "topic": "Credential Management navigator.credentials.get mediation modes",
        "source": "third_party/blink/renderer/modules/credentialmanagement/credentials_container.cc",
        "spec": "Credential Management Level 1 §4",
        "theory": "BlinkCredentialsMediationModeSemantics.v",
        "math": "modes: silent(0), optional(1), required(2), conditional(3)."
    },
    {
        "id": 604,
        "filename": "agent604_password_credential_non_empty.md",
        "topic": "PasswordCredential username/password non-empty validity",
        "source": "third_party/blink/renderer/modules/credentialmanagement/password_credential.cc",
        "spec": "Credential Management Level 1 §5.1",
        "theory": "BlinkPasswordCredentialNonEmptySemantics.v",
        "math": "valid_password_cred(u_len, p_len) = (0 <? u_len) && (0 <? p_len)."
    },
    {
        "id": 605,
        "filename": "agent605_federated_credential_origin_valid.md",
        "topic": "FederatedCredential IDP provider URL origin validity",
        "source": "third_party/blink/renderer/modules/credentialmanagement/federated_credential.cc",
        "spec": "Credential Management Level 1 §5.2",
        "theory": "BlinkFederatedCredentialOriginSemantics.v",
        "math": "is_valid_idp_origin(scheme) = (scheme =? SCHEME_HTTPS)."
    },
    {
        "id": 606,
        "filename": "agent606_digital_credentials_encapsulation.md",
        "topic": "Digital Credentials API protocol request encapsulation",
        "source": "third_party/blink/renderer/modules/credentialmanagement/digital_identity_credential.cc",
        "spec": "Digital Credentials API §3",
        "theory": "BlinkDigitalCredentialsProtocolSemantics.v",
        "math": "protocol_supported(p) = (p =? 1) || (p =? 2) (OpenID4VP, ISO-18013-5)."
    },
    {
        "id": 607,
        "filename": "agent607_webauthn_timeout_clamping.md",
        "topic": "WebAuthn timeout clamping to engine bounds (min 1000ms, max 600000ms)",
        "source": "device/fido/fido_constants.cc",
        "spec": "WebAuthn Level 3 §5.1.3",
        "theory": "BlinkWebAuthnTimeoutClampingSemantics.v",
        "math": "clamped_timeout(t) = min(600000, max(1000, t)); 1000 <= clamped <= 600000."
    },
    {
        "id": 608,
        "filename": "agent608_webauthn_abort_signal_cancellation.md",
        "topic": "WebAuthn abort signal cancellation responsiveness",
        "source": "third_party/blink/renderer/modules/credentialmanagement/authenticator_common.cc",
        "spec": "WebAuthn Level 3 §5.1.3",
        "theory": "BlinkWebAuthnAbortSignalSemantics.v",
        "math": "is_aborted(sig_state) = (sig_state =? 1); aborted operations reject immediately."
    }
]

def run_agent(agent):
    prompt = f"""You are a formal methods expert and WebAuthn / Passkeys security researcher analyzing Chromium Blink's Credential Management architecture.
Topic: {agent['topic']}
Chromium Source: {agent['source']}
Specification: {agent['spec']}
Formal Theory Target: {agent['theory']}
Mathematical Property: {agent['math']}

Write a comprehensive research report in Markdown covering:
1. Exact normative W3C WebAuthn / W3C Credential Management specification requirements.
2. Blink implementation details and invariants in {agent['source']}.
3. Formal specification definitions in Rocq/Coq (types, functions, predicates).
4. Concrete theorems with complete, admitted-free Rocq/Coq proofs using ZArith/Lia/Bool.
5. Verification analysis proving 0 admits and preservation of authentication invariants.

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
            f.write(f"Wave43-Agent{agent['id']},{MODEL_NAME},{prompt_tokens},{cand_tokens},{duration:.2f}\n")
        return True
    except Exception as e:
        print(f"[Agent {agent['id']}] FAILED: {e}")
        return False

print(f"Launching 16 concurrent agents for Wave 43 using {MODEL_NAME}...")
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
    futures = [executor.submit(run_agent, agent) for agent in AGENTS]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

print(f"Wave 43 complete: {sum(results)}/16 succeeded.")
