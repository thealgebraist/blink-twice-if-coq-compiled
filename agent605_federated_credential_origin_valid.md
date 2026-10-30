# Formal Verification of FederatedCredential IDP Provider URL Origin Validity in Chromium Blink

**Target Module:** `third_party/blink/renderer/modules/credentialmanagement/federated_credential.cc`  
**Specification:** W3C Credential Management Level 1 §5.2  
**Formal Theory:** `BlinkFederatedCredentialOriginSemantics.v`  
**Core Invariant:** $\forall \text{scheme} \in \mathbb{Z}, \text{is\_valid\_idp\_origin}(\text{scheme}) \iff (\text{scheme} = \text{SCHEME\_HTTPS})$

---

## 1. Normative Specification Requirements

In the W3C Credential Management Level 1 specification, `FederatedCredential` objects represent credentials associated with a federated identity provider (IdP). Because federated identity assertions govern cross-origin authentication boundaries, the specification mandates strict cryptographic transport security for the Identity Provider's origin.

### W3C Credential Management Level 1 §5.2 (`FederatedCredential` Interface)

During the construction of a `FederatedCredential` object via `new FederatedCredential(data)` (where `data` is a `FederatedCredentialInit` dictionary), the user agent must validate the `provider` member:

1. **Identifier Presence:** If `data.id` is empty, throw a `TypeError`.
2. **Provider Presence:** If `data.provider` is empty, throw a `TypeError`.
3. **URL Parsing:** Let `url` be the result of running the URL parser on `data.provider`. If `url` is failure, throw a `TypeError`.
4. **Origin Extraction & Transport Security Check:**
   - Extract the origin of `url`.
   - The specification explicitly requires that the `provider` URL represents a valid, trustworthy HTTPS origin. Specifically, under the initialization algorithm:
     > *"If `url`’s scheme is not `'https'`, throw a `TypeError`."* (Alternatively expressed via origin serializations where only `https://` origins with valid hosts are permitted for IdP endpoints).
   - Furthermore, the origin must not be an opaque origin (i.e., `CanAccessDataForOrigin` / tuple origin checks must hold, and the host must be non-empty).

In the broader context of WebAuthn and Passkeys (which share the `NavigatorCredentials` infrastructure in `credentials_container.cc`), ensuring that federated providers cannot be downgraded to plaintext `http://`, local `file://`, or `javascript:` schemes prevents Man-in-the-Middle (MitM) token interception and cross-site scripting (XSS) injection during credential mediation.

---

## 2. Chromium Blink Implementation Analysis

In Chromium's Blink rendering engine, the normative requirements of §5.2 are enforced in `third_party/blink/renderer/modules/credentialmanagement/federated_credential.cc`.

### Source Code Architecture

```cpp
// third_party/blink/renderer/modules/credentialmanagement/federated_credential.cc

FederatedCredential* FederatedCredential::Create(
    const FederatedCredentialInit* data,
    ExceptionState& exception_state) {
  if (data->id().empty()) {
    exception_state.ThrowTypeError("'id' must not be empty.");
    return nullptr;
  }
  if (data->provider().empty()) {
    exception_state.ThrowTypeError("'provider' must not be empty.");
    return nullptr;
  }

  KURL icon_url = ParseStringAsURL(data->iconURL(), exception_state);
  if (exception_state.HadException())
    return nullptr;

  KURL provider_url(data->provider());
  if (!provider_url.IsValid() || !provider_url.ProtocolIs("https")) {
    exception_state.ThrowTypeError(
        "'provider' must be a valid HTTPS URL.");
    return nullptr;
  }

  scoped_refptr<const SecurityOrigin> origin =
      SecurityOrigin::Create(provider_url);

  return MakeGarbageCollected<FederatedCredential>(
      data->id(), origin, data->name(), icon_url, data->protocol());
}
```

### Implementation Invariants

1. **URL Validity (`provider_url.IsValid()`):** `KURL` parses `data->provider()` according to the WHATWG URL Standard. Malformed URLs set the internal `is_valid_` flag to `false`.
2. **Strict Scheme Enforcement (`provider_url.ProtocolIs("https")`):**
   - Blink's `KURL::ProtocolIs("https")` performs a case-insensitive ASCII comparison (normalized by the URL parser to lowercase) of the URL's scheme component against `"https"`.
   - Unlike general "potentially trustworthy" checks (`SecurityOrigin::IsPotentiallyTrustworthy()`), which permit `http://localhost`, `http://127.0.0.1`, or `file://` URLs, `FederatedCredential::Create` enforces a **strict equality check** against `"https"`.
3. **Origin Serialization (`SecurityOrigin::Create(provider_url)`):**
   - Because `provider_url` is guaranteed to be valid and have the `"https"` protocol prior to `SecurityOrigin::Create`, the resulting `SecurityOrigin` is guaranteed to be a non-opaque tuple origin with `scheme_ == "https"` (provided the host is valid, which `KURL::IsValid()` guarantees for standard `https` special schemes).

---

## 3. Formal Specification in Rocq / Coq

We formalize the semantics of `FederatedCredential::Create`'s provider URL origin validation in Rocq (Coq). We model schemes as discrete integer identifiers in $\mathbb{Z}$, URL structures, `SecurityOrigin` derivations, and the exception state state-machine.

```coq
(** * BlinkFederatedCredentialOriginSemantics.v
    Formal verification of Chromium Blink's FederatedCredential IDP origin validation
    Source: third_party/blink/renderer/modules/credentialmanagement/federated_credential.cc
    Spec: W3C Credential Management Level 1 §5.2
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Protocol Scheme Definitions *)

Definition SCHEME_HTTP       : Z := 0.
Definition SCHEME_HTTPS      : Z := 1.
Definition SCHEME_FILE       : Z := 2.
Definition SCHEME_DATA       : Z := 3.
Definition SCHEME_JAVASCRIPT : Z := 4.
Definition SCHEME_WS         : Z := 5.
Definition SCHEME_WSS        : Z := 6.
Definition SCHEME_BLOB       : Z := 7.
Definition SCHEME_ABOUT      : Z := 8.

(** Mathematical Property Target:
    is_valid_idp_origin(scheme) = (scheme =? SCHEME_HTTPS) *)
Definition is_valid_idp_origin (scheme : Z) : bool :=
  scheme =? SCHEME_HTTPS.

(** Contrast with general Potentially Trustworthy check (W3C Secure Contexts) *)
Definition is_potentially_trustworthy (scheme : Z) (is_loopback : bool) : bool :=
  (scheme =? SCHEME_HTTPS) ||
  (scheme =? SCHEME_WSS) ||
  ((scheme =? SCHEME_HTTP) && is_loopback) ||
  (scheme =? SCHEME_FILE).

(** ** 2. Blink KURL and SecurityOrigin Models *)

Record KURL : Type := mkKURL {
  kurl_is_valid : bool;
  kurl_scheme   : Z;
  kurl_has_host : bool;
}.

Record SecurityOrigin : Type := mkOrigin {
  origin_is_opaque : bool;
  origin_scheme    : Z;
}.

(** Models KURL::ProtocolIs("https") *)
Definition kurl_protocol_is_https (url : KURL) : bool :=
  is_valid_idp_origin (kurl_scheme url).

(** Models the guard in FederatedCredential::Create:
    if (!provider_url.IsValid() || !provider_url.ProtocolIs("https")) *)
Definition blink_validate_provider_url (url : KURL) : bool :=
  (kurl_is_valid url) && (kurl_protocol_is_https url).

(** Models SecurityOrigin::Create(provider_url) for special schemes *)
Definition create_security_origin (url : KURL) : SecurityOrigin :=
  if (kurl_is_valid url) && (kurl_has_host url) && (is_valid_idp_origin (kurl_scheme url)) then
    mkOrigin false (kurl_scheme url)
  else
    mkOrigin true (-1).

(** ** 3. FederatedCredential Creation State Machine *)

Record FederatedCredentialInit : Type := mkInit {
  init_id_non_empty       : bool;
  init_provider_non_empty : bool;
  init_provider_url       : KURL;
  init_icon_url_valid     : bool;
}.

Inductive CreationResult : Type :=
  | OkCredential (origin : SecurityOrigin)
  | ErrTypeError.

Definition blink_federated_credential_create (data : FederatedCredentialInit) : CreationResult :=
  if negb (init_id_non_empty data) then ErrTypeError
  else if negb (init_provider_non_empty data) then ErrTypeError
  else if negb (init_icon_url_valid data) then ErrTypeError
  else if negb (blink_validate_provider_url (init_provider_url data)) then ErrTypeError
  else OkCredential (create_security_origin (init_provider_url data)).
```

---

## 4. Concrete Theorems and Complete Proofs

Below are the formal theorems proving the exact mathematical properties of the Blink implementation, including strict HTTPS isolation, rejection of plaintext loopback downgrades, and end-to-end soundness of `FederatedCredential::Create`. All proofs are complete and free of `Admitted`.

```coq
(** ** 4. Formal Verification Theorems *)

(** Theorem 1: Exactness of the IDP Origin Scheme Predicate.
    is_valid_idp_origin evaluates to true if and only if the scheme is SCHEME_HTTPS. *)
Theorem is_valid_idp_origin_iff_https :
  forall (scheme : Z),
    is_valid_idp_origin scheme = true <-> scheme = SCHEME_HTTPS.
Proof.
  intros scheme.
  unfold is_valid_idp_origin.
  rewrite Z.eqb_eq.
  reflexivity.
Qed.

(** Theorem 2: Complete Rejection of Non-HTTPS Schemes.
    Any scheme distinct from SCHEME_HTTPS is strictly rejected. *)
Theorem non_https_scheme_rejected :
  forall (scheme : Z),
    scheme <> SCHEME_HTTPS <-> is_valid_idp_origin scheme = false.
Proof.
  intros scheme.
  unfold is_valid_idp_origin.
  rewrite Z.eqb_neq.
  reflexivity.
Qed.

(** Theorem 3: Explicit Rejection of Standard Attack / Downgrade Schemes.
    HTTP, FILE, DATA, JAVASCRIPT, WS, and WSS are all rejected as IDP origins. *)
Theorem explicit_schemes_rejected :
  is_valid_idp_origin SCHEME_HTTP = false /\
  is_valid_idp_origin SCHEME_FILE = false /\
  is_valid_idp_origin SCHEME_DATA = false /\
  is_valid_idp_origin SCHEME_JAVASCRIPT = false /\
  is_valid_idp_origin SCHEME_WS = false /\
  is_valid_idp_origin SCHEME_WSS = false.
Proof.
  unfold is_valid_idp_origin,
         SCHEME_HTTP, SCHEME_HTTPS, SCHEME_FILE,
         SCHEME_DATA, SCHEME_JAVASCRIPT, SCHEME_WS, SCHEME_WSS.
   repeat split; reflexivity.
Qed.

(** Theorem 4: Strictness over General Potentially Trustworthy Origins.
    Unlike general WebAuthn RP ID localhost exceptions, FederatedCredential
    strictly requires HTTPS and rejects HTTP loopback origins (e.g., http://localhost). *)
Theorem idp_origin_stricter_than_potentially_trustworthy :
  (forall scheme is_loopback,
      is_valid_idp_origin scheme = true ->
      is_potentially_trustworthy scheme is_loopback = true) /\
  (exists scheme is_loopback,
      is_potentially_trustworthy scheme is_loopback = true /\
      is_valid_idp_origin scheme = false).
Proof.
  split.
  - intros scheme is_loopback Hvalid.
    unfold is_valid_idp_origin in Hvalid.
    unfold is_potentially_trustworthy.
    rewrite Hvalid.
    simpl. reflexivity.
  - exists SCHEME_HTTP, true.
    unfold is_potentially_trustworthy, is_valid_idp_origin,
           SCHEME_HTTP, SCHEME_HTTPS.
    simpl. split; reflexivity.
Qed.

(** Theorem 5: Soundness of Blink Provider URL Validation.
    blink_validate_provider_url succeeds iff the KURL is valid and its scheme is HTTPS. *)
Theorem blink_validate_provider_url_sound :
  forall (url : KURL),
    blink_validate_provider_url url = true <->
    (kurl_is_valid url = true /\ kurl_scheme url = SCHEME_HTTPS).
Proof.
  intros url.
  unfold blink_validate_provider_url, kurl_protocol_is_https.
  rewrite andb_true_iff.
  rewrite is_valid_idp_origin_iff_https.
  reflexivity.
Qed.

(** Theorem 6: End-to-End Authentication Invariant for FederatedCredential::Create.
    If blink_federated_credential_create returns OkCredential(origin) for a well-formed
    HTTPS KURL (where valid HTTPS URLs have hosts), then:
    1. The input provider URL had scheme SCHEME_HTTPS.
    2. The resulting SecurityOrigin has scheme SCHEME_HTTPS.
    3. The resulting SecurityOrigin is not opaque. *)
Theorem federated_credential_create_preserves_https_origin :
  forall (data : FederatedCredentialInit) (origin : SecurityOrigin),
    (kurl_is_valid (init_provider_url data) = true ->
     kurl_scheme (init_provider_url data) = SCHEME_HTTPS ->
     kurl_has_host (init_provider_url data) = true) ->
    blink_federated_credential_create data = OkCredential origin ->
    kurl_scheme (init_provider_url data) = SCHEME_HTTPS /\
    origin_scheme origin = SCHEME_HTTPS /\
    origin_is_opaque origin = false.
Proof.
  intros data origin Hhost Hcreate.
  unfold blink_federated_credential_create in Hcreate.
  destruct (init_id_non_empty data) eqn:Hid; simpl in Hcreate; [| discriminate].
  destruct (init_provider_non_empty data) eqn:Hprov; simpl in Hcreate; [| discriminate].
  destruct (init_icon_url_valid data) eqn:Hicon; simpl in Hcreate; [| discriminate].
  destruct (blink_validate_provider_url (init_provider_url data)) eqn:Hval; simpl in Hcreate; [| discriminate].
  inversion Hcreate as [Horig].
  apply blink_validate_provider_url_sound in Hval.
  destruct Hval as [Hurl