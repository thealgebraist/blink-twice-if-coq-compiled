# Formal Verification of Chromium Blink's Digital Credentials API Protocol Request Encapsulation

**Target Source**: `third_party/blink/renderer/modules/credentialmanagement/digital_identity_credential.cc`  
**Specification**: W3C Digital Credentials API §3 ("The `DigitalCredential` Interface" and `DigitalCredentialRequestOptions`) & W3C Credential Management Level 1  
**Formal Theory Target**: `BlinkDigitalCredentialsProtocolSemantics.v`  
**Mathematical Property**: $\text{protocol\_supported}(p) = (p =? 1) \lor (p =? 2)$

---

## 1. Normative Specification Requirements

The W3C Digital Credentials API extends the W3C Credential Management API (`navigator.credentials.get()`) to enable Relying Parties (RPs) to request cryptographic presentations of digital identity credentials (such as ISO/IEC 18013-5 mDocs and OpenID for Verifiable Presentations [OpenID4VP]).

### 1.1 WebIDL Interfaces (§3)
According to §3 of the W3C Digital Credentials API specification, the request structure is defined via the following WebIDL dictionaries:

```webidl
partial dictionary CredentialRequestOptions {
  DigitalCredentialRequestOptions digital;
};

dictionary DigitalCredentialRequestOptions {
  sequence<DigitalCredentialRequest> providers; // Renamed to `requests` in recent drafts
};

dictionary DigitalCredentialRequest {
  required DOMString protocol;
  required object data;
};
```

### 1.2 Normative Processing Model
When `navigator.credentials.get(options)` is invoked with `options.digital` present, the User Agent (UA) must execute the **Request a Digital Credential** algorithm:

1. **Context Validation**: Verify that the current `Document` is in a Secure Context (`window.isSecureContext === true`) and is the active document of a top-level traversable (or explicitly delegated via Permissions Policy `digital-credentials-get`).
2. **Provider/Request List Validation**:
   - If `options.digital.providers` (or `requests`) is empty, reject the promise with a `TypeError`.
3. **Protocol Encapsulation & Serialization**:
   - For each `request` in `options.digital.providers`:
     - Extract the `protocol` identifier (`DOMString`).
     - Extract the `data` payload (`object` or `DOMString`), convert it to a JSON-formatted string (serializing the ECMAScript object via `JSON.stringify` semantics), and catch any serialization exceptions, rethrowing them as `TypeError`.
4. **Protocol Filtering & Dispatch**:
   - The UA must validate whether the requested `protocol` is supported by the underlying platform bridge (e.g., Android `CredMan` or desktop hybrid transport).
   - Standardized protocols in the registry correspond to:
     - **OpenID4VP** (`"openid4vp"`)
     - **ISO/IEC 18013-5 mDoc** (`"org.iso.mdoc"` / `"mdoc"`)
   - Unrecognized or unsupported protocols must not result in arbitrary unvalidated IPC payload execution; they must either be filtered prior to platform invocation or deterministically rejected with `NotSupportedError` / `DOMException`.

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, the Digital Credentials API is implemented inside `third_party/blink/renderer/modules/credentialmanagement/digital_identity_credential.cc` (interfacing with `CredentialManagerProxy` and Mojo IPC types defined in `third_party/blink/public/mojom/webid/digital_identity_request.mojom`).

### 2.1 Execution Flow in `digital_identity_credential.cc`
The core entry point is `DiscoverDigitalIdentityCredentialFromExternalSource(...)`:

1. **Pre-condition Checks**:
   - Validates `IsDigitalIdentityCredentialTypeSpecified(options)`.
   - Checks `resolver->GetExecutionContext()` validity and verifies transient user activation (`LocalFrame::HasTransientUserActivation`), unless bypassed by specific runtime flags.
2. **Vector Extraction & Non-Empty Invariant**:
   - Inspects `options.digital()->providers()` (or `requests()`).
   - If the vector is empty, it invokes `resolver->RejectWithTypeError(...)` and terminates immediately before any Mojo IPC allocation.
3. **Payload Stringification & Mojo Struct Encapsulation**:
   - Iterates over each `IdentityRequestProvider` / `DigitalCredentialRequest` in theBlink IDL sequence.
   - Invokes `v8::JSON::Stringify` on the `request` / `data` ScriptValue. If stringification fails or yields an empty handle, an exception state is raised, aborting the operation.
   - Constructs a ` payments::mojom::blink::DigitalIdentityRequestPtr` (or `blink::mojom::blink::DigitalCredentialSelectorPtr`) containing:
     - `String protocol`: The exact protocol identifier string.
     - `String request`: The canonicalized JSON string representation of the request dictionary.
4. **Protocol Validation & IPC Dispatch**:
   - The Blink layer or browser-side `DigitalIdentityRequestImpl` validates the encapsulated protocol identifier against supported presentation protocols (`1` = OpenID4VP, `2` = ISO-18013-5 mDoc).

### 2.2 Security Invariants
- **Invariant 1 (Encapsulation Completeness)**: Every Mojo IPC request dispatched to the browser process must contain a non-empty, syntactically valid JSON payload paired with an explicit protocol tag.
- **Invariant 2 (Strict Protocol Partitioning)**: Let $P$ be the domain of protocol identifiers mapped to integers ($\mathbb{Z}$), where $1$ denotes `OpenID4VP` and $2$ denotes `ISO-18013-5`. A protocol $p \in \mathbb{Z}$ is accepted by the normative validator if and only if $\text{protocol\_supported}(p) = \text{true}$, defined as $(p =? 1) \lor (p =? 2)$.
- **Invariant 3 (Batch Rejection on Unsupported Protocol)**: Under strict validation semantics, a batch request containing any unsupported protocol $p \notin \{1, 2\}$ fails validation, preventing confused-deputy attacks across heterogeneous wallet providers.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of the Digital Credentials API protocol encapsulation and validation semantics in Rocq (Coq), targeting `BlinkDigitalCredentialsProtocolSemantics.v`.

```coq
(** * BlinkDigitalCredentialsProtocolSemantics.v
    Formal verification of Chromium Blink's Digital Credentials API
    protocol request encapsulation and validation invariants.
    
    Source: third_party/blink/renderer/modules/credentialmanagement/digital_identity_credential.cc
    Specification: W3C Digital Credentials API §3
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Protocol Identifier Semantics *)

(** Protocol identifiers are modeled as integers (Z).
    1 represents OpenID4VP ("openid4vp").
    2 represents ISO-18013-5 ("org.iso.mdoc").
    All other integers represent unrecognized/unsupported protocols. *)
Definition ProtocolId := Z.

Definition PROTOCOL_OPENID4VP : ProtocolId := 1.
Definition PROTOCOL_ISO_18013_5 : ProtocolId := 2.

(** Core mathematical property:
    protocol_supported(p) = (p =? 1) || (p =? 2) *)
Definition protocol_supported (p : ProtocolId) : bool :=
  (p =? PROTOCOL_OPENID4VP) || (p =? PROTOCOL_ISO_18013_5).

(** ** 2. Request Encapsulation Structures *)

(** Abstract representation of a V8 ScriptValue payload in Blink. *)
Inductive ScriptValuePayload : Type :=
  | ValidJsonObject (serialized_id : Z)
  | UnserializableObject. (* e.g. circular reference or BigInt in JSON.stringify *)

(** WebIDL DigitalCredentialRequest dictionary in Blink *)
Record BlinkDigitalCredentialRequest : Type := mkBlinkRequest {
  req_protocol : ProtocolId;
  req_data : ScriptValuePayload
}.

(** Mojo IPC encapsulated structure sent to Browser process *)
Record MojoDigitalCredentialRequest : Type := mkMojoRequest {
  mojo_protocol : ProtocolId;
  mojo_json_payload : Z
}.

(** Result of Blink's encapsulation and validation pipeline *)
Inductive EncapsulationResult : Type :=
  | EncapSuccess (mojo_requests : list MojoDigitalCredentialRequest)
  | EncapTypeError           (* Empty request list or JSON serialization failure *)
  | EncapNotSupportedError.  (* Unsupported protocol identifier *)

(** ** 3. Blink Encapsulation & Validation Functions *)

(** Encapsulates a single Blink request into a Mojo request if the
    protocol is supported and the payload is JSON-serializable. *)
Definition encapsulate_single (req : BlinkDigitalCredentialRequest) 
  : EncapsulationResult :=
  match req.(req_data) with
  | UnserializableObject => EncapTypeError
  | ValidJsonObject json_id =>
      if protocol_supported req.(req_protocol) then
        EncapSuccess [mkMojoRequest req.(req_protocol) json_id]
      else
        EncapNotSupportedError
  end.

(** Helper to fold over a sequence of requests, preserving order and error precedence. *)
Fixpoint encapsulate_sequence (reqs : list BlinkDigitalCredentialRequest) 
  : EncapsulationResult :=
  match reqs with
  | [] => EncapSuccess []
  | r :: rest =>
      match encapsulate_single r with
      | EncapTypeError => EncapTypeError
      | EncapNotSupportedError => EncapNotSupportedError
      | EncapSuccess [m_req] =>
          match encapsulate_sequence rest with
          | EncapSuccess m_rest => EncapSuccess (m_req :: m_rest)
          | err => err
          end
      | EncapSuccess _ => EncapTypeError (* Unreachable by construction *)
      end
  end.

(** Top-level Blink DiscoverDigitalIdentityCredentialFromExternalSource
    request encapsulation entry point.
    Enforces W3C §3 requirement: empty providers/requests sequence throws TypeError. *)
Definition blink_encapsulate_requests (reqs : list BlinkDigitalCredentialRequest) 
  : EncapsulationResult :=
  match reqs with
  | [] => EncapTypeError
  | _ :: _ => encapsulate_sequence reqs
  end.

(** ** 4. Security Predicates *)

(** A Mojo request is normatively valid if its protocol is supported. *)
Definition mojo_request_valid (m : MojoDigitalCredentialRequest) : Prop :=
  protocol_supported m.(mojo_protocol) = true.

(** All Mojo requests in a dispatched batch are normatively valid. *)
Definition all_mojo_requests_valid (ms : list MojoDigitalCredentialRequest) : Prop :=
  Forall mojo_request_valid ms.
```

---

## 4. Concrete Theorems and Complete Proofs

We now state and prove five foundational theorems establishing algebraic characterization of `protocol_supported`, soundness and completeness of single-request and batch encapsulation, non-empty IPC dispatch guarantees, and full authentication invariant preservation.

```coq
(** ** 5. Formal Verification Theorems and Proofs *)

(** Theorem 1: Exact Characterization of Supported Protocols.
    Proves that protocol_supported(p) = true if and only if p = 1 (OpenID4VP)
    or p = 2 (ISO-18013-5). *)
Theorem protocol_supported_iff : forall (p : ProtocolId),
  protocol_supported p = true <-> (p = 1 \/ p = 2).
Proof.
  intros p.
  unfold protocol_supported, PROTOCOL_OPENID4VP, PROTOCOL_ISO_18013_5.
  rewrite orb_true_iff.
   repeat rewrite Z.eqb_eq.
  reflexivity.
Qed.

(** Theorem 2: Exact Characterization of Unsupported Protocols.
    Proves that any protocol integer outside {1, 2} evaluates to false. *)
Theorem protocol_unsupported_iff : forall (p : ProtocolId),
  protocol_supported p = false <-> (p <> 1 /\ p <> 2).
Proof.
  intros p.
  unfold protocol_supported, PROTOCOL_OPENID4VP, PROTOCOL_ISO_18013_5.
  rewrite orb_false_iff.
  repeat rewrite Z.eqb_neq.
  reflexivity.
Qed.

(** Theorem 3: Decidability and Boundary Rejection for Out-of-Range Protocols.
    Specifically proves that non-positive integers (p <= 0) and integers (p >= 3)
    are strictly rejected by the protocol validator. *)
Theorem protocol_bounds_rejection : forall (p : ProtocolId),
  (p <= 0 \/ p >= 3) -> protocol_supported p = false.
Proof.
  intros p Hbounds.
  apply protocol_unsupported_iff.
  lia.
Qed.

(** Theorem 4: Single Request Encapsulation Soundness.
    If encapsulate_single succeeds, the resulting Mojo request list is a singleton
    whose protocol is strictly either OpenID4VP (1) or ISO-18013-5 (2). *)
Theorem encapsulate_single_sound : forall (req : BlinkDigitalCredentialRequest) (ms : list MojoDigitalCredentialRequest),
  encapsulate_single req = EncapSuccess ms ->
  exists (m : MojoDigitalCredentialRequest),
    ms = [m] /\
    m.(mojo_protocol) = req.(req_protocol) /\
    (m.(mojo_protocol) = 1 \/ m.(mojo_protocol) = 2).
Proof.
  intros req ms Henc.
  unfold encapsulate_single in Henc.
  destruct (req_data req) as [json_id | ] eqn:Hdata.
  - destruct (protocol_supported (req_protocol req)) eqn:Hsupp.
    + inversion Henc; subst.
      exists (mkMojoRequest (req_protocol req) json_id).
      split; [reflexivity | ].
      split; [simpl; reflexivity | ].
      simpl. apply protocol_supported_iff. exact Hsupp.
    + discriminate Henc.
  - discriminate Henc.
Qed.

(** Theorem 5: Inductive Sequence Encapsulation Invariant Preservation.
    Every Mojo request produced by encapsulate_sequence satisfies mojo_request_valid. *)
Lemma encapsulate_sequence_preserves_validity : forall (reqs : list BlinkDigitalCredentialRequest) (ms : list MojoDigitalCredentialRequest),
  encapsulate_sequence reqs = EncapSuccess ms ->
  all_mojo_requests_valid ms /\ length ms = length reqs.
Proof.
  induction reqs as [| r rest IH]; intros ms Hseq.
  - simpl in Hseq. inversion Hseq; subst.
    split.
    + unfold all_mojo_requests_valid. constructor.
    + reflexivity.
  - simpl in Hseq.
    destruct (encapsulate_single r) as [ms_single | | ] eqn:Hsingle; try discriminate Hseq.
    apply encapsulate_single_sound in Hsingle.
    destruct Hsingle as [m_req [Hms_eq [Hprot_eq Hprot_valid]]].
    subst ms_single.
    destruct (encapsulate_sequence rest) as [ms_rest |