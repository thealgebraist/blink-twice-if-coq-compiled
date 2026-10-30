# Formal Verification Report: Web Bluetooth GATT Connection State Automaton Semantics

**Agent**: Formal Verification Agent 610 (Web Hardware & Peripheral Platform APIs)  
**Topic**: Web Bluetooth GATT Connection State Automaton Semantics  
**Chromium Source**: `third_party/blink/renderer/modules/bluetooth/bluetooth_device.cc`, `third_party/blink/renderer/modules/bluetooth/bluetooth_remote_gatt_server.cc`  
**Specification**: W3C Web Bluetooth Draft Community Group Report §4.2 (`BluetoothRemoteGATTServer`)  
**Formal Theory Target**: `BlinkWebBluetoothGATTConnectionStateSemantics.v`  
**Mathematical Property**: Valid transition topology and invariant preservation across the lifecycle automaton: $\text{Disconnected} \to \text{Connecting} \to \text{Connected} \to \text{Disconnecting} \to \text{Disconnected}$, including asynchronous abort/error short-circuits and idempotent calls.

---

## 1. Normative Specification Requirements

### 1.1 W3C Web Bluetooth Specification (§4.2 `BluetoothRemoteGATTServer`)
The W3C Web Bluetooth specification defines the `BluetoothRemoteGATTServer` interface, which represents a GATT Server on a remote device. The primary state exposed to script is the boolean attribute `connected` (`[[connected]]` internal slot). However, the underlying asynchronous algorithms (`connect()` and `disconnect()`) combined with the Active Algorithms list (`[[activeAlgorithms]]`) induce a 4-state extended deterministic finite automaton (DFA) when accounting for in-flight Mojo IPC requests to the browser process.

#### Normative Algorithms:
1. **`connect()` Method**:
   * **Step 1**: If `this.device` is not allowed to access GATT, reject with `SecurityError`.
   * **Step 2**: Return a new `Promise` $P$. Run the following steps in parallel:
   * **Step 3**: If `this.connected` is `true`, resolve $P$ with `this` and abort these steps (Idempotency in `Connected` state).
   * **Step 4**: Add the connection algorithm to `this.[[activeAlgorithms]]` (Transition to `Connecting`).
   * **Step 5**: Attempt to establish an OS-level GATT connection to the remote device.
   * **Step 6**: If `connect()` was aborted by an explicit `disconnect()` call while in-flight (i.e., removed from `[[activeAlgorithms]]`), reject $P$ with `NetworkError` and ensure state is `Disconnected`.
   * **Step 7**: If the OS connection fails, remove from `[[activeAlgorithms]]`, set `this.connected` to `false`, and reject $P$ with `NetworkError` (Transition `Connecting` $\to$ `Disconnected`).
   * **Step 8**: Upon success, remove from `[[activeAlgorithms]]`, set `this.connected` to `true`, and resolve $P$ with `this` (Transition `Connecting` $\to$ `Connected`).

2. **`disconnect()` Method**:
   * **Step 1**: For each algorithm in `this.[[activeAlgorithms]]`, abort the algorithm and cause its promise to reject with `NetworkError`. Clear `this.[[activeAlgorithms]]`.
   * **Step 2**: If `this.connected` is `false`, abort these steps (Idempotency in `Disconnected`, or cancellation in `Connecting`).
   * **Step 3**: Clean up active GATT objects, set `this.connected` to `false`, and notify the OS to drop the Bluetooth connection (`Connected` $\to$ `Disconnecting` $\to$ `Disconnected`).

3. **Garbage Collection & Context Destruction (`gattserverdisconnected` Event)**:
   * When the remote peripheral spontaneously drops the link or the `ExecutionContext` is destroyed, any pending `[[activeAlgorithms]]` are aborted, `this.connected` is set to `false`, and the `gattserverdisconnected` event is queued.

### 1.2 Cross-API Hardware Alignment (WebUSB, WebHID, Web Serial)
The state machine in Web Bluetooth is isomorphic to the peripheral lifecycle automata in sibling W3C/WHATWG hardware specifications:
* **WebUSB (`USBDevice.open()` / `close()`)**: Tracks `opened` boolean alongside in-flight Mojo promises, prohibiting concurrent close/transfer collisions.
* **WebHID (`HIDDevice.open()` / `close()`)**: Enforces strict transitions where `open()` rejects with `InvalidStateError` if already opening or open, and `close()` transitions through a closing state.
* **Web Serial (`SerialPort.open()` / `close()`)**: Explicit 4-state machine (`closed`, `opening`, `opened`, `closing`) governing readable/writable stream locks and hardware port handles.

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, the GATT connection state machine is split across `BluetoothDevice` (`third_party/blink/renderer/modules/bluetooth/bluetooth_device.cc`) and `BluetoothRemoteGATTServer` (`third_party/blink/renderer/modules/bluetooth/bluetooth_remote_gatt_server.cc`).

### 2.1 Architectural Split (`bluetooth_device.cc` & `bluetooth_remote_gatt_server.cc`)
* `BluetoothDevice` owns the `Member<BluetoothRemoteGATTServer> gatt_` instance and receives disconnections from the browser process via the Mojo interface `mojom::blink::WebBluetoothDevice`.
* When the OS Bluetooth stack detects a link loss, the browser invokes `BluetoothDevice::DisconnectGATTIfConnected()` or triggers the Mojo connection error handler, which delegates to `gatt_->SetConnected(false)` and dispatches `Event::CreateBubble(event_type_names::kGattserverdisconnected)`.
* `BluetoothRemoteGATTServer` maintains:
  * `bool connected_`: Represents the W3C `[[connected]]` slot (Initialized to `false`).
  * `HeapHashSet<Member<ScriptPromiseResolver>> active_algorithms_`: Tracks in-flight `connect()` and GATT operation promises.

### 2.2 Implicit & Explicit State Representation in Blink
While Blink stores `bool connected_` and `active_algorithms_`, the system state $S$ at the Mojo boundary is a 4-state automaton:
1. **`Disconnected` ($S = 0$)**: `connected_ == false` and no active `Connect` callback is awaiting a Mojo response, nor is a `RemoteServerDisconnect` IPC flushing.
2. **`Connecting` ($S = 1$)**: `connected_ == false`, `BluetoothRemoteGATTServer::connect()` has been invoked, a `ScriptPromiseResolver` is registered in `active_algorithms_`, and `service->RemoteServerConnect(...)` is in-flight over Mojo.
3. **`Connected` ($S = 2$)**: `BluetoothRemoteGATTServer::ConnectCallback` received `mojom::blink::WebBluetoothResult::SUCCESS`, removed the resolver from `active_algorithms_`, and executed `SetConnected(true)`.
4. **`Disconnecting` ($S = 3$)**: `BluetoothRemoteGATTServer::disconnect()` (or context teardown in `bluetooth_device.cc`) is invoked while `connected_ == true`. Blink executes `CleanupDisconnectedDeviceAndFireEvent()`, clears `active_algorithms_`, sets `connected_ = false`, and issues the asynchronous Mojo call `service->RemoteServerDisconnect(device_->GetBluetoothDevice()->id)` to release the browser-side `BluetoothGattConnection` handle. Until the browser process processes this IPC and releases the OS link handle, the composite system (Blink + Browser Mojo channel) is in the `Disconnecting` state, after which it settles in `Disconnected`.

### 2.3 Critical Implementation Invariants
* **Invariant 1 (Exposed Flag Consistency)**: The WebIDL attribute `gatt.connected` evaluates to `true` if and only if the automaton is in the exact `Connected` state. During `Disconnected`, `Connecting`, and `Disconnecting`, the Web-exposed `connected` boolean must be `false`.
* **Invariant 2 (Active Algorithms Isolation)**: `active_algorithms_` can only be non-empty during `Connecting` (holding the connection resolver) or `Connected` (holding characteristic/descriptor read/write resolvers). Entering `Disconnecting` or `Disconnected` strictly clears `active_algorithms_` (`active_algorithms_.clear()`), preventing dangling `ScriptPromiseResolver` leaks in V8.
* **Invariant 3 (Transition Validity)**: The canonical lifecycle follows `Disconnected -> Connecting -> Connected -> Disconnecting -> Disconnected`. Direct transitions such as `Disconnected -> Connected` (bypassing `Connecting`), `Connecting -> Disconnecting` (without either connecting first or aborting directly to `Disconnected`), or `Disconnecting -> Connected` are strictly unreachable.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the complete, self-contained formalization of the `BlinkWebBluetoothGATTConnectionStateSemantics.v` module. It encodes the states, events, transition relation, runnable step function, and Blink hardware invariants.

```coq
(** * BlinkWebBluetoothGATTConnectionStateSemantics.v
    Formal Verification of Web Bluetooth GATT Connection State Automaton
    Chromium Source: third_party/blink/renderer/modules/bluetooth/bluetooth_device.cc
    Specification: W3C Web Bluetooth §4.2 GATTServer connect/disconnect state machine *)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Automaton State & Event Definitions *)

(** The 4 canonical states of the GATT Connection Automaton across Blink and Mojo IPC. *)
Inductive GATTState : Type :=
  | Disconnected  : GATTState
  | Connecting    : GATTState
  | Connected     : GATTState
  | Disconnecting : GATTState.

(** Decidable equality for GATTState. *)
Definition gatt_state_eqb (s1 s2 : GATTState) : bool :=
  match s1, s2 with
  | Disconnected, Disconnected   => true
  | Connecting, Connecting       => true
  | Connected, Connected         => true
  | Disconnecting, Disconnecting => true
  | _, _                         => false
  end.

Lemma gatt_state_eqb_eq : forall s1 s2 : GATTState,
  gatt_state_eqb s1 s2 = true <-> s1 = s2.
Proof.
  intros s1 s2; destruct s1, s2; simpl; split; intro H; try reflexivity; try discriminate.
Qed.

(** Events driving the state machine from JavaScript API calls, Mojo IPC responses,
    and OS-level spontaneous link losses routed through bluetooth_device.cc. *)
Inductive GATTEvent : Type :=
  | EvRequestConnect        : GATTEvent (* JS calls device.gatt.connect() *)
  | EvMojoConnectSuccess    : GATTEvent (* Mojo ConnectCallback returns SUCCESS *)
  | EvMojoConnectFailed     : GATTEvent (* Mojo ConnectCallback returns Error *)
  | EvRequestDisconnect     : GATTEvent (* JS calls device.gatt.disconnect() *)
  | EvMojoDisconnectAck     : GATTEvent (* Browser completes RemoteServerDisconnect *)
  | EvSpontaneousLinkLoss   : GATTEvent (* OS drops link -> bluetooth_device.cc fires event *).

(** ** 2. Blink Concrete State Structure *)

(** Models the concrete C++ fields in BluetoothDevice and BluetoothRemoteGATTServer. *)
Record BlinkGATTServerModel : Type := mkBlinkGATT {
  automaton_state    : GATTState;
  js_connected_flag  : bool;  (* BluetoothRemoteGATTServer::connected_ *)
  active_algos_count : Z;     (* active_algorithms_.size() *)
  mojo_ipc_inflight  : bool   (* Pending Mojo Connect or Disconnect IPC *)
}.

(** Initial state when BluetoothDevice constructs BluetoothRemoteGATTServer. *)
Definition initial_blink_gatt : BlinkGATTServerModel :=
  mkBlinkGATT Disconnected false 0 false.

(** ** 3. State Transition Function *)

(** Pure state transition function over GATTState. *)
Definition next_gatt_state (s : GATTState) (ev : GATTEvent) : GATTState :=
  match s, ev with
  (* From Disconnected *)
  | Disconnected, EvRequestConnect      => Connecting
  | Disconnected, _                     => Disconnected

  (* From Connecting *)
  | Connecting, EvMojoConnectSuccess    => Connected
  | Connecting, EvMojoConnectFailed     => Disconnected
  | Connecting, EvRequestDisconnect     => Disconnected (* Aborts in-flight connect *)
  | Connecting, EvSpontaneousLinkLoss   => Disconnected
  | Connecting, _                       => Connecting

  (* From Connected *)
  | Connected, EvRequestDisconnect      => Disconnecting
  | Connected, EvSpontaneousLinkLoss    => Disconnected
  | Connected, _                        => Connected

  (* From Disconnecting *)
  | Disconnecting, EvMojoDisconnectAck  => Disconnected
  | Disconnecting, EvSpontaneousLinkLoss=> Disconnected
  | Disconnecting, _                    => Disconnecting
  end.

(** Concrete step function updating the Blink C++ model fields in lockstep. *)
Definition step_blink_gatt (m : BlinkGATTServerModel) (ev : GATTEvent) : BlinkGATTServerModel :=
  match automaton_state m, ev with
  | Disconnected, EvRequestConnect =>
      mkBlinkGATT Connecting false 1 true
  | Disconnected, _ =>
      m

  | Connecting, EvMojoConnectSuccess =>
      mkBlinkGATT Connected true 0 false
  | Connecting, EvMojoConnectFailed =>
      mkBlinkGATT Disconnected false 0 false
  | Connecting, EvRequestDisconnect =>
      mkBlinkGATT Disconnected false 0 false
  | Connecting, EvSpontaneousLinkLoss =>
      mkBlinkGATT Disconnected false 0 false
  | Connecting, _ =>
      m

  | Connected, EvRequestDisconnect =>
      mkBlinkGATT Disconnecting false 0 true
  | Connected, EvSpontaneousLinkLoss =>
      mkBlinkGATT Disconnected false 0 false
  | Connected, _ =>
      m

  | Disconnecting, EvMojoDisconnectAck =>
      mkBlinkGATT Disconnected false 0 false
  | Disconnecting, EvSpontaneousLinkLoss =>
      mkBlinkGATT Disconnected false 0 false
  | Disconnecting, _ =>
      m
  end.

(** Multi-step execution trace over a list of events. *)
Fixpoint run_gatt_trace (m : BlinkGATTServerModel) (trace : list GATTEvent) : BlinkGATTServerModel :=
  match trace with
  | [] => m
  | ev :: rest => run_gatt_trace (step_blink_gatt m ev) rest
  end.

(** ** 4. Formal Predicates and Invariants *)

(** Predicate defining the valid structural single-step transitions in the automaton.
    Contains the primary cycle:
      Disconnected -> Connecting -> Connected -> Disconnecting -> Disconnected
    plus self-loops (idempotency) and abort/error edges to Disconnected. *)
Definition valid_gatt_transition (s1 s2 : GATTState) : Prop :=
  (s1 = s2) \/
  (s1 = Disconnected  /\ s2 = Connecting) \/
  (s1 = Connecting    /\ s2 = Connected) \/
  (s1 = Connected     /\ s2 = Disconnecting) \/
  (s1 = Disconnecting /\ s2 = Disconnected) \/
  (* Abort / Link-loss recovery edges directly to Disconnected *)
  (s1 = Connecting    /\ s2 = Disconnected) \/
  (s1 = Connected     /\ s2 = Disconnected).

(** Numeric progress rank