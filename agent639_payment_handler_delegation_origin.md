# Formal Verification Research Report: Payment Handler API Delegated Payment Client Origin Match

**Agent ID:** Formal Verification Agent 639  
**Specialization:** Web Payments, Autofill & Form Normalization (Chromium Blink & W3C Specifications)  
**Target Source:** `third_party/blink/renderer/modules/payments/payment_handler_utils.cc`  
**Target Specification:** W3C Payment Handler API §4.1 (Delegated Payment Client Origin Validation)  
**Formal Theory Target:** `BlinkPaymentHandlerDelegationOriginSemantics.v`  
**Core Mathematical Property:**  
$$\text{is\_authorized\_delegation}(\text{client\_origin}, \text{handler\_origin}) \iff (\text{client\_origin} = \text{handler\_origin}) \land \neg \text{is\_opaque}(\text{client\_origin})$$

---

## 1. Exact Normative W3C Payment Handler Specification Requirements

Within the architecture of the W3C Payment Request and Payment Handler APIs, a Payment Handler operates within the execution context of a Service Worker (`ServiceWorkerGlobalScope`). During the handling of a `paymentrequest` event (`PaymentRequestEvent`), the payment handler may require user interaction (e.g., authentication, card selection, or confirmation of shipping/payer details) or may delegate response formulation to an active window client via `PaymentRequestEvent.openWindow(url)` or by communicating with existing controlled `WindowClient` instances.

### 1.1 Normative Citations (W3C Payment Handler API §4.1 & §6)

According to the W3C Payment Handler API Specification:

1. **Same-Origin Registration & Execution Context (§3 & §4.1):**
   A `PaymentManager` is bound to a specific `ServiceWorkerRegistration`. The origin of the payment handler (`handler_origin`) is the origin of the service worker's script URL, which is guaranteed by the Service Workers specification to be a potentially trustworthy, non-opaque origin.
2. **Opening Payment Handler Windows (§6.4 `openWindow()` method):**
   When `openWindow(url)` is invoked on a `PaymentRequestEvent`:
   - Let *url* be the result of parsing the argument against the service worker's relevant settings object's API base URL.
   - **Normative Origin Check:** *"If url's origin is not the same origin as the service worker's origin, then return a promise rejected with a `SecurityError` `DOMException`."*
3. **Delegated Payment Client Authorization (§4.1 & Window Client Messaging):**
   When a payment handler delegates payment instrument selection or user authorization to a client context (`client_origin`), the delegating service worker and the delegated client must satisfy the HTML Specification's **Same Origin** predicate (`same_origin(A, B)`):
   - Neither origin may be an opaque (unique) origin (`!A.is_opaque() && !B.is_opaque()`).
   - Both origins must share the exact same scheme, host, and port components:
     $$\text{scheme}(A) = \text{scheme}(B) \land \text{host}(A) = \text{host}(B) \land \text{port}(A) = \text{port}(B)$$

Failure to enforce this invariant would permit a cross-origin frame or malicious window to spoof payment responses, intercept sensitive autofill/payment instrument data, or bypass user activation invariants enforced on the `PaymentRequestEvent` lifecycle.

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, Web Payment security utilities, origin checks, and execution context diagnostics are centralized within `third_party/blink/renderer/modules/payments/`—specifically interacting with `payment_handler_utils.cc`, `payment_request_event.cc`, and `payment_instruments.cc`.

### 2.1 Architectural Role of `payment_handler_utils.cc`

`payment_handler_utils.cc` provides helper routines for the Payment Handler module, including:
- Logging and reporting security/manifest errors to the DevTools console (`PaymentHandlerUtils::ReportResponseError`).
- Validating execution contexts, security origins (`blink::SecurityOrigin`), and service worker client relationships before allowing payment delegation or responding to a `PaymentRequestEvent`.

In Blink, origins are represented by the `blink::SecurityOrigin` class (`third_party/blink/renderer/platform/weborigin/security_origin.h`). When verifying whether a delegated payment client (`ExecutionContext` or `WebServiceWorkerClientInfo`) is authorized to act on behalf of a Payment Handler running in a `ServiceWorkerGlobalScope`, Blink enforces the following implementation invariants:

```cpp
// Conceptual representation of Blink's origin validation invariant in modules/payments/
bool IsAuthorizedPaymentHandlerClient(
    const SecurityOrigin* client_origin,
    const SecurityOrigin* handler_origin) {
  if (!client_origin || !handler_origin) {
    return false;
  }
  // SecurityOrigin::IsSameOriginWith checks:
  // 1. Neither origin is opaque (unless comparing identical opaque pointers, 
  //    which is disallowed for ServiceWorker payment handlers as they require 
  //    secure, non-opaque origins).
  // 2. Scheme, Host, and Port equality.
  if (client_origin->IsOpaque() || handler_origin->IsOpaque()) {
    return false;
  }
  return client_origin->IsSameOriginWith(handler_origin);
}
```

### 2.2 Critical Blink Security Invariants

1. **Non-Opacity Invariant (`!IsOpaque()`):**  
   Sandboxed `<iframe>` elements (without `allow-same-origin`) or `data:` URLs possess opaque `SecurityOrigin` instances where every origin comparison returns `false` (except pointer-identical self-comparison in restricted contexts). Payment handlers in Blink must explicitly reject opaque origins from participating in delegated payment flows.
2. **Tuple Equality Invariant (`IsSameOriginWith`):**  
   For non-opaque origins, `SecurityOrigin::IsSameOriginWith(other)` evaluates to `true` if and only if `protocol_ == other->protocol_`, `host_ == other->host_`, and `port_ == other->port_`.
3. **Domain Relaxation Exclusion (`!IsSameOriginDomain`):**  
   Crucially, Blink uses `IsSameOriginWith` rather than `CanAccess` (which historically accounted for `document.domain` mutation). Payment Handler delegation strictly follows the W3C *same origin* (tuple match) semantics rather than *same origin-domain*.
4. **Delegation Filtering Soundness:**  
   When filtering a list of candidate `ServiceWorkerClient` instances or validating a batch of payment delegation requests, every retained client in the authorized set is guaranteed to have an origin strictly equal to the payment handler's origin.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkPaymentHandlerDelegationOriginSemantics.v`. We model schemes, hosts, ports, non-opaque vs. opaque origins (capturing `blink::SecurityOrigin`), delegation requests, and batch client filtering, using standard Coq libraries (`ZArith`, `Lia`, `Bool`, `List`).

```coq
(** * BlinkPaymentHandlerDelegationOriginSemantics.v
    Formal Verification of W3C Payment Handler API §4.1 & Chromium Blink
    Payment Handler Delegated Client Origin Validation.
    Target: third_party/blink/renderer/modules/payments/payment_handler_utils.cc *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Fundamental Web Origin Types *)

(** Scheme, Host, and Port identifiers modeled as arbitrary integers in Z
    (representing interned strings / canonical port numbers in Blink). *)
Definition SchemeId := Z.
Definition HostId   := Z.
Definition PortNum  := Z.
Definition NonceId  := Z.

(** A canonical tuple origin consists of (scheme, host, port). *)
Record TupleOrigin : Type := mkTupleOrigin {
  to_scheme : SchemeId;
  to_host   : HostId;
  to_port   : PortNum
}.

(** Decidable boolean equality on TupleOrigin. *)
Definition tuple_origin_eqb (o1 o2 : TupleOrigin) : bool :=
  (Z.eqb (to_scheme o1) (to_scheme o2)) &&
  (Z.eqb (to_host o1)   (to_host o2))   &&
  (Z.eqb (to_port o1)   (to_port o2)).

(** Full Web SecurityOrigin (blink::SecurityOrigin):
    Either a standard non-opaque TupleOrigin or an OpaqueOrigin with a unique nonce. *)
Inductive Origin : Type :=
  | NonOpaque (t : TupleOrigin)
  | Opaque    (nonce : NonceId).

(** Predicate identifying whether an Origin is opaque. *)
Definition is_opaque (o : Origin) : bool :=
  match o with
  | NonOpaque _ => false
  | Opaque _    => true
  end.

(** Exact structural equality on Origin (used for mathematical specification
    on non-opaque origins). *)
Definition origin_exact_eqb (o1 o2 : Origin) : bool :=
  match o1, o2 with
  | NonOpaque t1, NonOpaque t2 => tuple_origin_eqb t1 t2
  | Opaque n1, Opaque n2       => Z.eqb n1 n2
  | _, _                       => false
  end.

(** ** 2. W3C Payment Handler API §4.1 & Blink Delegation Authorization *)

(** In Blink's payment_handler_utils.cc and PaymentRequestEvent window/client
    validation, a delegated payment client is authorized if and only if both
    the client origin and handler origin are non-opaque and share the exact
    same (scheme, host, port) tuple. *)
Definition is_authorized_delegation (client_origin handler_origin : Origin) : bool :=
  match client_origin, handler_origin with
  | NonOpaque c, NonOpaque h => tuple_origin_eqb c h
  | _, _                     => false
  end.

(** For non-opaque origins (which all valid ServiceWorker registrations and
    standard HTTPS window clients are), we also define the direct TupleOrigin
    authorization predicate corresponding directly to:
    is_authorized_delegation(client_origin, handler_origin) = (client_origin == handler_origin) *)
Definition is_authorized_tuple_delegation (client_origin handler_origin : TupleOrigin) : bool :=
  tuple_origin_eqb client_origin handler_origin.

(** ** 3. Payment Handler Execution Context & Client Delegation Models *)

Record PaymentClient : Type := mkPaymentClient {
  pc_client_id : Z;
  pc_origin    : Origin;
  pc_is_window : bool
}.

Record PaymentHandlerContext : Type := mkPaymentHandlerContext {
  ph_registration_id : Z;
  ph_origin          : Origin
}.

(** A PaymentHandlerContext is well-formed in Blink if its ServiceWorker origin
    is non-opaque and uses a secure scheme (modeled here as scheme == 1 for HTTPS). *)
Definition HTTPS_SCHEME : Z := 1.

Definition wf_payment_handler (ctx : PaymentHandlerContext) : Prop :=
  exists t : TupleOrigin,
    ph_origin ctx = NonOpaque t /\ to_scheme t = HTTPS_SCHEME.

(** Check if a specific PaymentClient is authorized to receive delegated payment UI/handling
    for a given PaymentHandlerContext. *)
Definition authorize_payment_client (client : PaymentClient) (ctx : PaymentHandlerContext) : bool :=
  pc_is_window client && is_authorized_delegation (pc_origin client) (ph_origin ctx).

(** Filter a list of candidate ServiceWorker clients to only those authorized
    for payment delegation. *)
Definition filter_authorized_clients
  (clients : list PaymentClient) (ctx : PaymentHandlerContext) : list PaymentClient :=
  filter (fun c => authorize_payment_client c ctx) clients.
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

In this section, we state and prove the core mathematical theorems establishing soundness, completeness, equivalence relation properties on non-opaque origins, cross-origin rejection, opaque-origin rejection, and batch client filtering preservation. Every proof is complete and free of `Admitted`.

```coq
(** ** 4. Formal Verification Theorems and Proofs *)

(** *** Theorem 1: Soundness and Completeness of TupleOrigin Equality *)
Lemma tuple_origin_eqb_eq : forall (o1 o2 : TupleOrigin),
  tuple_origin_eqb o1 o2 = true <-> o1 = o2.
Proof.
  intros [s1 h1 p1] [s2 h2 p2].
  unfold tuple_origin_eqb; simpl.
  rewrite andb_true_iff, andb_true_iff.
  rewrite !Z.eqb_eq.
  split.
  - intros [[Hs Hh] Hp].
    subst. reflexivity.
  - intros Heq.
    inversion Heq; subst.
    auto.
Qed.

Lemma tuple_origin_eqb_neq : forall (o1 o2 : TupleOrigin),
  tuple_origin_eqb o1 o2 = false <-> o1 <> o2.
Proof.
  intros o1 o2.
  split.
  - intros Hfalse Heq.
    apply tuple_origin_eqb_eq in Heq.
    congruence.
  - intros Hneq.
    destruct (tuple_origin_eqb o1 o2) eqn:Heqb; [|reflexivity].
    apply tuple_origin_eqb_eq in Heqb.
    contradiction.
Qed.

(** *** Theorem 2: Exact Mathematical Property on Non-Opaque Origins
    Proves the core specification invariant:
    is_authorized_tuple_delegation(client_origin, handler_origin) = true <->
    client_origin = handler_origin. *)
Theorem authorized_tuple_delegation_iff_eq :
  forall (client_origin handler_origin : TupleOrigin),
    is_authorized_tuple_delegation client_origin handler_origin = true <->
    client_origin = handler_origin.
Proof.
  intros client_origin handler_origin.
  unfold is_authorized_tuple_delegation.
  apply tuple_origin_eqb_eq.
Qed.

(** *** Theorem 3: General Origin Delegation Characterization
    is_authorized_delegation(client_origin, handler_origin) = true if and only if
    both origins are non-opaque and strictly equal. *)
Theorem authorized_delegation_characterization :
  forall (client_origin handler_origin : Origin),
    is_authorized_delegation client_origin handler_origin = true <->
    (is_opaque client_origin = false /\
     is_opaque handler_origin = false /\
     client_origin = handler_origin).
Proof.
  intros [t1 | n1] [t2 | n2]; simpl; split.
  - intros H.
    apply tuple_origin_eqb_eq in H.
    subst. repeat split; reflexivity.
  - intros [_ [_ Heq]].
    inversion Heq; subst.
    apply tuple_origin_eqb_eq. reflexivity.
  - intros H