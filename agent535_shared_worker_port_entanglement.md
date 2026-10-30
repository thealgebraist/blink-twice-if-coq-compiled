# Formal Verification Report: Blink SharedWorker MessagePort Bidirectional Entanglement

**Formal Theory Target**: `BlinkSharedWorkerPortEntanglementSemantics.v`  
**Chromium Source**: `third_party/blink/renderer/core/workers/shared_worker.cc`, `third_party/blink/renderer/core/messaging/message_channel.cc`, `third_party/blink/renderer/core/messaging/message_port.cc`, `third_party/blink/common/messaging/message_port_channel.cc`  
**Normative Specification**: WHATWG HTML Standard §10.3 (Shared workers and the `SharedWorker` interface) & §9.4 (Channel messaging)  
**Mathematical Property**: $\forall p_1, p_2 \in \mathcal{P},\; \text{entangle}(p_1) = p_2 \iff \text{entangle}(p_2) = p_1$; bidirectional entanglement is a strict irreflexive involution on the domain of active ports.

---

## 1. Normative WHATWG Specification Requirements

Under the WHATWG HTML Standard, `SharedWorker` communication relies on the underlying `MessagePort` entanglement primitives defined in **§9.4 (Channel messaging)** and instantiated during worker creation in **§10.3.2 (The `SharedWorker` interface)**.

### 1.1 Port Entanglement (§9.4.3 Message ports)
Each `MessagePort` object can be entangled with another (a symmetric relationship). When the specification dictates to **entangle** two `MessagePort` objects $p_1$ and $p_2$:
1. If one of the ports is already entangled, first disentangle it and the port that it was entangled with.
2. Associate $p_1$ and $p_2$ so that they form the two parts of a new channel (bijective pairing). If $p_1$ and $p_2$ are the same object, this step is a violation of platform invariants (irreflexivity).

### 1.2 SharedWorker Construction and Port Creation (§10.3.2)
When the `new SharedWorker(scriptURL, options)` constructor is invoked:
1. **Step 5**: Create a new `MessagePort` object whose owner is the incumbent settings object, let this be `outside port` ($p_{\text{outside}}$).
2. **Step 6**: Associate `outside port` with the newly constructed `SharedWorker` instance's `port` attribute.
3. **Step 10.4 (Inside Parallel Execution / Worker Manager)**: Create a new `MessagePort` object `inside port` ($p_{\text{inside}}$) inside the `SharedWorkerGlobalScope` (or prepare its descriptor for transfer before the global scope initializes).
4. **Step 10.5**: **Entangle** `outside port` and `inside port`:
   $$\text{entangle}(p_{\text{outside}}) = p_{\text{inside}} \quad \land \quad \text{entangle}(p_{\text{inside}}) = p_{\text{outside}}$$
5. **Step 10.6**: Queue a task to fire a `connect` event at the `SharedWorkerGlobalScope` object, with `ports` initialized to a frozen array containing `[inside port]` and `source` initialized to `inside port`.

### 1.3 Formal Invariants Required by the Standard
- **Symmetry (Involution)**: If port $a$ is entangled with port $b$, then port $b$ is simultaneously entangled with port $a$. Applying the entanglement lookup operator twice yields the identity on the active port domain: $E(E(p)) = p$.
- **Irreflexivity**: No port $p$ may ever be entangled with itself: $E(p) \neq p$.
- **Exclusivity (Injectivity)**: A port may be entangled with at most one counterparty at any discrete execution step. Entangling an already-entangled port atomically severs the prior entanglement for both former partners.
- **Disentanglement Atomicity**: Closing or transferring a port disentangles it from its counterpart, leaving the counterpart unentangled (or re-entangled with a newly transferred remote endpoint descriptor).

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, the `SharedWorker` constructor and its cross-process / cross-thread `MessagePort` entanglement are implemented in `third_party/blink/renderer/core/workers/shared_worker.cc` and backed by Mojo message pipes encapsulated within `blink::MessagePortDescriptor` and `blink::MessagePortChannel`.

### 2.1 Execution Flow in `shared_worker.cc`
```cpp
// third_party/blink/renderer/core/workers/shared_worker.cc

SharedWorker* SharedWorker::Create(ExecutionContext* context,
                                   const String& url,
                                   const V8UnionStringOrSharedWorkerOptions* name_or_options,
                                   ExceptionState& exception_state) {
  // ... [Security & Context Validation] ...

  SharedWorker* worker = MakeGarbageCollected<SharedWorker>(context);

  // 1. Create a bidirectional Mojo MessagePipe via MessageChannel.
  auto* channel = MakeGarbageCollected<MessageChannel>(context);
  
  // 2. Bind port1 as the "outside port" exposed on SharedWorker.port.
  worker->port_ = channel->port1();
  
  // 3. Disentangle port2 from the local blink::MessagePort wrapper to extract
  //    its underlying Mojo pipe handle (MessagePortDescriptor) for IPC transfer.
  MessagePortChannel remote_port = channel->port2()->Disentangle();

  // 4. Connect to the browser/worker host via SharedWorkerConnector, transferring
  //    ownership of the remote_port descriptor to become the "inside port".
  SharedWorkerClientHolder::From(*window)->Connect(
      worker, std::move(remote_port), script_url, std::move(blob_url_token),
      options, context->UkmSourceId());

  return worker;
}
```

### 2.2 Underlying Entanglement Mechanics (`MessageChannel` & `MessagePortDescriptorPair`)
When `MakeGarbageCollected<MessageChannel>(context)` executes:
1. It instantiates a `blink::MessagePortDescriptorPair`, which invokes `mojo::CreateMessagePipe()` to allocate two entangled Mojo message pipe handles (`handle0`, `handle1`).
2. Inside `MessagePortDescriptorPair::MessagePortDescriptorPair()`, `handle0` and `handle1` are bound as symmetric peers at the kernel/Mojo core layer.
3. `channel->port1()->Entangle( pipe.TakePort0() )` and `channel->port2()->Entangle( pipe.TakePort1() )` bind the Blink GC-managed `MessagePort` instances to the respective descriptors.

### 2.3 Invariants Preserved Across `Disentangle()` and IPC `Connect()`
- **Logical vs. Physical Entanglement**: Although `channel->port2()->Disentangle()` detaches the local Blink C++ `MessagePort` shell (`port2`) on the main thread, the underlying `MessagePortDescriptor` (`remote_port`) retains the entangled Mojo pipe endpoint.
- **State Machine Conservation**: Let $\mathcal{P}$ represent the space of active `MessagePortDescriptor` endpoints (whether currently wrapped by a main-thread `blink::MessagePort`, in-flight over Mojo IPC inside `SharedWorkerConnector::Connect`, or wrapped by the worker-thread `blink::MessagePort` upon `SharedWorkerGlobalScope::OnConnect`). Throughout the entire lifecycle, the bidirectional pairing between `port1`'s descriptor ($p_1$) and `remote_port`'s descriptor ($p_2$) satisfies:
  $$\text{peer}(p_1) = p_2 \quad \land \quad \text{peer}(p_2) = p_1 \quad \land \quad p_1 \neq p_2$$
- **Garbage Collection & Mojo Lifecycle**: Oilpan (`Member<MessagePort> port_`) guarantees `port1` stays alive as long as the `SharedWorker` wrapper is reachable or has pending activity. If either endpoint calls `close()`, the Mojo pipe peer closure signal propagates asynchronously, transitioning both endpoints to the disentangled state.

---

## 3. Formal Specification in Rocq / Coq

We formalize the state space of `MessagePort` descriptors, channel allocation, bidirectional entanglement, disentanglement, and `SharedWorker` connection semantics in Rocq (Coq).

### 3.1 Domain Definitions and State Representation
- **Port Identifiers (`PortId`)**: Modeled as `Z` (arbitrary-precision integers representing unique descriptor IDs).
- **Entanglement Map (`EntangleMap`)**: Modeled as a total function `Z -> option Z` backed by an explicit finite association list `list (Z * Z)` to allow decidable boolean reflection and structural induction.
- **System State (`EngineState`)**: Tracks the next fresh port allocator ID (`next_id : Z`), the active entanglement relation (`links : list (Z * Z)`), and the registered `SharedWorker` instances (`workers : list (Z * Z)` mapping worker ID to its outside port ID).

---

## 4. Concrete Rocq / Coq Theory (`BlinkSharedWorkerPortEntanglementSemantics.v`)

Below is the complete, self-contained, and admitted-free Rocq formalization and verification of the `SharedWorker` `MessagePort` bidirectional entanglement semantics.

```coq
(** * BlinkSharedWorkerPortEntanglementSemantics.v
    Formal verification of Chromium Blink's SharedWorker MessagePort
    bidirectional entanglement invariants (HTML Standard §10.3 & §9.4).
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Core Types and Association List Lookup Primitives *)

Definition PortId := Z.
Definition WorkerId := Z.
Definition EntangleTable := list (PortId * PortId).

(** Lookup the entangled peer of port [p] in table [t]. *)
Fixpoint lookup_peer (p : PortId) (t : EntangleTable) : option PortId :=
  match t with
  | [] => None
  | (k, v) :: rest =>
      if Z.eqb p k then Some v else lookup_peer p rest
  end.

(** Remove any entry involving port [p] (either as source or target) to preserve
    clean disentanglement when re-entangling or closing ports. *)
Fixpoint remove_port (p : PortId) (t : EntangleTable) : EntangleTable :=
  match t with
  | [] => []
  | (k, v) :: rest =>
      if (Z.eqb p k) || (Z.eqb p v) then remove_port p rest
      else (k, v) :: remove_port p rest
  end.

(** Disentangle a port [p] and its former counterparty (if any). *)
Definition disentangle_port (p : PortId) (t : EntangleTable) : EntangleTable :=
  match lookup_peer p t with
  | None => remove_port p t
  | Some q => remove_port q (remove_port p t)
  end.

(** Entangle two distinct ports [p1] and [p2].
    Follows HTML Standard §9.4.3:
    1. If p1 or p2 are equal, operation is a no-op (irreflexivity guard).
    2. Disentangle both p1 and p2 from any existing partners.
    3. Insert symmetric bindings (p1 -> p2) and (p2 -> p1). *)
Definition entangle_ports (p1 p2 : PortId) (t : EntangleTable) : EntangleTable :=
  if Z.eqb p1 p2 then t
  else
    let t1 := disentangle_port p1 t in
    let t2 := disentangle_port p2 t1 in
    (p1, p2) :: (p2, p1) :: t2.

(** ** 2. Well-Formedness Predicates (Involution & Irreflexivity) *)

(** A table satisfies the Involution Property if every entangled port maps to a
    counterparty that maps directly back to the original port. *)
Definition is_involution (t : EntangleTable) : Prop :=
  forall p1 p2 : PortId,
    lookup_peer p1 t = Some p2 <-> lookup_peer p2 t = Some p1.

(** Functional formulation of involution: applying lookup twice yields the original port. *)
Definition involutive_step (t : EntangleTable) : Prop :=
  forall p1 p2 : PortId,
    lookup_peer p1 t = Some p2 -> lookup_peer p2 t = Some p1.

(** A table is irreflexive if no port is entangled with itself. *)
Definition is_irreflexive (t : EntangleTable) : Prop :=
  forall p : PortId, lookup_peer p t <> Some p.

(** Combined Structural Soundness Invariant for Blink MessagePort Entanglement. *)
Definition EntanglementSound (t : EntangleTable) : Prop :=
  involutive_step t /\ is_irreflexive t.

(** ** 3. Engine State & SharedWorker::Create Transition Semantics *)

Record EngineState := mkEngineState {
  next_port_id : PortId;
  next_worker_id : WorkerId;
  entanglements : EntangleTable;
  shared_workers : list (WorkerId * PortId * PortId) (* (worker, outside_port, inside_port) *)
}.

Definition init_engine_state : EngineState :=
  mkEngineState 1 1 [] [].

(** Models SharedWorker::Create in third_party/blink/renderer/core/workers/shared_worker.cc:
    1. Allocates outside_port (p_out = next_port_id) and inside_port (p_in = next_port_id + 1).
    2. Entangles p_out and p_in via MessageChannel.
    3. Transfers p_in to SharedWorkerConnector::Connect while retaining p_out on SharedWorker.port_. *)
Definition create_shared_worker (st : EngineState) : EngineState * WorkerId * PortId * PortId :=
  let p_out := next_port_id st in
  let p_in := p_out + 1 in
  let w_id := next_worker_id st in
  let new_table := entangle_ports p_out p_in (entanglements st) in
  let st' := mkEngineState
               (p_out + 2)
               (w_id + 1)
               new_table
               ((w_id, p_out, p_in) :: shared_workers st) in
  (st', w_id, p_out, p_in).

(** ** 4. Lemmas on Lookup and Removal *)

Lemma lookup_remove_same : forall (p : PortId) (t : EntangleTable),
  lookup_peer p (remove_port p t) = None.
Proof.
  intros p t. induction t as [| [k v] rest IH].
  - simpl. reflexivity.
  - simpl. destruct (Z.eqb p k) eqn:Heqk.
    + simpl. exact IH.
    + destruct (Z.eqb p v) eqn:Heqv.
      * simpl. exact IH.
      * simpl. rewrite Heqk. exact