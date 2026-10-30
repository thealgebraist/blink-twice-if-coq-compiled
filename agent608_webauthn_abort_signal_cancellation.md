# Formal Verification Report: WebAuthn Abort Signal Cancellation Responsiveness in Chromium Blink

**Formal Theory Target:** `BlinkWebAuthnAbortSignalSemantics.v`  
**Chromium Component:** `third_party/blink/renderer/modules/credentialmanagement/authenticator_common.cc`  
**Specification Reference:** W3C WebAuthn Level 3 §5.1.3 & §5.1.4; W3C Credential Management Level 1 §2.3 & §2.4  
**Mathematical Property:** $\text{is\_aborted}(\text{sig\_state}) = (\text{sig\_state} \stackrel{?}{=} 1)$; aborted operations reject immediately.

---

## 1. Normative W3C Specification Requirements

The Web Authentication API (WebAuthn) operates as an extension of the W3C Credential Management API. Its asynchronous operations (`navigator.credentials.create()` and `navigator.credentials.get()`) are governed by the `AbortSignal` mechanism defined in the WHATWG DOM specification and integrated via the Credential Management algorithm pipelines.

### 1.1 W3C Credential Management Level 1 (§2.3 & §2.4)
In the core `[[Create]](origin, options, sameOriginWithAncestors)` and `[[CollectFromCredentialStore]](origin, options, sameOriginWithAncestors)` algorithms, the user agent must monitor the `options.signal` attribute (`AbortSignal`) if present:

1. **Immediate Pre-Flight Rejection:** Before dispatching any internal authenticator requests or queuing tasks on the credential management task source, if `options.signal` is present and its `aborted` flag is set (i.e., `signal.aborted == true`), the algorithm must immediately return a new `Promise` rejected with `options.signal`'s `abort reason` (historically a `"AbortError"` `DOMException`). No further steps in the credential creation or assertion pipelines may execute.
2. **In-Flight Asynchronous Cancellation:** While the parallel steps for interacting with authenticators are executing, the user agent must register an abort algorithm with `options.signal`. If the signal transitions to the aborted state while the ceremony is pending, the user agent must:
   - Invoke the authenticator cancellation protocol (` authenticatorCancel` in CTAP2).
   - Reject the pending promise with `options.signal`'s abort reason.
   - Ensure no sub-sequent authenticator responses resolve the already-rejected promise.

### 1.2 W3C WebAuthn Level 3 (§5.1.3 & §5.1.4)
Within `PublicKeyCredential`'s implementations of `[[Create]]` (§5.1.3) and `[[DiscoverFromExternalSource]]` (§5.1.4):

- **Step 5 (Pre-Flight Check):** *"If `options.signal` is present and its aborted flag is set, then return a promise rejected with `options.signal`’s abort reason and abort these steps."*
- **Parallel Loop Condition:** During the lifetime of the `issuedRequests`, if `options.signal`’s abort algorithm is triggered, the user agent must terminate ongoing CTAP/U2F transactions for all authenticators currently processing a request in `issuedRequests`, clear the pending UI state, and reject the outer promise immediately without waiting for hardware timeouts.

---

## 2. Chromium Blink Implementation & Invariants

In Chromium's Blink rendering engine, WebAuthn operations are orchestrated by `AuthenticatorCommonImpl` (located in `third_party/blink/renderer/modules/credentialmanagement/authenticator_common.cc` and `credentials_container.cc`).

### 2.1 Execution Path in `authenticator_common.cc`
When `CredentialsContainer::get` or `CredentialsContainer::create` is invoked with `PublicKeyCredentialRequestOptions` or `PublicKeyCredentialCreationOptions`, execution delegates to `AuthenticatorCommonImpl::Create` or `AuthenticatorCommonImpl::Get`.

```cpp
// Conceptual extraction of the Blink implementation pattern in authenticator_common.cc
void AuthenticatorCommonImpl::Create(
    LocalDOMWindow* window,
    const CredentialCreationOptions* options,
    ScriptPromiseResolver* resolver) {
  
  // 1. Pre-flight check for AbortSignal state
  if (options->hasSignal() && options->signal()->aborted()) {
    resolver->Reject(options->signal()->reason( resolver->GetScriptState() ));
    return;
  }

  // 2. Enforce single pending request invariant
  if (has_pending_request_) {
    resolver->Reject(MakeGarbageCollected<DOMException>(
        DOMExceptionCode::kOperationError,
        "A request is already pending."));
    return;
  }

  // 3. Register in-flight abort handle
  if (options->hasSignal()) {
    abort_handle_ = options->signal()->AddAlgorithm(
        WTF::BindOnce(&AuthenticatorCommonImpl::Cancel, WrapWeakPersistent(this)));
  }

  // 4. Transition to Pending state and dispatch Mojo IPC
  has_pending_request_ = true;
  resolver_ = resolver;
  authenticator_remote_->MakeCredential(
      std::move(mojo_options),
      WTF::BindOnce(&AuthenticatorCommonImpl::OnRegisterResponse,
                    WrapPersistent(this)));
}
```

### 2.2 Cancellation Handler (`AuthenticatorCommonImpl::Cancel`)
When the JavaScript environment invokes `AbortController.abort()`, Blink synchronously triggers the registered algorithm bound to `AuthenticatorCommonImpl::Cancel()`:

```cpp
void AuthenticatorCommonImpl::Cancel() {
  if (!has_pending_request_)
    return;

  // Dispatch asynchronous cancellation to the Browser Process over Mojo
  authenticator_remote_->Cancel();
  
  // Note: In Blink's Mojo pipeline, Cancel() signals the browser's AuthenticatorImpl,
  // which aborts the FidoRequestHandler and triggers the callback with 
  // AuthenticatorStatus::ABORT_ERROR, or resolves immediately via Cleanup().
  CleanupAndRejectWithAbortReason();
}
```

### 2.3 Core Implementation Invariants
To guarantee conformance to WebAuthn Level 3 §5.1.3 and prevent Use-After-Free (UAF), double-resolution, or state corruption vulnerabilities in the renderer, `authenticator_common.cc` maintains four strict invariants:

1. **Invariant I1 (Immediate Pre-Flight Rejection):** If `signal->aborted()` evaluates to `true` ($sig\_state = 1$) at invocation entry, the transition system rejects the `ScriptPromiseResolver` immediately, returns control to the caller, and does *not* mutate `has_pending_request_` or emit any Mojo IPC (`MakeCredential` / `GetAssertion`).
2. **Invariant I2 (In-Flight Cancellation Responsiveness):** If the signal transitions to aborted ($sig\_state = 1$) while a request is active (`has_pending_request_ == true`), the operation transitions unconditionally to the `RejectedAbort` state, invokes `Cleanup()`, and releases the `abort_handle_`.
3. **Invariant I3 (Promise Settlement Finality):** Once a request has settled into `Resolved` or `Rejected` (including `RejectedAbort`), subsequent asynchronous Mojo callbacks (e.g., a race where the hardware authenticator responds just as the user aborts) cannot override the settled promise state.
4. **Invariant I4 (Mutual Exclusion of Pending Requests):** At most one request may be in flight per `AuthenticatorCommonImpl` instance (`has_pending_request_`). An immediate pre-flight abort on a second overlapping call must reject with the abort reason *before* checking or corrupting the in-flight state of the primary request.

---

## 3. Formal Specification in Rocq / Coq

We model the state machine of `AuthenticatorCommonImpl` and the `AbortSignal` semantics in Rocq (Coq) using the `ZArith`, `Lia`, and `Bool` standard libraries. The theory file `BlinkWebAuthnAbortSignalSemantics.v` formalizes the exact discrete transitions of the C++ implementation.

```coq
(** * BlinkWebAuthnAbortSignalSemantics.v
    Formal verification of WebAuthn AbortSignal cancellation responsiveness
    in Chromium Blink (authenticator_common.cc). *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Bool.Bool.
Require Import Coq.Micromega.Lia.
Require Import Coq.Lists.List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Mathematical Predicate for AbortSignal *)

(** A signal state is represented as an integer:
    0 = Unaborted (active/listening)
    1 = Aborted (triggered via AbortController.abort()) *)
Definition SigState := Z.

Definition SIG_UNABORTED : SigState := 0.
Definition SIG_ABORTED   : SigState := 1.

(** Target Mathematical Property:
    is_aborted(sig_state) = (sig_state =? 1) *)
Definition is_aborted (sig_state : SigState) : bool :=
  sig_state =? 1.

(** Well-formedness predicate for signal states *)
Definition wf_sig_state (s : SigState) : Prop :=
  s = 0 \/ s = 1.

(** ** 2. Blink Promise and Authenticator State Definitions *)

(** Represents the settlement status of blink::ScriptPromiseResolver *)
Inductive PromiseStatus : Type :=
  | PromiseIdle             (** Before operation initiation *)
  | PromisePending          (** Operation in-flight over Mojo *)
  | PromiseResolved         (** Settled with PublicKeyCredential *)
  | PromiseRejectedAbort    (** Settled with AbortError / signal.reason *)
  | PromiseRejectedOpError  (** Settled with OperationError (e.g. pending conflict) *)
  | PromiseRejectedOther.   (** Settled with NotAllowedError, InvalidStateError, etc. *)

(** Decidable equality for PromiseStatus *)
Definition promise_status_eqb (p1 p2 : PromiseStatus) : bool :=
  match p1, p2 with
  | PromiseIdle, PromiseIdle => true
  | PromisePending, PromisePending => true
  | PromiseResolved, PromiseResolved => true
  | PromiseRejectedAbort, PromiseRejectedAbort => true
  | PromiseRejectedOpError, PromiseRejectedOpError => true
  | PromiseRejectedOther, PromiseRejectedOther => true
  | _, _ => false
  end.

(** Classification of terminal (settled) promise states *)
Definition is_settled (p : PromiseStatus) : bool :=
  match p with
  | PromiseResolved
  | PromiseRejectedAbort
  | PromiseRejectedOpError
  | PromiseRejectedOther => true
  | _ => false
  end.

(** Classification of immediate abort rejection *)
Definition is_rejected_abort (p : PromiseStatus) : bool :=
  promise_status_eqb p PromiseRejectedAbort.

(** State of Blink's AuthenticatorCommonImpl instance *)
Record AuthenticatorState : Type := mkAuthState {
  has_pending_request : bool;          (** C++ member: has_pending_request_ *)
  mojo_ipc_active     : bool;          (** Whether Mojo MakeCredential/GetAssertion is active *)
  abort_handle_active : bool;          (** Whether AbortSignal::AlgorithmHandle is registered *)
  promise_status      : PromiseStatus; (** Status of the current ScriptPromiseResolver *)
  sig_state           : SigState       (** Current state of options.signal *)
}.

(** Initial idle state of AuthenticatorCommonImpl *)
Definition init_auth_state (initial_sig : SigState) : AuthenticatorState :=
  mkAuthState false false false PromiseIdle initial_sig.

(** System invariant capturing valid reachable configurations in Blink *)
Definition auth_state_invariant (st : AuthenticatorState) : Prop :=
  wf_sig_state (sig_state st) /\
  (has_pending_request st = true <-> promise_status st = PromisePending) /\
  (mojo_ipc_active st = true -> has_pending_request st = true) /\
  (abort_handle_active st = true -> has_pending_request st = true) /\
  (is_aborted (sig_state st) = true -> has_pending_request st = false).

(** ** 3. Operational Semantics of authenticator_common.cc *)

(** Step 1: Pre-Flight Invocation (Create / Get entry point)
    Models the synchronous entry logic in AuthenticatorCommonImpl::Create/Get. *)
Definition step_invoke (st : AuthenticatorState) (call_sig : SigState) : AuthenticatorState :=
  if is_aborted call_sig then
    (* WebAuthn §5.1.3 Step 5: Immediate rejection on aborted signal.
       Note: Does not disturb an existing pending request if one exists,
       resolving the new call's promise immediately with AbortError.
       Here we model the state projection for the invoked operation. *)
    mkAuthState false false false PromiseRejectedAbort call_sig
  else if has_pending_request st then
    (* Reject overlapping request with OperationError *)
    mkAuthState (has_pending_request st)
                (mojo_ipc_active st)
                (abort_handle_active st)
                PromiseRejectedOpError
                call_sig
  else
    (* Normal transition: register abort algorithm and dispatch Mojo IPC *)
    mkAuthState true true true PromisePending call_sig.

(** Step 2: Synchronous Abort Trigger (AbortController.abort() called in JS)
    Models the signal transitioning to 1 and synchronously invoking
    AuthenticatorCommonImpl::Cancel() via the registered abort algorithm. *)
Definition step_abort_signal (st : AuthenticatorState) : AuthenticatorState :=
  let st_with_sig := mkAuthState (has_pending_request st)
                                 (mojo_ipc_active st)
                                 (abort_handle_active st)
                                 (promise_status st)
                                 SIG_ABORTED in
  if is_aborted (sig_state st_with_sig) then
    if has_pending_request st_with_sig then
      (* In-flight request is cancelled immediately and cleaned up *)
      mkAuthState false false false PromiseRejectedAbort SIG_ABORTED
    else if promise_status_eqb (promise_status st_with_sig) PromiseIdle then
      (* Pre-flight idle state with aborted signal *)
      mkAuthState false false false PromiseRejectedAbort SIG_ABORTED
    else
      (* Already settled promise remains in its settled state, only signal updates *)
      mkAuthState false false false (promise_status st_with_sig) SIG_ABORTED
  else
    st_with_sig.

(** Step 3: Asynchronous Mojo Response Callback (OnRegisterResponse / OnSignResponse)
    Models the browser process returning a CTAP status over Mojo. *)
Inductive MojoStatus : Type :=
  | MojoSuccess
  | MojoErrorCancel
  | MojoErrorNotAllowed.

Definition step_mojo_response (st : AuthenticatorState) (status : MojoStatus) : AuthenticatorState :=
  if negb (has_pending_request st) then
    (* If no request is pending (e.g., already aborted and cleaned up),
       late Mojo callbacks are ignored (no-op). *)
    st
  else if is_aborted (sig_state st) then
    (* Defensive check: if signal is aborted, must reject with abort *)
    mkAuthState false false false PromiseRejectedAbort (sig_state st)
  else
    match status with
    | MojoSuccess =>
        mkAuthState false false false PromiseResolved (sig_state st)
    | MojoErrorCancel =>
        mkAuthState false false false PromiseRejectedAbort (sig_state st)
    | MojoErrorNotAllowed =>
        mkAuthState false false false PromiseRejectedOther (sig_state st)
    end.
```

---

## 4. Concrete Theorems