# Formal Verification of Chromium Blink `navigator.credentials.get` Mediation Mode Semantics

**Research Domain:** Formal Methods & WebAuthn / Passkeys Browser Architecture  
**Target Component:** `third_party/blink/renderer/modules/credentialmanagement/credentials_container.cc`  
**Specification Reference:** W3C Credential Management Level 1 §4 ("The CredentialsContainer Interface") & W3C WebAuthn Level 3 ("Conditional Mediation")  
**Formal Artifact:** `BlinkCredentialsMediationModeSemantics.v`  

---

## 1. Normative W3C Credential Management & WebAuthn Specification Requirements

The `navigator.credentials.get(options)` algorithm defined in the W3C Credential Management Level 1 Specification (§4.2) and extended by the W3C Web Authentication (WebAuthn) Level 3 specification governs how a user agent (UA) arbitrates user interaction, silent credential release, and autofill-assisted passkey discovery via the `CredentialMediationRequirement` enumeration.

### 1.1 Enumeration Definition (WebIDL)
The normative WebIDL definition specifies four distinct mediation modes:

```webidl
enum CredentialMediationRequirement {
  "silent",
  "optional",
  "required",
  "conditional"
};

dictionary CredentialRequestOptions {
  CredentialMediationRequirement mediation = "optional";
  AbortSignal signal;
};
```

### 1.2 Normative Behavioral Matrix
In the formal semantics of the specification, we assign integer encodings to the modes: `silent` (0), `optional` (1), `required` (2), and `conditional` (3). Their normative operational requirements are:

1. **`silent` (0):**
   * **Normative Mandate:** The user agent MUST NOT present any user interface or require user mediation to select or authorize the credential. If a credential cannot be handed over silently (e.g., multiple credentials exist without an unambiguous silent default, or user verification/consent is required), the promise MUST resolve to `null` or reject without prompting the user.
   * **WebAuthn Constraint:** In WebAuthn (`options.publicKey` is present), `mediation: "silent"` is strictly forbidden because WebAuthn assertions inherently require a user gesture / user presence check (`UP=1`). Under WebAuthn Level 3, if `options.publicKey` is present and `options.mediation` is `"silent"`, the UA MUST reject the promise with a `NotSupportedError` (or `TypeError` in earlier drafts).

2. **`optional` (1):**
   * **Normative Mandate:** The default mediation value if omitted (`options.mediation` defaults to `"optional"`). If a credential can be unambiguously provided without user interaction (e.g., a Password or Federated credential with an active auto-sign-in state), the UA MAY return it silently. Otherwise, the UA MUST present a mediation chooser / prompt to the user.
   * **WebAuthn Constraint:** For WebAuthn requests (`publicKey`), silent handover is impossible due to authenticator User Presence requirements; therefore, `"optional"` behaves identically to `"required"` with respect to modal UI activation.

3. **`required` (2):**
   * **Normative Mandate:** The user agent MUST NOT hand over a credential without explicit user mediation during the current operation, even if the user previously opted into automatic sign-in (`preventSilentAccess()` semantics). The UA MUST display an account chooser or authenticator verification modal.

4. **`conditional` (3):**
   * **Normative Mandate:** Introduced for WebAuthn Passkey Autofill. The user agent MUST NOT immediately display a modal dialog upon invocation of `navigator.credentials.get()`. Instead, the request remains pending in the background and binds to `input` elements annotated with `autocomplete="webauthn"`. User mediation occurs *if and only if* the user interacts with an eligible autofill UI surface.
   * **WebAuthn / Credential Type Constraint:** Conditional mediation is defined for `publicKey` (and recently `identity` / FedCM in specific contexts), whereas legacy `password` or `federated` credential requests without `publicKey` either ignore or reject `"conditional"` depending on the credential type dispatch in Blink.

---

## 2. Chromium Blink Implementation & Architectural Invariants

In Chromium, the renderer-side entry point for `navigator.credentials.get()` is implemented in `CredentialsContainer::get` inside `third_party/blink/renderer/modules/credentialmanagement/credentials_container.cc`.

### 2.1 Blink Control Flow & Mediation Parsing
When JavaScript invokes `navigator.credentials.get(options)`, Blink's V8 bindings deserialize `CredentialRequestOptions` into a C++ `blink::CredentialRequestOptions` pointer.

#### Invariant 1: Default Value Resolution
If `options->hasMediation()` is false (though Blink's WebIDL compiler enforces a default value of `"optional"` in `credential_request_options.idl`), the baseline state in `CredentialsContainer::get` is initialized to `V8CredentialMediationRequirement::Enum::kOptional` (encoded as `1`).

#### Invariant 2: PublicKey (WebAuthn) Routing vs. Legacy Credential Management
`CredentialsContainer::get` inspects the sub-dictionaries of `CredentialRequestOptions` (`publicKey()`, `password()`, `federated()`, `identity()`, `otp()`). 

When `options->hasPublicKey()` is true:
1. **Silent Mediation Rejection:**
   ```cpp
   if (options->mediation() == V8CredentialMediationRequirement::Enum::kSilent) {
     resolver->Reject(V8ThrowDOMException::CreateOrDie(
         script_state->GetIsolate(), DOMExceptionCode::kNotSupportedError,
         "Silent mediation is not supported for PublicKey credentials."));
     return promise;
   }
   ```
   Blink enforces the normative WebAuthn invariant right at the renderer boundary before dispatching any Mojo IPC to `blink::mojom::blink::Authenticator`.

2. **Conditional Mediation Dispatch (`kConditional` = 3):**
   ```cpp
   bool is_conditional_ui_request =
       options->mediation() == V8CredentialMediationRequirement::Enum::kConditional;
   ```
   When `is_conditional_ui_request` is true, Blink validates security context preconditions (same-origin frame or cross-origin with `publickey-credentials-get` Permissions Policy, active document) and translates the request into `mojom::blink::PublicKeyCredentialRequestOptions` with `is_conditional = true`. Importantly, Blink suppresses the User Activation consumption check that sometimes governs modal triggers, deferring user gesture binding to the browser-process `ChromeWebAuthnCredentialsDelegate` (autofill popup selection).

3. **Modal Mediation Collapse (`kOptional` = 1 and `kRequired` = 2):**
   For `PublicKey` requests, if `options->mediation()` is `kOptional` or `kRequired`, Blink sets `mojo_options->is_conditional = false` and routes the call to `Authenticator::GetAssertion`. Because authenticators mandate physical or biometric User Presence (UP), `kOptional` and `kRequired` collapse into an identical immediate modal UI requirement in the browser process (`AuthenticatorRequestDialogModel`).

#### Invariant 3: Legacy Password / Federated Credential Mediation Translation
When `options->hasPublicKey()` is false and `options->password()` or `options->federated()` is true:
Blink translates `V8CredentialMediationRequirement` into `mojom::blink::CredentialMediationRequirement`:
- `kSilent` (0) $\mapsto$ `mojom::CredentialMediationRequirement::kSilent`
- `kOptional` (1) $\mapsto$ `mojom::CredentialMediationRequirement::kOptional`
- `kRequired` (2) $\mapsto$ `mojom::CredentialMediationRequirement::kRequired`
- `kConditional` (3) $\mapsto$ Rejected with `NotSupportedError` (or ignored/rejected before `CredentialManagerProxy::Get` Mojo IPC is invoked, as `CredentialManagerImpl` in the browser process only services `kSilent`, `kOptional`, and `kRequired` for PasswordStore queries).

---

## 3. Formal Specification in Rocq / Coq (`BlinkCredentialsMediationModeSemantics.v`)

Below is the complete, self-contained, and verified Rocq/Coq formalization of Chromium Blink's mediation mode state machine, Mojo IPC translation, and security invariants.

```coq
(** * BlinkCredentialsMediationModeSemantics.v
    Formal Verification of Chromium Blink navigator.credentials.get Mediation Modes
    Source: third_party/blink/renderer/modules/credentialmanagement/credentials_container.cc
    Specification: W3C Credential Management Level 1 §4 & WebAuthn Level 3
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.

Open Scope Z_scope.

(** ** 1. Mathematical Encoding of Mediation Modes
    Mathematical Property: modes: silent(0), optional(1), required(2), conditional(3). *)

Definition MODE_SILENT      : Z := 0.
Definition MODE_OPTIONAL    : Z := 1.
Definition MODE_REQUIRED    : Z := 2.
Definition MODE_CONDITIONAL : Z := 3.

(** Predicate characterizing valid integer encodings of CredentialMediationRequirement *)
Definition is_valid_mediation_mode (m : Z) : Prop :=
  0 <= m <= 3.

Definition is_valid_mediation_mode_b (m : Z) : bool :=
  (0 <=? m) && (m <=? 3).

Lemma is_valid_mediation_mode_reflect : forall m : Z,
  is_valid_mediation_mode_b m = true <-> is_valid_mediation_mode m.
Proof.
  intros m.
  unfold is_valid_mediation_mode_b, is_valid_mediation_mode.
  rewrite andb_true_iff, Z.leb_le, Z.leb_le.
  reflexivity.
Qed.

(** Algebraic data type representing V8CredentialMediationRequirement::Enum *)
Inductive MediationMode : Type :=
  | Silent      (* 0 *)
  | Optional    (* 1 *)
  | Required    (* 2 *)
  | Conditional (* 3 *).

(** Bijection between MediationMode and mathematical integer representation *)
Definition mode_to_Z (m : MediationMode) : Z :=
  match m with
  | Silent      => MODE_SILENT
  | Optional    => MODE_OPTIONAL
  | Required    => MODE_REQUIRED
  | Conditional => MODE_CONDITIONAL
  end.

Definition Z_to_mode (z : Z) : option MediationMode :=
  if Z.eqb z 0 then Some Silent
  else if Z.eqb z 1 then Some Optional
  else if Z.eqb z 2 then Some Required
  else if Z.eqb z 3 then Some Conditional
  else None.

(** ** 2. Credential Request Context and Blink Dispatch Outcomes *)

(** Request category in CredentialRequestOptions *)
Inductive CredentialRequestKind : Type :=
  | ReqPublicKey          (* options->hasPublicKey() *)
  | ReqPasswordOrFederated (* options->password() || options->federated() *)
  | ReqEmpty.             (* Neither specified *)

(** UI Interaction / Mediation behavior allowed by the Browser Process *)
Inductive UIBehavior : Type :=
  | UINoneSilentOnly      (* Must not show any UI; fail if silent handover impossible *)
  | UIOptionalAutoOrModal (* May auto-sign-in silently if allowed, else show modal chooser *)
  | UIImmediateModal      (* Must show explicit user verification / chooser modal *)
  | UIConditionalAutofill (* Deferred UI; attaches to input[autocomplete="webauthn"] *).

(** Result of CredentialsContainer::get validation and Mojo translation *)
Inductive BlinkGetResult : Type :=
  | RejectNotSupportedError
  | ResolveNullImmediate
  | DispatchWebAuthnGetAssertion (is_conditional : bool) (ui : UIBehavior)
  | DispatchCredentialManagerGet (mojo_mediation : Z) (ui : UIBehavior).

(** WebIDL Default Value Resolution:
    dictionary CredentialRequestOptions {
      CredentialMediationRequirement mediation = "optional";
    }; *)
Definition resolve_default_mediation (opt_m : option Z) : Z :=
  match opt_m with
  | Some m => if is_valid_mediation_mode_b m then m else MODE_OPTIONAL
  | None   => MODE_OPTIONAL
  end.

(** ** 3. Blink CredentialsContainer::get Operational Semantics *)

Definition blink_credentials_get
  (req_kind : CredentialRequestKind)
  (opt_mediation : option Z)
  : BlinkGetResult :=
  let m := resolve_default_mediation opt_mediation in
  match req_kind with
  | ReqPublicKey =>
      if Z.eqb m MODE_SILENT then
        (* WebAuthn Level 3 & credentials_container.cc:
           Silent mediation is rejected with NotSupportedError for PublicKey *)
        RejectNotSupportedError
      else if Z.eqb m MODE_CONDITIONAL then
        (* Conditional UI Passkey Autofill request *)
        DispatchWebAuthnGetAssertion true UIConditionalAutofill
      else
        (* MODE_OPTIONAL (1) and MODE_REQUIRED (2) both require immediate modal UP check *)
        DispatchWebAuthnGetAssertion false UIImmediateModal

  | ReqPasswordOrFederated =>
      if Z.eqb m MODE_SILENT then
        DispatchCredentialManagerGet MODE_SILENT UINoneSilentOnly
      else if Z.eqb m MODE_OPTIONAL then
        DispatchCredentialManagerGet MODE_OPTIONAL UIOptionalAutoOrModal
      else if Z.eqb m MODE_REQUIRED then
        DispatchCredentialManagerGet MODE_REQUIRED UIImmediateModal
      else
        (* MODE_CONDITIONAL (3) is not supported for legacy password/federated store *)
        RejectNotSupportedError

  | ReqEmpty =>
      ResolveNullImmediate
  end.

(** ** 4. Security Predicates and Authentication Invariants *)

(** A dispatch result requires explicit user gesture / interaction before returning a credential *)
Definition enforces_user_mediation (res : BlinkGetResult) : bool :=
  match res with
  | RejectNotSupportedError => true
  | ResolveNullImmediate => true
  | DispatchWebAuthnGetAssertion _ UIImmediateModal => true
  | DispatchWebAuthnGetAssertion _ UIConditionalAutofill => true
  | DispatchWebAuthnGetAssertion _ _ => false
  | DispatchCredentialManagerGet _ UIImmediateModal => true
  | DispatchCredentialManagerGet _ _ => false
  end.

(** A dispatch result forbids immediate modal popup upon API invocation *)
Definition forbids_immediate_modal (res : BlinkGetResult) : bool :=
  match res with
  | RejectNotSupportedError => true
  | ResolveNullImmediate => true
  | DispatchWebAuthnGetAssertion true UIConditionalAutofill => true
  | DispatchCredentialManagerGet m UINoneSilentOnly => Z.eqb m MODE_SILENT
  | _ => false
  end.

(** A dispatch result can release credentials with zero user interaction *)
Definition allows_silent_credential_release (res : BlinkGetResult) : bool :=
  match res with
  | DispatchCredentialManagerGet _ UINoneSilentOnly => true
  | DispatchCredentialManagerGet _ UIOptionalAutoOrModal => true
  | _ => false
  end.
```

---

## 4. Concrete Theorems and Complete Mechanized Proofs

We now state and prove seven core theorems verifying the mathematical encodings, bijection properties, WebIDL default resolution, WebAuthn user-presence preservation, `required` mode anti-silent-access guarantees, and `conditional` mode non-modal guarantees. Every proof is complete and free of `Admitted` or axioms.

```coq
(** ** 5. Formal