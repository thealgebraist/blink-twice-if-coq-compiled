# Formal Verification of WebCrypto PBKDF2 Iterations Validation in Chromium Blink

**Author:** Formal Methods & Web Cryptography Research Group  
**Target Component:** `third_party/blink/renderer/modules/crypto/pbkdf2_params.cc` (and `normalize_algorithm.cc` / `components/webcrypto/algorithms/pbkdf2.cc`)  
**Normative Specification:** W3C Web Cryptography API §30.2 / §30.4  
**Formal Artifact:** `BlinkWebCryptoPBKDF2IterationsSemantics.v`  

---

## 1. Normative W3C Web Cryptography API Specification Requirements

In the W3C Web Cryptography API specification, the Password-Based Key Derivation Function 2 (PBKDF2) is parameterized by the `Pbkdf2Params` dictionary defined in **Section 30.2 (`Pbkdf2Params` dictionary)**:

```webidl
dictionary Pbkdf2Params : Algorithm {
  required BufferSource salt;
  required [EnforceRange] unsigned long iterations;
  required HashAlgorithmIdentifier hash;
};
```

### Normative Behavioral Invariants (§30.4 PBKDF2 Operations)
Under **Section 30.4 (Operations — Derive Bits)**, the specification mandates strict validation of the `iterations` parameter prior to invoking the underlying cryptographic primitive (RFC 8018, Section 5.2):

1. **WebIDL Type Conversion (`[EnforceRange] unsigned long`):**
   - The JavaScript Number passed as `iterations` is converted to an `unsigned long` ($[0, 2^{32}-1]$) via the WebIDL `[EnforceRange]` extended attribute.
   - If the input is `NaN`, $+\infty$, $-\infty$, or after rounding (`floor(abs(x)) * sign(x)`) lies strictly outside the closed interval $[0, 2^{32}-1]$, a JavaScript `TypeError` is thrown during dictionary normalization.
2. **Cryptographic Positivity Check (§30.4 Derive Bits, Step 2):**
   > *"If the `iterations` member of `normalizedAlgorithm` is zero, then throw an `OperationError`."*

Consequently, the complete normative acceptance domain for `iterations` across the WebIDL boundary and the algorithm normalization phase is the closed integer interval:
$$\text{Iterations}_{\text{valid}} = \{ k \in \mathbb{Z} \mid 1 \le k \le 2^{32} - 1 \}$$
Focusing specifically on the post-WebIDL algorithmic validation step (`uint32_t` domain), the core mathematical predicate governing the `OperationError` gate is:
$$\text{valid\_iterations}(\text{iter}) \iff 1 \le \text{iter}$$

---

## 2. Chromium Blink & WebCrypto Implementation Details

In Chromium's architecture, WebCrypto parameter normalization and execution span the Blink renderer bindings (`third_party/blink/renderer/modules/crypto/`) and the WebCrypto implementation layer (`components/webcrypto/algorithms/pbkdf2.cc`).

### Blink Normalization & Parameter Passing
When `SubtleCrypto.deriveBits()` or `SubtleCrypto.deriveKey()` is invoked with `"PBKDF2"`, Blink converts the V8 JavaScript object into a `V8Pbkdf2Params` instance and normalizes it into a `WebCryptoAlgorithmParams` structure (`WebCryptoPbkdf2Params` defined in `third_party/blink/public/platform/web_crypto_algorithm_params.h` and instantiated during algorithm normalization):

```cpp
// Conceptual representation of Blink PBKDF2 parameter normalization
// and WebCrypto execution gate:
bool ParsePbkdf2Params(const V8Pbkdf2Params* raw_params,
                       std::unique_ptr<WebCryptoAlgorithmParams>& out_params,
                       ExceptionState& exception_state) {
  // 1. WebIDL [EnforceRange] unsigned long guarantees raw_params->iterations()
  //    is a valid uint32_t in [0, 4294967295].
  uint32_t iterations = raw_params->iterations();

  // 2. W3C WebCrypto API §30.4 Step 2:
  //    If iterations is 0, reject with OperationError.
  if (iterations == 0) {
    // Rejects promise with DOMException(OperationError,
    // "PBKDF2 requires iterations > 0")
    return false;
  }

  out_params = std::make_unique<WebCryptoPbkdf2Params>(
      normalized_hash, std::move(salt), iterations);
  return true;
}
```

### BoringSSL Boundary Invariant (`PKCS5_PBKDF2_HMAC`)
Downstream in `components/webcrypto/algorithms/pbkdf2.cc`, Chromium invokes BoringSSL's `PKCS5_PBKDF2_HMAC`:

```cpp
Status DeriveBits(const blink::WebCryptoAlgorithm& algorithm,
                  const blink::WebCryptoKey& base_key,
                  bool has_optional_length_bits,
                  unsigned int optional_length_bits,
                  std::vector<uint8_t>* derived_bytes) const override {
  const blink::WebCryptoPbkdf2Params* params = algorithm.Pbkdf2Params();

  if (params->Iterations() == 0)
    return Status::ErrorPbkdf2Iterations0(); // Maps to Blink OperationError
  ...
  if (!PKCS5_PBKDF2_HMAC(
          reinterpret_cast<const char*>(password.data()), password.size(),
          params->Salt().data(), params->Salt().size(),
          params->Iterations(), evp_md, derived_bytes->size(),
          derived_bytes->data())) {
    return Status::OperationError();
  }
  return Status::Success();
}
```

#### Critical Security & Correctness Invariants:
1. **Zero-Iteration Rejection:** RFC 8018 defines the core PRF iteration loop $U_1 \oplus U_2 \oplus \dots \oplus U_c$ for $c \ge 1$. If $c = 0$ were permitted to reach an unguarded loop or treated as a no-op, the derived key material would either be uninitialized, all-zeros, or trigger an integer underflow ($c - 1 = \text{UINT\_MAX}$) resulting in a catastrophic denial-of-service (DoS).
2. **Signed/Unsigned Conversion Safety (`uint32_t` to `unsigned`):** Blink stores `iterations` as `unsigned` (`uint32_t`). BoringSSL's `PKCS5_PBKDF2_HMAC` accepts `unsigned iterations` (unlike OpenSSL 1.1.1 which historically took `int iter` and suffered from negative wrap-around vulnerabilities if $iter > 2^{31}-1$). By enforcing $1 \le \text{iter} \le 2^{32}-1$, Blink guarantees well-defined, non-degenerate execution in BoringSSL.

---

## 3. Formal Specification in Rocq / Coq

Below is the self-contained formalization `BlinkWebCryptoPBKDF2IterationsSemantics.v`. It models the WebIDL `[EnforceRange]` domain, the W3C §30.2/§30.4 specification predicate, the Blink/WebCrypto boolean guard `valid_iterations(iter) = (1 <=? iter)`, the full state transition system yielding `WebCryptoResult`, and the BoringSSL `PKCS5_PBKDF2_HMAC` precondition contract.

```coq
(** * BlinkWebCryptoPBKDF2IterationsSemantics.v
    Formal Verification of WebCrypto PBKDF2 Iterations Validation
    Chromium Source: third_party/blink/renderer/modules/crypto/pbkdf2_params.cc
    Specification: W3C Web Cryptography API §30.2 & §30.4 *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Bool.Bool.
Require Import Coq.Micromega.Lia.

Open Scope Z_scope.

(** ** 1. Constants and Domain Bounds *)

(** Maximum value of a WebIDL [EnforceRange] unsigned long (2^32 - 1). *)
Definition UINT32_MAX : Z := 4294967295.

(** Predicate characterizing the WebIDL [EnforceRange] unsigned long domain. *)
Definition in_uint32_range (iter : Z) : Prop :=
  0 <= iter <= UINT32_MAX.

(** Boolean decision procedure for WebIDL [EnforceRange] unsigned long. *)
Definition check_uint32_range (iter : Z) : bool :=
  (0 <=? iter) && (iter <=? UINT32_MAX).

(** ** 2. Core Mathematical Property & Normative Predicates *)

(** Target Mathematical Property:
    Boolean validation predicate for PBKDF2 iterations positivity. *)
Definition valid_iterations (iter : Z) : bool :=
  1 <=? iter.

(** High-level propositional specification of positive iterations. *)
Definition spec_valid_iterations (iter : Z) : Prop :=
  1 <= iter.

(** Complete W3C §30.2 + §30.4 validity predicate combining WebIDL
    [EnforceRange] unsigned long and the non-zero iterations check. *)
Definition spec_w3c_pbkdf2_iterations (iter : Z) : Prop :=
  1 <= iter <= UINT32_MAX.

(** ** 3. Blink & WebCrypto Execution Model *)

(** WebCrypto exception and success outcomes during PBKDF2 normalization/execution. *)
Inductive WebCryptoError : Type :=
  | Err_TypeError       (* Thrown by WebIDL [EnforceRange] if outside [0, 2^32-1] *)
  | Err_OperationError. (* Thrown by WebCrypto §30.4 Step 2 if iterations == 0 *)

Inductive WebCryptoResult (A : Type) : Type :=
  | Ok (val : A)
  | Err (e : WebCryptoError).

Arguments Ok {A} _.
Arguments Err {A} _.

(** Record representing a validated WebCryptoPbkdf2Params structure. *)
Record ValidatedPbkdf2Params : Type := mkValidatedPbkdf2Params {
  pbkdf2_salt_len   : Z;
  pbkdf2_iterations : Z;
  pbkdf2_hash_id    : Z
}.

(** Blink C++ implementation model of PBKDF2 iterations check on a normalized uint32_t:
    if (iterations == 0) return Status::ErrorPbkdf2Iterations0(); *)
Definition blink_check_iterations_uint32 (iter : Z) : bool :=
  negb (iter =? 0).

(** Full Blink + WebIDL PBKDF2 parameter normalization state machine. *)
Definition blink_normalize_pbkdf2_params
  (salt_len : Z) (raw_iter : Z) (hash_id : Z) : WebCryptoResult ValidatedPbkdf2Params :=
  if negb (check_uint32_range raw_iter) then
    Err Err_TypeError
  else if negb (valid_iterations raw_iter) then
    Err Err_OperationError
  else
    Ok (mkValidatedPbkdf2Params salt_len raw_iter hash_id).

(** Alternative C++ path using (iter == 0) after uint32_t range enforcement. *)
Definition blink_normalize_pbkdf2_params_cpp
  (salt_len : Z) (raw_iter : Z) (hash_id : Z) : WebCryptoResult ValidatedPbkdf2Params :=
  if negb (check_uint32_range raw_iter) then
    Err Err_TypeError
  else if raw_iter =? 0 then
    Err Err_OperationError
  else
    Ok (mkValidatedPbkdf2Params salt_len raw_iter hash_id).

(** ** 4. BoringSSL Cryptographic Primitive Contract *)

(** BoringSSL PKCS5_PBKDF2_HMAC safety precondition:
    Requires strictly positive iteration count in the 32-bit unsigned range
    to guarantee termination and non-degenerate PRF chaining (RFC 8018 §5.2). *)
Definition boringssl_pbkdf2_precondition (p : ValidatedPbkdf2Params) : Prop :=
  1 <= pbkdf2_iterations p <= UINT32_MAX.
```

---

## 4. Concrete Theorems and Complete Mechanized Proofs

The following theorems establish the soundness, completeness, observational equivalence between the C++ zero-equality check (`iterations == 0`) and the relational inequality (`1 <=? iter`), exact error classification (`TypeError` vs `OperationError`), and preservation of the BoringSSL cryptographic safety invariant. All proofs are complete and free of `Admitted` or axioms.

```coq
(** ** 5. Mechanized Theorems and Proofs *)

(** Theorem 1: Reflection equivalence between the boolean predicate
    [valid_iterations iter = (1 <=? iter)] and the arithmetic proposition [1 <= iter]. *)
Theorem valid_iterations_iff :
  forall iter : Z,
    valid_iterations iter = true <-> spec_valid_iterations iter.
Proof.
  intros iter.
  unfold valid_iterations, spec_valid_iterations.
  rewrite Z.leb_le.
  reflexivity.
Qed.

(** Theorem 2: Exact dual characterization of invalid iterations. *)
Theorem invalid_iterations_iff :
  forall iter : Z,
    valid_iterations iter = false <-> iter < 1.
Proof.
  intros iter.
  unfold valid_iterations.
  rewrite Z.leb_gt.
  reflexivity.
Qed.

(** Theorem 3: Correctness of the WebIDL [EnforceRange] unsigned long boolean check. *)
Theorem check_uint32_range_iff :
  forall iter : Z,
    check_uint32_range iter = true <-> in_uint32_range iter.
Proof.
  intros iter.
  unfold check_uint32_range, in_uint32_range, UINT32_MAX.
  rewrite andb_true_iff.
  rewrite !Z.leb_le.
  reflexivity.
Qed.

(** Theorem 4: Equivalence of Blink's C++ check [!(iter == 0)] and [valid_iterations iter]
    over the WebIDL [uint32_t] domain. *)
Theorem blink_cpp_zero_check_equiv_valid_iterations :
  forall iter : Z,
    in_uint32_range iter ->
    blink_check_iterations_uint32 iter = valid_iterations iter.
Proof.
  intros iter [Hlow Hhigh].
  unfold blink_check_iterations_uint32, valid_iterations.
  destruct (Z.eqb_spec iter 0) as [Heq | Hneq];
  destruct (Z.leb_spec 1 iter) as [Hle | Hgt];
  simpl; try reflexivity; lia.
Qed.

(** Theorem 5: Observational equivalence of the abstract normalization model
    and the concrete C++ normalization model across all integer inputs. *)
Theorem blink_normalize_models_equivalent :
  forall salt_len raw_iter hash_id : Z,
    blink_normalize_pbkdf2_params salt_len raw_iter hash_id =
    blink_normalize_pbkdf2_params_cpp salt_len raw_iter hash_id.