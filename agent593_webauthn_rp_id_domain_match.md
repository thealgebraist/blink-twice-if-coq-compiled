# Formal Verification Report: WebAuthn Relying Party ID Origin Domain Suffix Match in Chromium Blink

**Formal Theory Target**: `BlinkWebAuthnRPSuffixMatchSemantics.v`  
**Chromium Subsystem**: `third_party/blink/renderer/modules/credentialmanagement/`  
**Target Implementation**: `credential_manager_type_converters.cc`  
**Normative Specification**: W3C WebAuthn Level 3 §5.1.3, WHATWG HTML §7.5 (Relaxing the Same-Origin Restriction)  
**Mathematical Property**: $\text{rp\_id\_valid}(rp, origin) \iff \text{is\_suffix}(rp, origin) \land \neg \text{is\_public\_suffix}(rp)$

---

## 1. Normative W3C WebAuthn and WHATWG Specification Requirements

In the Web Authentication (WebAuthn) architecture, the **Relying Party Identifier (RP ID)** defines the security scope and cryptographic domain to which a public key credential is bound. When an authenticator generates or asserts a credential, it hashes the RP ID (`SHA-256(rp.id)`) into the Authenticator Data (`authData`). To prevent cross-origin phishing and credential synthesis across unrelated domains, the user agent must strictly enforce that a caller's origin is authorized to claim a specific RP ID.

### 1.1 W3C WebAuthn Level 3 §5.1.3 (Create) and §5.1.4 (Get)
Under **W3C WebAuthn Level 3**, the Relying Party ID validation relies on the concept of a **valid domain string** and the **registrable domain suffix** matching algorithm defined by the WHATWG HTML specification:

1. **Default RP ID Assignment**: If the `rp.id` member of `PublicKeyCredentialCreationOptions` (or `rpId` in `PublicKeyCredentialRequestOptions`) is omitted, the user agent initializes the effective RP ID to the **caller's origin's effective domain**.
2. **Valid Domain Check**: The RP ID must be a valid domain string (a non-empty sequence of non-empty ASCII labels separated by U+002E FULL STOP, after IDNA ToASCII canonicalization, that does not represent an IPv4 or IPv6 address).
3. **Suffix Match against Origin**: The RP ID must be a **registrable domain suffix of, or be equal to**, the caller's origin's effective domain.

### 1.2 WHATWG HTML §7.5 ("Is a registrable domain suffix of or is equal to")
Given a candidate suffix string $R$ (`rpId` / `hostSuffixString`) and an origin host $O$ (`originalHost`), $R$ is a registrable domain suffix of or equal to $O$ if and only if:
1. $R \neq \epsilon$ (non-empty) and $O \neq \epsilon$.
2. Neither $R$ nor $O$ is an IP address (IPv4 or IPv6).
3. After canonicalization (IDNA ToASCII lowercase):
   * Either $R = O$, OR
   * $R$ is a strict label suffix of $O$ (i.e., $O$ ends with `"." ++ R`, ensuring label-boundary alignment so that `notexample.com` does not match `example.com`).
4. **Public Suffix Exclusion**: $R$ is **not** a public suffix according to the Public Suffix List (PSL), meaning the public suffix of $R$ is strictly shorter than $R$ itself. An origin `sub.co.uk` cannot claim `co.uk` or `uk` as its RP ID, nor can `github.io` (if listed as a private PSL entry) be claimed by `attacker.github.io`.

---

## 2. Chromium Blink Implementation & Architectural Invariants

In Chromium, the WebAuthn API (`navigator.credentials.create()` and `navigator.credentials.get()`) is exposed to JavaScript in the Blink renderer process (`third_party/blink/renderer/modules/credentialmanagement/`). Before IPC serialization to the browser process via Mojo (`blink::mojom::blink::Authenticator`), the renderer converts WebIDL dictionary types into Mojo structs using type converters defined in `credential_manager_type_converters.cc`.

### 2.1 Role of `credential_manager_type_converters.cc`
`third_party/blink/renderer/modules/credentialmanagement/credential_manager_type_converters.cc` implements `mojo::TypeConverter` specializations for translating Blink's garbage-collected IDL objects into Mojo data structures:

* `TypeConverter<PublicKeyCredentialRpEntityPtr, const blink::PublicKeyCredentialRpEntity*>`
* `TypeConverter<PublicKeyCredentialCreationOptionsPtr, const blink::PublicKeyCredentialCreationOptions*>`
* `TypeConverter<PublicKeyCredentialRequestOptionsPtr, const blink::PublicKeyCredentialRequestOptions*>`

Within `credential_manager_type_converters.cc`:
```cpp
PublicKeyCredentialRpEntityPtr
TypeConverter<PublicKeyCredentialRpEntityPtr,
              const blink::PublicKeyCredentialRpEntity*>::
    Convert(const blink::PublicKeyCredentialRpEntity* entity) {
  auto mojo_entity = blink::mojom::blink::PublicKeyCredentialRpEntity::New();
  mojo_entity->name = entity->name();
  if (entity->hasId()) {
    mojo_entity->id = entity->id();
  }
  return mojo_entity;
}
```
Notice a critical architectural boundary: `credential_manager_type_converters.cc` performs a **total, unfiltered structural translation** of `entity->id()` (and `options->rpId()` for requests) into the Mojo struct. If `entity->hasId()` is false (or null/omitted), `mojo_entity->id` remains null or is defaulted by `AuthenticationCredentialsContainer` (`authentication_credentials_container.cc`) prior to or immediately after conversion using `context->GetSecurityOrigin()->Domain()`.

### 2.2 Renderer Defense-in-Depth vs. Browser Process Enforcement
Chromium enforces the RP ID domain suffix match across a two-tier boundary:

1. **Blink Renderer Pre-Check & Serialization (`authentication_credentials_container.cc` & `credential_manager_type_converters.cc`)**:
   * Extracts `SecurityOrigin` from the `ExecutionContext`.
   * Checks that the origin is an HTTPS or `localhost` opaque-free tuple origin (`SecurityOrigin::CanAccessPasswordManager()` / `IsPotentiallyTrustworthy()`).
   * Converts the options via `Mojo::ConvertTo<PublicKeyCredentialCreationOptionsPtr>(options)` in `credential_manager_type_converters.cc`.
2. **Browser Process Authoritative Check (`content/browser/webauth/authenticator_common_impl.cc` & `net::registry_controlled_domains`)**:
   * Because a compromised renderer process could bypass Blink checks and craft arbitrary `PublicKeyCredentialRpEntity` Mojo messages directly, the browser process re-verifies the RP ID received from `credential_manager_type_converters.cc` against `RenderFrameHost::GetLastCommittedOrigin()`.
   * Specifically, Chromium evaluates:
     1. Canonicalization check: `url::CanonHostInfo` verifies the claimed `relying_party_id` is canonical and not an IP address.
     2. Exact match or label-boundary suffix match: Either `relying_party_id == caller_domain` or ` caller_domain` ends with `"." + relying_party_id` (checked via `net::registry_controlled_domains::SameDomainOrHost` and string suffix comparisons).
     3. Public Suffix List (PSL) validation: `net::registry_controlled_domains::GetDomainAndRegistry(relying_party_id, INCLUDE_PRIVATE_REGISTRIES)` must return a non-empty string. In `net::registry_controlled_domains`, if an input domain is itself a public suffix (e.g., `com`, `co.uk`, `github.io`), `GetDomainAndRegistry` returns `""` (empty string) because there is no registrable label preceding the registry suffix.

### 2.3 Formal Invariants of the Implementation
Let DNS domain names be modeled from right to left (root-first) as lists of integer-encoded ASCII labels: $\text{Domain} = \text{list } \mathbb{Z}$. For example, `"login.corp.example.com"` is represented in root-first order as `["com"; "example"; "corp"; "login"]`.

Under this representation:
* **Label-Boundary Suffix Match ($\text{is\_suffix}(rp, origin)$)**: Because each element in the list is a discrete DNS label ordered from top-level domain (TLD) to leaf subdomain, $rp$ is a label-aligned domain suffix of (or equal to) $origin$ if and only if the list $rp$ is a **list prefix** of $origin$ in root-first order (or equivalently, a list suffix in leaf-first order). Crucially, representing domains as lists of labels rather than flat character strings structurally eliminates partial-label suffix attacks (e.g., `"ample.com"` is not a label-list suffix of `"example.com"`).
* **Public Suffix Exclusion ($\text{not\_public\_suffix}(rp)$)**: Let $\text{psl\_len}(d) \in \mathbb{Z}$ denote the number of labels in $d$ governed by the Public Suffix List (including ICANN and private registries). A domain $rp$ is **not** a public suffix if and only if it is non-empty, contains only valid labels, and $|rp| > \text{psl\_len}(rp) \ge 1$.
* **Converter Preservation**: When `credential_manager_type_converters.cc` converts `PublicKeyCredentialRpEntity` into `mojom::PublicKeyCredentialRpEntityPtr` (resolving an omitted `id` to the origin's effective domain), the resulting Mojo struct satisfies $\text{rp\_id\_valid}(rp, origin)$ if and only if the underlying domain satisfies $\text{is\_suffix}(rp, origin) \land \text{not\_public\_suffix}(rp)$.

---

## 3. Formal Specification in Rocq / Coq (`BlinkWebAuthnRPSuffixMatchSemantics.v`)

Below is the complete, self-contained, and admitted-free Rocq/Coq formalization of the WebAuthn Relying Party ID suffix matching semantics, the Blink `TypeConverter` transformation, and the security invariants.

```coq
(** * BlinkWebAuthnRPSuffixMatchSemantics.v
    Formal Verification of WebAuthn Relying Party ID Origin Domain Suffix Match
    Chromium Source: third_party/blink/renderer/modules/credentialmanagement/credential_manager_type_converters.cc
    Specification: W3C WebAuthn Level 3 Section 5.1.3 & WHATWG HTML Section 7.5
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import Micega.Lia.
Import ListNotations.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Domain and Origin Representation *)

(** A DNS label is represented as an integer identifier.
    Valid canonical ASCII labels are strictly positive (label > 0).
    Non-positive values represent invalid characters, empty labels (leading/trailing/consecutive dots),
    or IP address literals. *)
Definition Label := Z.

(** A Domain is represented in root-first (right-to-left DNS) order:
    e.g., "sub.example.com" is represented as [label("com"); label("example"); label("sub")].
    In this canonical representation, DNS suffix matching corresponds directly to list prefix matching
    over discrete labels, preventing partial-label attacks ("ample.com" vs "example.com"). *)
Definition Domain := list Label.

(** A label is valid if its identifier is strictly positive. *)
Definition valid_label (l : Label) : bool :=
  0 <? l.

(** A domain is well-formed if it is non-empty and all its labels are valid. *)
Fixpoint all_valid_labels (d : Domain) : bool :=
  match d with
  | [] => true
  | l :: rest => valid_label l && all_valid_labels rest
  end.

Definition well_formed_domain (d : Domain) : bool :=
  match d with
  | [] => false
  | _ => all_valid_labels d
  end.

(** ** 2. Domain Suffix Matching (is_suffix) *)

(** In root-first label order, [rp] is a domain suffix of (or equal to) [origin]
    iff [rp] is a prefix of the label list [origin]. *)
Fixpoint is_label_prefix (rp origin : Domain) : bool :=
  match rp, origin with
  | [], _ => true
  | _, [] => false
  | l1 :: r1, l2 :: r2 => (l1 =? l2) && is_label_prefix r1 r2
  end.

(** Normative suffix predicate: both [rp] and [origin] must be well-formed domains,
    and [rp] must match the root-first label prefix of [origin]. *)
Definition is_suffix (rp origin : Domain) : bool :=
  well_formed_domain rp && well_formed_domain origin && is_label_prefix rp origin.

(** ** 3. Public Suffix List (PSL) Model (not_public_suffix) *)

(** We model the Public Suffix List (PSL) via a registry length function [psl_len : Domain -> Z]
    that returns the number of root-first labels belonging to the public suffix registry for a given TLD/branch.
    For standard TLDs like ["com"], psl_len = 1.
    For multi-label public suffixes like ["uk"; "co"], psl_len = 2.
    For unlisted/invalid roots, psl_len >= 1.

    A domain [d] is NOT a public suffix (i.e., it has a registrable domain) iff:
    1. [d] is a well-formed domain.
    2. The total label length of [d] is strictly greater than its PSL suffix length,
       and the PSL suffix length is at least 1. *)

Fixpoint domain_len (d : Domain) : Z :=
  match d with
  | [] => 0
  | _ :: rest => 1 + domain_len rest
  end.

Section WebAuthnRPSuffixVerification.

  (** Abstract PSL oracle parameterized over the verification context, paired with
      its fundamental structural invariant: if a domain extends another, they share the same
      root-first registry branch once the domain is at least as long as the registry suffix. *)
  Variable psl_len : Domain -> Z.

  (** PSL Oracle Axiom: For any two domains that share the same root-first prefix [rp],
      if [rp] already exceeds the public suffix length, extending [rp] with additional
      subdomains in [origin] does not change the length of the underlying public suffix. *)
  Hypothesis psl_len_prefix_invariant :
    forall (rp origin : Domain),
      is_label_prefix rp origin = true ->
      1 <= psl_len rp ->
      psl_len rp < domain_len rp ->
      psl_len origin = psl_len rp.

  Definition not_public_suffix (rp : Domain) : bool :=
    well_formed_domain rp && (1 <=? psl_len rp) && (psl_len rp <? domain_len rp).

  (** ** 4. Top-Level WebAuthn RP ID Validation Predicate *)