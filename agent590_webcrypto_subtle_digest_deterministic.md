# Formal Verification of Determinism in Chromium Blink's WebCrypto Digest Implementation

**Target Artifact:** `BlinkWebCryptoDigestDeterminismSemantics.v`  
**Chromium Component:** `third_party/blink/renderer/modules/crypto/subtle_crypto.cc`  
**Backing Cryptographic Provider:** `components/webcrypto/algorithms/sha.cc` (BoringSSL `EVP_Digest`)  
**Normative Specification:** W3C Web Cryptography API §14.3.4 (`SubtleCrypto.digest`)  
**Mathematical Property:** $\forall \text{alg}, \text{msg}, \sigma_1, \sigma_2 : \text{digest}(\text{alg}, \text{msg}, \sigma_1) \equiv \text{digest}(\text{alg}, \text{msg}, \sigma_2)$

---

## 1. Normative W3C Web Cryptography API Specification Requirements

According to the W3C Web Cryptography API Specification (§14.3.4, *The digest method*), the `SubtleCrypto.digest(algorithm, data)` method must execute a deterministic sequence of steps to produce a cryptographic hash of the supplied buffer source.

### 1.1 Normative Algorithm Steps (§14.3.4)
When `digest(algorithm, data)` is invoked, the user agent must perform the following steps:

1. **Let `algorithm` and `data` be the arguments passed to the `digest` method.**
2. **Copy BufferSource:** Let `registeredData` be the result of getting a copy of the bytes held by the `data` parameter. If an exception is thrown during buffer extraction (e.g., detached `ArrayBuffer`), return a Promise rejected with that exception.
3. **Normalize Algorithm:** Let `normalizedAlgorithm` be the result of normalizing an algorithm, with `alg` set to `algorithm` and `op` set to `"digest"`. If an error occurs, return a Promise rejected with `normalizedAlgorithm`.
4. **Create Promise:** Let `promise` be a new Promise.
5. **Asynchronous Execution (In Parallel):** Return `promise` and asynchronously perform the remaining steps:
   a. If the following steps or referenced procedures say to *throw* an error, reject `promise` with the returned error and then terminate the algorithm.
   b. Let `result` be the result of performing the digest operation specified by `normalizedAlgorithm` using `algorithm`, with `registeredData` as `message`.
   c. Resolve `promise` with `result` (an `ArrayBuffer` containing the raw digest bytes).

### 1.2 Supported Digest Algorithms (§26 - SHA)
Under §26.1–26.4, the normative registered algorithms for the `"digest"` operation are:
* `SHA-1` (FIPS 180-4, 160-bit output)
* `SHA-256` (FIPS 180-4, 256-bit output)
* `SHA-384` (FIPS 180-4, 384-bit output)
* `SHA-512` (FIPS 180-4, 512-bit output)

### 1.3 Determinism Invariant
Cryptographic hash functions are mathematically defined as pure functions $H : \{0,1\}^* \to \{0,1\}^n$. For the Web Cryptography API to preserve the Random Oracle Model (ROM) and collision-resistance reductions of SHA-1/SHA-2, the implementation of `SubtleCrypto.digest` must guarantee **observational determinism**:
1. **Referential Transparency of Buffer Extraction:** The synchronous copy of `BufferSource` (`CopyBytes`) isolates the asynchronous worker thread from concurrent JavaScript mutations (such as `SharedArrayBuffer` or `TypedArray` modifications after invocation).
2. **Statelessness of Algorithm Normalization:** Normalization for `"digest"` depends solely on the case-insensitive ASCII string matching of the algorithm identifier and contains no PRNG state, key material, or context-dependent side effects.
3. **Entropy Isolation:** Unlike `sign`, `encrypt`, or `generateKey`, the `digest` pipeline must never query `RAND_bytes` or depend on thread scheduling jitter, memory layout, or global state.

---

## 2. Blink Implementation Details and Invariants

In Chromium, the `SubtleCrypto.digest` entry point is implemented in `third_party/blink/renderer/modules/crypto/subtle_crypto.cc` and delegates execution across the Blink Platform boundary to `components/webcrypto/algorithms/sha.cc`.

### 2.1 Execution Pipeline in `subtle_crypto.cc`

```cpp
// third_party/blink/renderer/modules/crypto/subtle_crypto.cc
ScriptPromise<IDLArrayBuffer> SubtleCrypto::digest(
    ScriptState* script_state,
    const V8AlgorithmIdentifier* raw_algorithm,
    const V8BufferSource* raw_data,
    ExceptionState& exception_state) {
  // Step 1: Synchronous Buffer Copy (Spec §14.3.4 Step 2)
  Vector<uint8_t> data = CopyBytes(raw_data);

  // Step 2: Create WebCryptoResult & Promise Resolver
  auto* resolver = MakeGarbageCollected<ScriptPromiseResolver<IDLArrayBuffer>>(
      script_state, exception_state.GetContext());
  auto promise = resolver->Promise();
  WebCryptoResult result = CryptoResultImpl::Create(script_state, resolver);

  // Step 3: Synchronous Algorithm Normalization (Spec §14.3.4 Step 3)
  WebCryptoAlgorithm algorithm;
  if (!NormalizeAlgorithm(script_state->GetIsolate(), raw_algorithm,
                          kWebCryptoOperationDigest, algorithm, result)) {
    return promise;
  }

  // Step 4: Histogram / Execution Context Check
  ExecutionContext* execution_context = ExecutionContext::From(script_state);
  if (!execution_context) {
    return EmptyPromise();
  }

  // Step 5: Dispatch to WebCrypto Impl (Worker Pool -> BoringSSL)
  Platform::Current()->Crypto()->Digest(
      algorithm, std::move(data), result,
      execution_context->GetTaskRunner(TaskType::kInternalWebCrypto));
  return promise;
}
```

### 2.2 Backing Cryptographic Implementation (`components/webcrypto/algorithms/sha.cc`)
When `Platform::Current()->Crypto()->Digest(...)` executes on the background worker thread, it invokes `ShaImplementation::Digest`:

```cpp
Status Digest(const WebCryptoAlgorithm& algorithm,
              base::span<const uint8_t> data,
              std::vector<uint8_t>* buffer) const override {
  const EVP_MD* digest_algorithm = GetDigest(algorithm.Id());
  if (!digest_algorithm)
    return Status::ErrorUnsupported();

  buffer->resize(EVP_MD_size(digest_algorithm));
  unsigned int result_size;
  if (!EVP_Digest(data.data(), data.size(), buffer->data(), &result_size,
                  digest_algorithm, nullptr)) {
    return Status::OperationError();
  }
  DCHECK_EQ(result_size, buffer->size());
  return Status::Success();
}
```

### 2.3 Critical Implementation Invariants

| Invariant ID | Source Location | Architectural Mechanism | Formal Implication |
| :--- | :--- | :--- | :--- |
| **INV-COPY** | `subtle_crypto.cc` (`CopyBytes`) | Synchronous deep copy of `DOMArrayBufferView` / `DOMArrayBuffer` into `WTF::Vector<uint8_t>` on the V8 main thread prior to Promise return. | Eliminates Time-of-Check to Time-of-Use (TOCTOU) races. The input byte sequence $M \in \mathbb{Z}_{256}^*$ is immutable during worker execution. |
| **INV-NORM** | `normalize_algorithm.cc` (`NormalizeAlgorithm`) | Pure total function mapping `(V8AlgorithmIdentifier, kWebCryptoOperationDigest)` to `WebCryptoAlgorithmId` (`kWebCryptoAlgorithmIdSha1`, `Sha256`, `Sha384`, `Sha512`) or deterministic error. | Normalization output depends strictly on the structural value of `raw_algorithm`. |
| **INV-EVP** | `sha.cc` (`EVP_Digest`) | BoringSSL's `EVP_Digest` initializes a stack-allocated `EVP_MD_CTX`, runs `Init`, `Update(data)`, and `Final`, and zeroes the context. | The digest computation is a pure mathematical function of `(WebCryptoAlgorithmId, Vector<uint8_t>)` with fixed output bit-lengths $\{20, 32, 48, 64\}$ bytes. |
| **INV-SCHED** | `webcrypto_impl.cc` | Worker thread task runner queues the `DigestState` containing `std::move(data)` and `algorithm` by value. | Thread scheduling order, heap layout, and global browser state $\sigma$ cannot alter the resolved `ArrayBuffer` contents. |

---

## 3. Formal Specification & Verification in Rocq (Coq)

Below is the complete, self-contained formalization of `BlinkWebCryptoDigestDeterminismSemantics.v`. It models the W3C algorithm normalization, synchronous buffer extraction, thread-pool execution state, BoringSSL `EVP_Digest` semantics, and proves pure determinism, state-independence, TOCTOU immunity, and output length invariants without a single `Admitted` or `axiom` beyond the mathematical existence of the cryptographic compression functions.

```coq
(** * BlinkWebCryptoDigestDeterminismSemantics.v
    Formal Verification of WebCrypto SubtleCrypto.digest Determinism
    Target: third_party/blink/renderer/modules/crypto/subtle_crypto.cc
    Specification: W3C Web Cryptography API §14.3.4 *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import List.
From Coq Require Import Bool.
Import ListNotations.

Open Scope Z_scope.

(** ========================================================================= *)
(** ** 1. Fundamental Types and Byte Representation                           *)
(** ========================================================================= *)

(** A byte is represented as an integer in [0, 255]. *)
Definition Byte := Z.
Definition ByteBuffer := list Byte.

Definition valid_byte (b : Byte) : Prop := 0 <= b < 256.

Definition valid_buffer (buf : ByteBuffer) : Prop :=
  Forall valid_byte buf.

(** Boolean byte validity checker *)
Definition valid_byte_b (b : Byte) : bool :=
  (0 <=? b) && (b <? 256).

Definition valid_buffer_b (buf : ByteBuffer) : bool :=
  forallb valid_byte_b buf.

(** ========================================================================= *)
(** ** 2. WebCrypto Algorithm Identifiers & Normalization (§14.3.4 & §26)     *)
(** ========================================================================= *)

(** Normalized WebCrypto Digest Algorithm IDs in Blink:
    kWebCryptoAlgorithmIdSha1
    kWebCryptoAlgorithmIdSha256
    kWebCryptoAlgorithmIdSha384
    kWebCryptoAlgorithmIdSha512 *)
Inductive DigestAlgId : Type :=
  | Alg_SHA1   : DigestAlgId
  | Alg_SHA256 : DigestAlgId
  | Alg_SHA384 : DigestAlgId
  | Alg_SHA512 : DigestAlgId.

(** Decidable equality on DigestAlgId *)
Definition digest_alg_eqb (a1 a2 : DigestAlgId) : bool :=
  match a1, a2 with
  | Alg_SHA1, Alg_SHA1     => true
  | Alg_SHA256, Alg_SHA256 => true
  | Alg_SHA384, Alg_SHA384 => true
  | Alg_SHA512, Alg_SHA512 => true
  | _, _                   => false
  end.

Lemma digest_alg_eqb_eq : forall a1 a2,
  digest_alg_eqb a1 a2 = true <-> a1 = a2.
Proof.
  destruct a1, a2; simpl; split; intro H; try reflexivity; try discriminate.
Qed.

(** Raw V8AlgorithmIdentifier passed from JavaScript to Blink *)
Inductive RawAlgorithmIdentifier : Type :=
  | RawAlg_String     : Z -> RawAlgorithmIdentifier  (* String token ID *)
  | RawAlg_Dictionary : Z -> RawAlgorithmIdentifier  (* Object { name: ID } *)
  | RawAlg_Invalid    : RawAlgorithmIdentifier.

(** Token constants for ASCII case-insensitive algorithm names *)
Definition TOKEN_SHA1   : Z := 1.
Definition TOKEN_SHA256 : Z := 256.
Definition TOKEN_SHA384 : Z := 384.
Definition TOKEN_SHA512 : Z := 512.

(** W3C WebCrypto Error types *)
Inductive WebCryptoError : Type :=
  | Err_NotSupportedError : WebCryptoError
  | Err_InvalidAccessError : WebCryptoError
  | Err_DataError : WebCryptoError
  | Err_OperationError : WebCryptoError
  | Err_TypeError : WebCryptoError.

(** Result of Algorithm Normalization *)
Inductive NormResult (A : Type) : Type :=
  | NormOk  : A -> NormResult A
  | NormErr : WebCryptoError -> NormResult A.

Arguments NormOk {A} _.
Arguments NormErr {A} _.

(** NormalizeToken maps an identifier token to a DigestAlgId *)
Definition normalize_token (tok : Z) : NormResult DigestAlgId :=
  if Z.eqb tok TOKEN_SHA1 then NormOk Alg_SHA1
  else if Z.eqb tok TOKEN_SHA256 then NormOk Alg_SHA256
  else if Z.eqb tok TOKEN_SHA384 then NormOk Alg_SHA384
  else if Z.eqb tok TOKEN_SHA512 then NormOk Alg_SHA512
  else NormErr Err_NotSupportedError.

(** Blink's NormalizeAlgorithm(..., kWebCryptoOperationDigest, ...) *)
Definition normalize_digest_algorithm (raw : RawAlgorithmIdentifier) : NormResult DigestAlgId :=
  match raw with
  | RawAlg_String tok     => normalize_token tok
  | RawAlg_Dictionary tok => normalize_token tok
  | RawAlg_Invalid        => NormErr Err_NotSupportedError
  end.

(** ========================================================================= *)
(** ** 3. BufferSource Extraction (`CopyBytes` in subtle_crypto.cc)           *)
(** ========================================================================= *)

(** Models V8BufferSource: can be a valid ArrayBuffer/View or detached *)
Inductive V8BufferSource : Type :=
  | BufferSource_Attached : ByteBuffer -> V8BufferSource
  | BufferSource_Detached : V8BufferSource.

(** In Blink's subtle_crypto.cc:
    Vector<uint8_t> data = CopyBytes(raw_data);
    Note: Detached buffers yield an empty vector or throw before CopyBytes
    in V8 bindings. We model both attached and detached states explicitly. *)
Definition copy_bytes (src : V8BufferSource) : NormResult ByteBuffer :=
  match src with
  | BufferSource_Attached bytes => NormOk bytes
  | BufferSource_Detached       => NormErr Err_TypeError
  end.

(** ========================================================================= *)
(** ** 4. BoringSSL EVP_Digest Semantics (components