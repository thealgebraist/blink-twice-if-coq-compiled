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
        "id": 577,
        "filename": "agent577_webcrypto_aes_gcm_tag_length.md",
        "topic": "WebCrypto AES-GCM tag length verification",
        "source": "third_party/blink/renderer/modules/crypto/aes_gcm_params.cc",
        "spec": "Web Cryptography API §21.2",
        "theory": "BlinkWebCryptoAESGCMTagLengthSemantics.v",
        "math": "is_valid_tag_length(l) = (l =? 96) || (l =? 104) || (l =? 112) || (l =? 120) || (l =? 128)."
    },
    {
        "id": 578,
        "filename": "agent578_webcrypto_aes_cbc_iv_length.md",
        "topic": "WebCrypto AES-CBC IV length requirement",
        "source": "third_party/blink/renderer/modules/crypto/aes_cbc_params.cc",
        "spec": "Web Cryptography API §20.2",
        "theory": "BlinkWebCryptoAESCBCIVLengthSemantics.v",
        "math": "is_valid_iv_length(l) = (l =? 16)."
    },
    {
        "id": 579,
        "filename": "agent579_webcrypto_aes_ctr_counter_length.md",
        "topic": "WebCrypto AES-CTR counter length requirement",
        "source": "third_party/blink/renderer/modules/crypto/aes_ctr_params.cc",
        "spec": "Web Cryptography API §22.2",
        "theory": "BlinkWebCryptoAESCTRCounterLengthSemantics.v",
        "math": "is_valid_counter_length(l) = (l =? 16)."
    },
    {
        "id": 580,
        "filename": "agent580_webcrypto_rsa_modulus_length.md",
        "topic": "WebCrypto RSA key modulus length minimum",
        "source": "third_party/blink/renderer/modules/crypto/rsa_key_gen_params.cc",
        "spec": "Web Cryptography API §23.2",
        "theory": "BlinkWebCryptoRSAModulusLengthSemantics.v",
        "math": "is_valid_modulus_length(bits) = (2048 <=? bits)."
    },
    {
        "id": 581,
        "filename": "agent581_webcrypto_hmac_hash_length.md",
        "topic": "WebCrypto HMAC digest output length",
        "source": "third_party/blink/renderer/modules/crypto/hmac_params.cc",
        "spec": "Web Cryptography API §28.2",
        "theory": "BlinkWebCryptoHMACHashLengthSemantics.v",
        "math": "hmac_output_bytes(hash_alg) = (if hash_alg =? 256 then 32 else if hash_alg =? 512 then 64 else 0)."
    },
    {
        "id": 582,
        "filename": "agent582_webcrypto_ecdsa_curve_spec.md",
        "topic": "WebCrypto ECDSA named curve validity",
        "source": "third_party/blink/renderer/modules/crypto/ec_key_gen_params.cc",
        "spec": "Web Cryptography API §24.2",
        "theory": "BlinkWebCryptoECDSACurveSpecSemantics.v",
        "math": "is_valid_curve(c) = (c =? 256) || (c =? 384) || (c =? 521)."
    },
    {
        "id": 583,
        "filename": "agent583_webcrypto_cryptokey_extractable.md",
        "topic": "WebCrypto CryptoKey extractable boolean immutability",
        "source": "third_party/blink/renderer/modules/crypto/crypto_key.cc",
        "spec": "Web Cryptography API §13.1",
        "theory": "BlinkWebCryptoCryptoKeyExtractableSemantics.v",
        "math": "extractable property is strictly immutable across key lifetime."
    },
    {
        "id": 584,
        "filename": "agent584_webcrypto_key_usage_bitset.md",
        "topic": "WebCrypto KeyUsage bitset permission containment",
        "source": "third_party/blink/renderer/modules/crypto/crypto_key.cc",
        "spec": "Web Cryptography API §13.2",
        "theory": "BlinkWebCryptoKeyUsageBitsetSemantics.v",
        "math": "has_key_usage(mask, usage) = (Z.land mask usage =? usage)."
    },
    {
        "id": 585,
        "filename": "agent585_webcrypto_derive_key_algorithm.md",
        "topic": "WebCrypto deriveKey algorithm constraint check",
        "source": "third_party/blink/renderer/modules/crypto/subtle_crypto.cc",
        "spec": "Web Cryptography API §14.3.8",
        "theory": "BlinkWebCryptoDeriveKeyAlgorithmSemantics.v",
        "math": "derive_key_allowed(base_usage) = has_key_usage(base_usage, USAGE_DERIVE_KEY)."
    },
    {
        "id": 586,
        "filename": "agent586_webcrypto_get_random_values_quota.md",
        "topic": "WebCrypto getRandomValues quota bounding",
        "source": "third_party/blink/renderer/modules/crypto/crypto.cc",
        "spec": "Web Cryptography API §10.1",
        "theory": "BlinkWebCryptoGetRandomValuesQuotaSemantics.v",
        "math": "valid_random_bytes(sz) = (sz <=? 65536) && (0 <=? sz)."
    },
    {
        "id": 587,
        "filename": "agent587_webcrypto_pbkdf2_iterations.md",
        "topic": "WebCrypto PBKDF2 iterations positive integer",
        "source": "third_party/blink/renderer/modules/crypto/pbkdf2_params.cc",
        "spec": "Web Cryptography API §30.2",
        "theory": "BlinkWebCryptoPBKDF2IterationsSemantics.v",
        "math": "valid_iterations(iter) = (1 <=? iter)."
    },
    {
        "id": 588,
        "filename": "agent588_webcrypto_hkdf_info_length.md",
        "topic": "WebCrypto HKDF info parameter byte length bound",
        "source": "third_party/blink/renderer/modules/crypto/hkdf_params.cc",
        "spec": "RFC 5869 §2.3",
        "theory": "BlinkWebCryptoHKDFInfoLengthSemantics.v",
        "math": "valid_hkdf_info(len) = (0 <=? len) && (len <=? 65536)."
    },
    {
        "id": 589,
        "filename": "agent589_webcrypto_import_key_format.md",
        "topic": "WebCrypto importKey format discrimination",
        "source": "third_party/blink/renderer/modules/crypto/subtle_crypto.cc",
        "spec": "Web Cryptography API §14.3.9",
        "theory": "BlinkWebCryptoImportKeyFormatSemantics.v",
        "math": "formats: raw(1), pkcs8(2), spki(3), jwk(4)."
    },
    {
        "id": 590,
        "filename": "agent590_webcrypto_subtle_digest_deterministic.md",
        "topic": "WebCrypto subtle digest determinism",
        "source": "third_party/blink/renderer/modules/crypto/subtle_crypto.cc",
        "spec": "Web Cryptography API §14.3.4",
        "theory": "BlinkWebCryptoDigestDeterminismSemantics.v",
        "math": "digest(alg, msg) == digest(alg, msg); pure determinism."
    },
    {
        "id": 591,
        "filename": "agent591_webcrypto_wrapping_key_usage.md",
        "topic": "WebCrypto wrapping key usage enforcement",
        "source": "third_party/blink/renderer/modules/crypto/subtle_crypto.cc",
        "spec": "Web Cryptography API §14.3.11",
        "theory": "BlinkWebCryptoWrappingKeyUsageSemantics.v",
        "math": "can_wrap(key_usages) = has_key_usage(key_usages, USAGE_WRAP_KEY)."
    },
    {
        "id": 592,
        "filename": "agent592_webcrypto_constant_time_compare.md",
        "topic": "WebCrypto constant-time buffer comparison soundness",
        "source": "third_party/boringssl/src/crypto/mem.c",
        "spec": "W3C WebCrypto Security Considerations §3",
        "theory": "BlinkWebCryptoConstantTimeCompareSemantics.v",
        "math": "ct_compare(b1, b2) = (b1 =? b2); sound boolean equality."
    }
]

def run_agent(agent):
    prompt = f"""You are a formal methods expert and Web Cryptography researcher analyzing Chromium Blink's WebCrypto and BoringSSL architecture.
Topic: {agent['topic']}
Chromium Source: {agent['source']}
Specification: {agent['spec']}
Formal Theory Target: {agent['theory']}
Mathematical Property: {agent['math']}

Write a comprehensive research report in Markdown covering:
1. Exact normative W3C Web Cryptography API specification requirements.
2. Blink implementation details and invariants in {agent['source']}.
3. Formal specification definitions in Rocq/Coq (types, functions, predicates).
4. Concrete theorems with complete, admitted-free Rocq/Coq proofs using ZArith/Lia/Bool.
5. Verification analysis proving 0 admits and preservation of cryptographic security bounds.

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
            f.write(f"Wave42-Agent{agent['id']},{MODEL_NAME},{prompt_tokens},{cand_tokens},{duration:.2f}\n")
        return True
    except Exception as e:
        print(f"[Agent {agent['id']}] FAILED: {e}")
        return False

print(f"Launching 16 concurrent agents for Wave 42 using {MODEL_NAME}...")
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
    futures = [executor.submit(run_agent, agent) for agent in AGENTS]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

print(f"Wave 42 complete: {sum(results)}/16 succeeded.")
