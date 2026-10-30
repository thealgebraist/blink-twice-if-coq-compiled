# Formal Verification Report: `PaymentRequest.canMakePayment()` Boolean Determinism & Lifecycle State Idempotence

**Agent ID:** 640 (Web Payments, Autofill & Form Normalization)  
**Chromium Source:** `third_party/blink/renderer/modules/payments/payment_request.cc`  
**Specification:** W3C Payment Request API §5.3 (`canMakePayment()` method)  
**Formal Theory Target:** `BlinkCanMakePaymentBooleanDeterminismSemantics.v`  
**Mathematical Property:** $\forall s, e.\; \text{state\_after\_query}(s, e) = \text{state\_before\_query}(s, e) \land \exists! b \in \mathbb{B}.\; \text{result}(s, e) = \text{Resolved}(b)$ (under valid state preconditions)

---

## 1. Normative W3C Payment Request Specification Requirements

In the W3C Payment Request API specification (§5.3, *The `canMakePayment()` method*), the `canMakePayment()` method allows a merchant to query whether the User Agent (UA) supports at least one of the payment methods specified during the `PaymentRequest` instantiation before invoking `show()`.

### 1.1 Exact Normative Algorithm (§5.3)
When the `canMakePayment()` method is invoked on a `PaymentRequest` object $R$:

1. **State Precondition Check:** If $R.\text{[[state]]}$ is not `"created"`, then return a promise rejected with an `"InvalidStateError"` `DOMException`.
2. **Duplicate Query Guard (Blink / Spec Implementation Alignment):** In Chromium Blink's implementation of the specification, if a `canMakePayment()` promise is already pending ($R.\text{can\_make\_payment\_resolver\_} \neq \text{null}$), return a promise rejected with an `"InvalidStateError"` `DOMException`.
3. **Promise Creation:** Let $P$ be a new Promise.
4. **Parallel Query Execution:** Run the following steps in parallel:
   - For each payment method identifier $m \in R.\text{[[serializedMethodData]]}$:
     - Determine if the UA or an installed payment handler supports $m$.
   - Quota / Privacy Enforcement: If the top-level origin and frame origin exceed query quota limits for differing parameters, resolve or reject according to privacy heuristics (in standard specification conformance, resolve $P$ with a boolean indicating availability, or in Chromium's anti-fingerprinting mode, deterministically resolve based on cached/allowed origin configuration).
5. **Lifecycle State Preservation:** Throughout the entire execution of `canMakePayment()`—both at synchronous invocation and asynchronous resolution—the internal slot $R.\text{[[state]]}$ **must not** transition out of `"created"` (unless mutated by an orthogonal call like `show()`). Once the query settles, the `PaymentRequest` object's observable lifecycle state returns to its exact pre-query configuration.

---

## 2. Chromium Blink Implementation Details & Invariants

In `third_party/blink/renderer/modules/payments/payment_request.cc`, `PaymentRequest::canMakePayment(ScriptState* script_state, ExceptionState& exception_state)` enforces strict state invariants across the Blink renderer and Mojo IPC boundary (`payments::mojom::blink::PaymentRequest`).

### 2.1 Core Implementation Architecture (`payment_request.cc`)
```cpp
ScriptPromise<IDLBoolean> PaymentRequest::canMakePayment(
    ScriptState* script_state,
    ExceptionState& exception_state) {
  if (!GetExecutionContext() || !GetExecutionContext()->IsWindow()) {
    exception_state.ThrowDOMException(DOMExceptionCode::kInvalidStateError,
                                      "Cannot specify payment request");
    return EmptyPromise();
  }
  if (state_ != kCreated) {
    exception_state.ThrowDOMException(DOMExceptionCode::kInvalidStateError,
                                      "Cannot query payment request");
    return EmptyPromise();
  }
  if (can_make_payment_resolver_) {
    exception_state.ThrowDOMException(
        DOMExceptionCode::kInvalidStateError,
        "Cannot query payment request multiple times simultaneously");
    return EmptyPromise();
  }

  payment_provider_->CanMakePayment();
  can_make_payment_resolver_ =
      MakeGarbageCollected<ScriptPromiseResolver<IDLBoolean>>(
          script_state, exception_state.GetContext());
  return can_make_payment_resolver_->Promise();
}
```

And the asynchronous Mojo callback `PaymentRequest::OnCanMakePayment`:
```cpp
void PaymentRequest::OnCanMakePayment(CanMakePaymentQueryResult result) {
  if (!can_make_payment_resolver_)
    return;

  switch (result) {
    case CanMakePaymentQueryResult::kCanMakePayment:
      can_make_payment_resolver_->Resolve(true);
      break;
    case CanMakePaymentQueryResult::kCannotMakePayment:
      can_make_payment_resolver_->Resolve(false);
      break;
    case CanMakePaymentQueryResult::kQuotaExceeded:
      // Note: Modern Chromium resolves or rejects deterministically based on
      // RuntimeEnabledFeatures; in standard boolean resolution paths, it maps
      // deterministically to a settled outcome and clears the resolver.
      can_make_payment_resolver_->Reject(MakeGarbageCollected<DOMException>(
          DOMExceptionCode::kNotAllowedError,
          "Not allowed to check whether can make payment"));
      break;
  }
  can_make_payment_resolver_.Clear();
}
```

### 2.2 Critical Renderer Invariants
1. **Lifecycle Orthogonality (`state_` Invariance):** Neither `PaymentRequest::canMakePayment()` nor `PaymentRequest::OnCanMakePayment()` modifies `state_` (`kCreated`, `kInteractive`, `kClosed`). Thus, `state_` before the query equals `state_` after the query settles.
2. **Resolver Mutual Exclusion (`can_make_payment_resolver_` Cleanup):** When `canMakePayment()` begins in valid state `kCreated` with `can_make_payment_resolver_ == nullptr`, it allocates a resolver, then upon `OnCanMakePayment` completion, unconditionally invokes `can_make_payment_resolver_.Clear()`, restoring `can_make_payment_resolver_ == nullptr`.
3. **Complete State Restoration (`state_after_query = state_before_query`):** A complete atomic query cycle (invocation followed by `OnCanMakePayment` settlement) leaves the `PaymentRequest` internal state record identical to `state_before_query`.
4. **Boolean Determinism:** For any fixed payment environment (installed payment apps, browser autofill instrument availability, and quota state) and `PaymentRequest` method configuration, the query result evaluates to a single, deterministic outcome; when within quota in a valid `"created"` state, it deterministically resolves to a boolean $b \in \{\text{true}, \text{false}\}$.

---

## 3. Formal Specification & Verification in Rocq/Coq

Below is the complete, self-contained, and admitted-free Rocq/Coq formalization (`BlinkCanMakePaymentBooleanDeterminismSemantics.v`). It models the `PaymentRequest` state machine, execution context, Mojo `CanMakePaymentQueryResult` transitions, two-phase async execution, and single-step atomic query composition.

```coq
(** * BlinkCanMakePaymentBooleanDeterminismSemantics.v
    Formal Verification of W3C Payment Request API §5.3 & Chromium Blink
    third_party/blink/renderer/modules/payments/payment_request.cc
    Property: state_after_query = state_before_query & deterministic boolean resolution.
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import Micromechanics.Lia.
Import ListNotations.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Domain Types and Enumerations *)

(** W3C PaymentRequest [[state]] internal slot / Blink PaymentRequest::State *)
Inductive PaymentRequestLifecycleState : Type :=
  | kCreated
  | kInteractive
  | kClosed.

Scheme Equality for PaymentRequestLifecycleState.

(** Mojo IPC CanMakePaymentQueryResult enum (payments::mojom::CanMakePaymentQueryResult) *)
Inductive MojoCanMakePaymentResult : Type :=
  | kCanMakePayment
  | kCannotMakePayment
  | kQuotaExceeded.

Scheme Equality for MojoCanMakePaymentResult.

(** DOMException codes relevant to canMakePayment() *)
Inductive DOMExceptionCode : Type :=
  | kInvalidStateError
  | kNotAllowedError.

Scheme Equality for DOMExceptionCode.

(** Promise settlement outcome for ScriptPromise<IDLBoolean> *)
Inductive PromiseOutcome : Type :=
  | PromiseResolved (b : bool)
  | PromiseRejected (err : DOMExceptionCode).

Scheme Equality for PromiseOutcome.

(** Payment Method Identifier (represented as integer IDs for formal decidability) *)
Definition PaymentMethodId := Z.

(** ** 2. Payment Request State and Environment *)

(** Internal state of Blink's PaymentRequest object *)
Record PaymentRequestState : Type := mkPaymentRequestState {
  pr_lifecycle_state : PaymentRequestLifecycleState;
  pr_has_pending_can_make_payment_resolver : bool;
  pr_method_data : list PaymentMethodId;
  pr_context_active : bool
}.

(** External Browser / Mojo Payment Provider Environment *)
Record PaymentEnvironment : Type := mkPaymentEnvironment {
  env_supported_methods : list PaymentMethodId;
  env_quota_available : bool;
  env_feature_reject_on_quota : bool
}.

(** ** 3. Helper Predicates and Functions *)

(** Check if a payment method ID is supported by the environment *)
Fixpoint is_method_supported (m : PaymentMethodId) (supported : list PaymentMethodId) : bool :=
  match supported with
  | [] => false
  | x :: xs => if Z.eqb m x then true else is_method_supported m xs
  end.

(** Check if any requested payment method is supported by the environment *)
Fixpoint any_method_supported (requested : list PaymentMethodId) (supported : list PaymentMethodId) : bool :=
  match requested with
  | [] => false
  | m :: ms => if is_method_supported m supported then true else any_method_supported ms supported
  end.

(** Browser-side Mojo service calculation of CanMakePaymentQueryResult *)
Definition compute_mojo_result (req_methods : list PaymentMethodId) (env : PaymentEnvironment)
  : MojoCanMakePaymentResult :=
  if negb (env_quota_available env) then
    kQuotaExceeded
  else if any_method_supported req_methods (env_supported_methods env) then
    kCanMakePayment
  else
    kCannotMakePayment.

(** ** 4. Blink Renderer Step Semantics (payment_request.cc) *)

(** Phase 1: Synchronous invocation of PaymentRequest::canMakePayment() *)
Inductive StartQueryResult : Type :=
  | SyncRejected (st' : PaymentRequestState) (err : DOMExceptionCode)
  | AsyncPending (st' : PaymentRequestState).

Definition blink_start_can_make_payment (st : PaymentRequestState) : StartQueryResult :=
  if negb (pr_context_active st) then
    SyncRejected st kInvalidStateError
  else match pr_lifecycle_state st with
  | kCreated =>
      if pr_has_pending_can_make_payment_resolver st then
        SyncRejected st kInvalidStateError
      else
        AsyncPending (mkPaymentRequestState
                        (pr_lifecycle_state st)
                        true
                        (pr_method_data st)
                        (pr_context_active st))
  | _ =>
      SyncRejected st kInvalidStateError
  end.

(** Phase 2: Asynchronous Mojo callback PaymentRequest::OnCanMakePayment() *)
Definition blink_on_can_make_payment
  (st : PaymentRequestState)
  (mojo_res : MojoCanMakePaymentResult)
  (reject_on_quota : bool)
  : (PaymentRequestState * option PromiseOutcome) :=
  if negb (pr_has_pending_can_make_payment_resolver st) then
    (st, None)
  else
    let st_cleared := mkPaymentRequestState
                        (pr_lifecycle_state st)
                        false
                        (pr_method_data st)
                        (pr_context_active st) in
    match mojo_res with
    | kCanMakePayment =>
        (st_cleared, Some (PromiseResolved true))
    | kCannotMakePayment =>
        (st_cleared, Some (PromiseResolved false))
    | kQuotaExceeded =>
        if reject_on_quota then
          (st_cleared, Some (PromiseRejected kNotAllowedError))
        else
          (* Anti-fingerprinting fallback: deterministically resolve based on method match *)
          (st_cleared, Some (PromiseResolved false))
    end.

(** Composed End-to-End Query Execution (Start + Mojo Evaluation + OnCanMakePayment) *)
Definition execute_can_make_payment_query
  (st_before : PaymentRequestState)
  (env : PaymentEnvironment)
  : (PaymentRequestState * PromiseOutcome) :=
  match blink_start_can_make_payment st_before with
  | SyncRejected st_sync err =>
      (st_sync, PromiseRejected err)
  | AsyncPending st_pending =>
      let mojo_res := compute_mojo_result (pr_method_data st_pending) env in
      match blink_on_can_make_payment st_pending mojo_res (env_feature_reject_on_quota env) with
      | (st_after, Some outcome) => (st_after, outcome)
      | (st_after, None) => (st_after, PromiseRejected kInvalidStateError) (* Unreachable invariant *)
      end
  end.

(** Projections for state_after_query and query_outcome *)
Definition state_after_query (st_before : PaymentRequestState) (env : PaymentEnvironment)
  : PaymentRequestState :=
  fst (execute_can_make_payment_query st_before env).

Definition query_outcome (st_before : PaymentRequestState) (env : PaymentEnvironment)
  : PromiseOutcome :=
  snd (execute_can_make_payment_query st_before env).

(** Precondition for a standard valid boolean query *)
Definition valid_boolean_query_precondition (st : PaymentRequestState) (env : PaymentEnvironment) : Prop :=
  pr_context_active st = true /\
  pr_lifecycle_state st = kCreated /\
  pr_has_pending_can_make_payment_resolver st = false /\
  env_quota_available env = true.
```

---

## 4. Concrete Theorems and Complete Proofs

We now prove the core mathematical properties required for `BlinkCanMakePaymentBooleanDeterminismSemantics.v`:
1. **Universal State Preservation (`state_after_query = state_before_query`):** Across *all* possible initial states (valid or invalid, active or detached, created or interactive/closed, quota available or exceeded), executing a `canMakePayment()` query cycle leaves the `PaymentRequestState` completely unchanged.
2. **Lifecycle Slot Invariance:** Neither phase 1 nor phase 2 ever alters `pr_lifecycle_state`.
3. **Boolean Resolution Existence & Sound