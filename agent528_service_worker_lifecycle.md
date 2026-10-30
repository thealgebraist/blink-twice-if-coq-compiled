# Formal Analysis of Service Worker Registration Lifecycle States

**Author:** Formal Methods & Web Platform Networking Research Group  
**Target Artifact:** `BlinkServiceWorkerLifecycleStateSemantics.v`  
**Chromium Subsystem:** `content/browser/service_worker/service_worker_version.cc`  
**Specification Reference:** W3C Service Workers Specification §3.2 (ServiceWorkerState Enum & Update/Install/Activate Algorithms)  

---

## 1. Normative W3C/WHATWG Specification Requirements

In the W3C Service Workers specification (Nightly / CR), §3.2 defines the `ServiceWorker` interface and its associated `ServiceWorkerState` enumeration. Every service worker instance possesses an internal `[[State]]` slot whose value transitions strictly forward through a well-ordered finite domain.

### 1.1 The `ServiceWorkerState` Enumeration
Per §3.2, the normative state space $\Sigma_{SW}$ is defined as:
```webidl
enum ServiceWorkerState {
  "parsed",
  "installing",
  "installed",
  "activating",
  "activated",
  "redundant"
};
```

### 1.2 Normative State Transition Rules
The state machine governing a service worker's lifecycle is driven by four core specification algorithms: **Install**, **Activate**, **Update**, and **Update Worker State**.

1. **Initial State (`"parsed"`):** When a service worker script is successfully fetched and parsed during the *Soft Update* or *Register* algorithms, a new service worker structure is instantiated with its `[[State]]` initialized to `"parsed"`. Note that `"parsed"` is an internal/initial state before the `ServiceWorker` object is typically exposed as an `installing` worker on a `ServiceWorkerRegistration`, though the WebIDL enum explicitly includes it as the minimal state.
2. **Installation Phase (`"installing"` $\to$ `"installed"` | `"redundant"`):**
   - Upon entering the *Install* algorithm, *Update Worker State* is invoked with `"installing"`.
   - The `install` ExtendableEvent is dispatched to the worker's global scope (`ServiceWorkerGlobalScope`).
   - If any `waitUntil()` promise rejects, or an uncaught runtime script error occurs during evaluation, *Update Worker State* is invoked with `"redundant"`, aborting installation.
   - If all promises in the extendable event resolve, *Update Worker State* is invoked with `"installed"` (making it the *waiting* worker on the registration).
3. **Activation Phase (`"installed"` $\to$ `"activating"` $\to$ `"activated"` | `"redundant"`):**
   - If a waiting (`"installed"`) worker is replaced by a newer installing worker before it can activate, the older waiting worker transitions directly from `"installed"` to `"redundant"`.
   - When the *Activate* algorithm triggers (either immediately via `skipWaiting()` or once no clients are controlled by the prior active worker), *Update Worker State* is invoked with `"activating"`.
   - If activation fails or is superseded under catastrophic client-teardown conditions (or worker replacement), it transitions to `"redundant"`. Otherwise, upon resolution of the `activate` event's `waitUntil()` promises, *Update Worker State* is invoked with `"activated"`.
4. **Termination / Replacement Phase (`"activated"` $\to$ `"redundant"`):**
   - When a registration is unregistered or a newer waiting worker invokes `skipWaiting()` / takes over control, the currently `"activated"` worker has *Update Worker State* invoked with `"redundant"`.

### 1.3 The Monotonicity Requirement
Across all normative invocations of the **Update Worker State** algorithm in the specification, given an existing state $s_{old}$ and a target state $s_{new}$, if we define the canonical rank mapping $\rho: \Sigma_{SW} \to \mathbb{N}$:
$$\rho(\text{parsed}) = 0 < \rho(\text{installing}) = 1 < \rho(\text{installed}) = 2 < \rho(\text{activating}) = 3 < \rho(\text{activated}) = 4 < \rho(\text{redundant}) = 5$$
Then every valid transition $s_{old} \to s_{new}$ strictly satisfies $\rho(s_{old}) < \rho(s_{new})$. Furthermore, `"redundant"` ($\rho = 5$) is an absorbing terminal sink state: there exist no outgoing transitions from `"redundant"`.

---

## 2. Chromium Blink / Content Implementation Details & Invariants

In Chromium's multi-process architecture, the normative lifecycle state of a Service Worker is managed in the browser process by `content::ServiceWorkerVersion` (`content/browser/service_worker/service_worker_version.h` and `.cc`), and mirrored to the renderer process (`blink::WebServiceWorkerObjectInfo` / `blink::ServiceWorker`).

### 2.1 `ServiceWorkerVersion::Status` Mapping
In `content/browser/service_worker/service_worker_version.h`, the internal C++ enumeration `ServiceWorkerVersion::Status` maps directly to the W3C states:

| `ServiceWorkerVersion::Status` (C++) | W3C `ServiceWorkerState` | Rank ($\rho$) | Description in Chromium |
| :--- | :--- | :---: | :--- |
| `Status::NEW` | `"parsed"` | $0$ | Initial version state upon instantiation (`parsed` after script fetch). |
| `Status::INSTALLING` | `"installing"` | $1$ | Dispatched `InstallEvent` via Mojo to Blink `ServiceWorkerGlobalScope`. |
| `Status::INSTALLED` | `"installed"` | $2$ | `InstallEvent` finished; assigned to `registration->waiting_version()`. |
| `Status::ACTIVATING` | `"activating"` | $3$ | Promoted to `active_version()`; dispatched `ActivateEvent`. |
| `Status::ACTIVATED` | `"activated"` | $4$ | `ActivateEvent` finished; intercepts `FetchEvent`s via `ServiceWorkerSubresourceLoader`. |
| `Status::REDUNDANT` | `"redundant"` | $5$ | Discarded, failed, or replaced; Mojo pipes closed and storage doomed. |

### 2.2 State Transition Enforcement in `service_worker_version.cc`
The method `ServiceWorkerVersion::SetStatus(Status status)` in `content/browser/service_worker/service_worker_version.cc` is the single chokepoint mutating the `status_` member field:

```cpp
void ServiceWorkerVersion::SetStatus(Status status) {
  if (status_ == status)
    return;

  TRACE_EVENT2("ServiceWorker", "ServiceWorkerVersion::SetStatus", "Script URL",
               script_url_.spec(), "New Status", VersionStatusToString(status));

  // Enforce strict progression and valid state machine edges.
  switch (status) {
    case NEW:
      NOTREACHED(); // Cannot transition back to NEW (parsed).
    case INSTALLING:
      DCHECK_EQ(NEW, status_);
      break;
    case INSTALLED:
      DCHECK_EQ(INSTALLING, status_);
      break;
    case ACTIVATING:
      DCHECK_EQ(INSTALLED, status_);
      break;
    case ACTIVATED:
      DCHECK_EQ(ACTIVATING, status_);
      break;
    case REDUNDANT:
      DCHECK_NE(REDUNDANT, status_);
      break;
  }

  status_ = status;
  // ... [Observer notifications, Mojo IPC updates, and callback cleanups]
}
```

### 2.3 Subsystem Invariants in `service_worker_version.cc`
1. **Strict Rank Monotonicity (`DCHECK` Guards):** The `switch` statement inside `SetStatus` enforces that:
   - `NEW` ($0$) has in-degree $0$ (unreachable via `SetStatus`).
   - `INSTALLING` ($1$), `INSTALLED` ($2$), `ACTIVATING` ($3$), and `ACTIVATED` ($4$) require the exact predecessor state $\rho(s_{old}) = \rho(s_{new}) - 1$.
   - `REDUNDANT` ($5$) can be reached from any state $s_{old} \neq \text{REDUNDANT}$ (in practice, from `NEW` on script load error, `INSTALLING` on install failure, `INSTALLED` on waiting replacement, `ACTIVATING` on fatal error, or `ACTIVATED` on unregistration/replacement).
2. **Idempotence Guard:** If `status_ == status`, `SetStatus` returns early without firing redundant observer notifications or queuing duplicate IPC messages to Blink renderer processes.
3. **In-Flight Fetch & Stream Teardown on `REDUNDANT`:** When transitioning to `Status::REDUNDANT`, `ServiceWorkerVersion::SetStatus` clears pending controllee callbacks, detaches `ServiceWorkerSubresourceLoaderFactory` instances, and triggers doom markers in the `ServiceWorkerRegistry` database so that body streams (`mojo::ScopedDataPipeConsumerHandle`) and Cache Storage (`blink::mojom::CacheStorage`) locks do not leak or serve stale responses from dead versions.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of the Service Worker lifecycle state machine, its rank function, transition relations, and multi-step execution traces for `BlinkServiceWorkerLifecycleStateSemantics.v`.

```coq
(** * BlinkServiceWorkerLifecycleStateSemantics.v
    Formal Semantics of W3C Service Worker Registration Lifecycle States
    and Chromium's ServiceWorkerVersion::SetStatus State Machine. *)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micromechanics.Lia.
From Coq Require Import Lists.List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. State Space Definition (W3C Service Workers §3.2) *)

Inductive SWState : Type :=
  | Parsed      (* Status::NEW        - rank 0 *)
  | Installing  (* Status::INSTALLING - rank 1 *)
  | Installed   (* Status::INSTALLED  - rank 2 *)
  | Activating  (* Status::ACTIVATING - rank 3 *)
  | Activated   (* Status::ACTIVATED  - rank 4 *)
  | Redundant.  (* Status::REDUNDANT  - rank 5 *)

(** Decidable equality on SWState *)
Definition sw_state_eqb (s1 s2 : SWState) : bool :=
  match s1, s2 with
  | Parsed, Parsed => true
  | Installing, Installing => true
  | Installed, Installed => true
  | Activating, Activating => true
  | Activated, Activated => true
  | Redundant, Redundant => true
  | _, _ => false
  end.

Lemma sw_state_eqb_eq : forall s1 s2 : SWState,
  sw_state_eqb s1 s2 = true <-> s1 = s2.
Proof.
  intros s1 s2; destruct s1, s2; simpl; split; intro H; try reflexivity; try discriminate.
Qed.

Lemma sw_state_eq_dec : forall s1 s2 : SWState, {s1 = s2} + {s1 <> s2}.
Proof.
  decide equality.
Defined.

(** ** 2. Monotonic Rank Function *)

Definition state_rank (s : SWState) : Z :=
  match s with
  | Parsed     => 0
  | Installing => 1
  | Installed  => 2
  | Activating => 3
  | Activated  => 4
  | Redundant  => 5
  end.

(** ** 3. Normative & Chromium Transition Relations *)

(** Strict single-step transition relation modeling the valid state transitions
    allowed by ServiceWorkerVersion::SetStatus (when status_ != status). *)
Inductive valid_transition : SWState -> SWState -> Prop :=
  | Trans_Parse_Install   : valid_transition Parsed Installing
  | Trans_Install_Success : valid_transition Installing Installed
  | Trans_Wait_Activate   : valid_transition Installed Activating
  | Trans_Activate_Done   : valid_transition Activating Activated
  | Trans_Abort_Parsed    : valid_transition Parsed Redundant
  | Trans_Abort_Install   : valid_transition Installing Redundant
  | Trans_Replace_Waiting : valid_transition Installed Redundant
  | Trans_Abort_Activate  : valid_transition Activating Redundant
  | Trans_Replace_Active  : valid_transition Activated Redundant.

(** Executable boolean predicate matching Chromium's DCHECK logic in SetStatus *)
Definition can_transition_b (s_old s_new : SWState) : bool :=
  match s_new with
  | Parsed     => false
  | Installing => sw_state_eqb s_old Parsed
  | Installed  => sw_state_eqb s_old Installing
  | Activating => sw_state_eqb s_old Installed
  | Activated  => sw_state_eqb s_old Activating
  | Redundant  => negb (sw_state_eqb s_old Redundant)
  end.

(** Reflexive-transitive closure of valid_transition for multi-step traces *)
Inductive reachable_star : SWState -> SWState -> Prop :=
  | Reach_Refl : forall s, reachable_star s s
  | Reach_Step : forall s1 s2 s3,
      valid_transition s1 s2 ->
      reachable_star s2 s3 ->
      reachable_star s1 s3.

(** Model of ServiceWorkerVersion::SetStatus(Status status) which returns
    Some s_new if either s_old = s_new (idempotent early return) or
    can_transition_b s_old s_new = true, and None if NOTREACHED/DCHECK fails. *)
Definition set_status (s_old s_new : SWState) : option SWState :=
  if sw_state_eqb s_old s_new then
    Some s_old
  else if can_transition_b s_old s_new then
    Some s_new
  else
    None.

(** ** 4. Networking, Fetch, and Cache Subsystem Predicates *)

(** A Service Worker version may only intercept network FetchEvents
    (via ServiceWorkerSubresourceLoader) when in the Activated state. *)
Definition can_handle_fetch (s : SWState) : bool :=
  sw_state_eqb s Activated.

(** A Service Worker version may execute ExtendableEvents (Install/Activate)
    that populate CacheStorage or read network streams during Installing,
    Activating, or Activated states. *)
Definition is_active_execution_context (s : SWState) : bool :=
  match s with
  | Installing | Activating | Activated => true
  | Parsed | Installed | Redundant => false
  end.

(** A Service Worker version has released all controllee references and
    doomed unreferenced disk resources when Redundant. *)
Definition resources_doomed (s : SWState) : bool :=
  sw_state_eqb s Redundant.
```

---

## 4. Concrete Theorems and Complete Proofs

We now state and prove the core mathematical theorems verifying strict rank monotonicity, rank bounds, equivalence between the inductive specification and executable checker, terminal sink absorption, acyclicity, and networking/cache safety invariants. All proofs are complete with zero `Admitted` statements.

```coq
(** ** Theorem 1: Rank Bounds
    Every Service Worker state has a well-defined integer rank in [0, 5]. *)
Theorem state_rank_bounds : forall s : SWState,
  0 <=