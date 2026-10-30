# Formal Verification Report: Peripheral Device Disconnect Teardown and Stream Cancellation

**Agent**: Formal Verification Agent 624 (Web Hardware & Peripheral Platform APIs)  
**Target Theory**: `BlinkWebDeviceDisconnectCleanupSemantics.v`  
**Chromium Source**: `third_party/blink/renderer/modules/serial/serial_port.cc`  
**Specification**: W3C Web Serial API / WebUSB / WebHID  
**Mathematical Property**: $\forall s, \text{disconnect}(s) \implies \text{is\_open}(s') = \text{false} \land \text{active\_transfers}(s') = 0$

---

## 1. Normative Specification Requirements

Across the W3C Web Hardware APIs (Web Serial, WebUSB, WebHID, and Web Bluetooth), unexpected physical or logical disconnection of a peripheral device requires immediate, deterministic state teardown in the user agent to prevent dangling pointers, memory leaks, and stalled JavaScript promises/streams.

### 1.1. W3C Web Serial API
In the W3C Web Serial Specification (Section *Responding to device disconnection* & `SerialPort` lifecycle):
1. **State Transition**: When a serial port becomes disconnected from the host system while its `[[state]]` is `"opened"`, the user agent must immediately transition `[[state]]` to `"closed"` (or `"closing"` followed by synchronous stream cleanup before firing the `disconnect` event).
2. **ReadableStream Teardown**: If `[[readable]]` is not `null`, the user agent must error the `ReadableStream` with a `NetworkError` `DOMException` and set `[[readable]]` to `null`. Any pending read requests (`[[readRequests]]`) must be rejected.
3. **WritableStream Teardown**: If `[[writable]]` is not `null`, the user agent must error the `WritableStream` with a `NetworkError` `DOMException`, abort any in-flight write operations, and set `[[writable]]` to `null`.
4. **Mojo/IPC Pipe Closure**: Underlying OS handles and IPC data pipes must be closed prior to dispatching the `disconnect` event on the `Serial` or `SerialPort` instance.

### 1.2. W3C WebUSB & WebHID Equivalents
- **WebUSB**: When a USB device is unplugged, `USBDevice.[[opened]]` is set to `false`, all claimed interfaces are released (`[[claimed]] = false`), and all pending in-flight `transferIn`, `transferOut`, `isochronousTransferIn`, and `isochronousTransferOut` promises are rejected with `NetworkError`, reducing active transfers to `0`.
- **WebHID**: When a HID device is disconnected, `HIDDevice.opened` becomes `false`, and all pending `sendReport`, `sendFeatureReport`, and `receiveFeatureReport` operations are terminated.

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, `third_party/blink/renderer/modules/serial/serial_port.cc` implements the `SerialPort` interface and manages Mojo IPC pipes (`mojo::Remote<device::mojom::blink::SerialPort>`) alongside the underlying data streams (`SerialPortUnderlyingSource` and `SerialPortUnderlyingSink`).

### 2.1. Core State Representation in `SerialPort`
In `serial_port.h` / `serial_port.cc`, the open state and active transfers are governed by:
- `port_` (`HeapMojoRemote<device::mojom::blink::SerialPort>`): The active Mojo IPC connection to the Device Service. `port_.is_bound()` serves as the authoritative `is_open` indicator in Blink.
- `underlying_source_` (`Member<SerialPortUnderlyingSource>`): Manages the `ReadableStream` and active read data pipe (`mojo::ScopedDataPipeConsumerHandle`).
- `underlying_sink_` (`Member<SerialPortUnderlyingSink>`): Manages the `WritableStream` and active write data pipe (`mojo::ScopedDataPipeProducerHandle`).
- `open_resolver_` / `close_resolver_` (`Member<ScriptPromiseResolver>`): Tracks pending asynchronous lifecycle transitions.

### 2.2. Teardown Execution Path (`OnConnectionError` & `ContextDestroyed`)
When a physical device disconnects, the browser process closes the Mojo message pipe, triggering the connection error handler `SerialPort::OnConnectionError()` in `serial_port.cc`:

```cpp
void SerialPort::OnConnectionError() {
  closing_ = false;
  port_.reset();
  if (underlying_source_) {
    underlying_source_->SignalErrorOnClose(
        DOMException::Create("The device has been lost.", "NetworkError"));
  }
  if (underlying_sink_) {
    underlying_sink_->SignalErrorOnClose(
        DOMException::Create("The device has been lost.", "NetworkError"));
  }
  if (open_resolver_) {
    open_resolver_->Reject(
        DOMException::Create("The device has been lost.", "NetworkError"));
    open_resolver_ = nullptr;
  }
  if (close_resolver_) {
    close_resolver_->Resolve();
    close_resolver_ = nullptr;
  }
}
```

When `SignalErrorOnClose()` is invoked on the source and sink, they immediately tear down their respective Mojo `DataPipe` handles and clear their references back to `SerialPort` via `UnderlyingSourceClosed()` and `UnderlyingSinkClosed()`, setting `readable_ = nullptr`, `writable_ = nullptr`, `underlying_source_ = nullptr`, and `underlying_sink_ = nullptr`.

### 2.3. Implementation Invariants
1. **Open-Binding Equivalence**: The port is considered open if and only if `port_.is_bound()` is true and `!closing_`.
2. **Transfer Containment**: Active read transfers (`active_reads > 0`) can only exist if `underlying_source_ != nullptr` and `port_.is_bound()`. Active write transfers (`active_writes > 0`) can only exist if `underlying_sink_ != nullptr` and `port_.is_bound()`.
3. **Total Disconnect Cleanup**: Execution of `OnConnectionError()` resets `port_`, signals errors on both streams, and clears all pending read/write data pipes, guaranteeing that `is_open == false` and `active_transfers == 0`.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkWebDeviceDisconnectCleanupSemantics.v`. It models the `SerialPort` state machine, stream states, Mojo connection states, and normal vs. disconnect transitions, using `ZArith`, `Lia`, and `Bool`.

```coq
(** * BlinkWebDeviceDisconnectCleanupSemantics.v
    Formal verification of Web Serial / WebUSB / WebHID disconnect teardown
    in Chromium Blink (third_party/blink/renderer/modules/serial/serial_port.cc).
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micega.Lia.

Open Scope Z_scope.

(** ** 1. Formal Types and State Definitions *)

(** Represents the state of a ReadableStream or WritableStream in Blink *)
Inductive StreamState : Type :=
  | StreamClosed : StreamState
  | StreamOpen   : Z -> StreamState (* Parameter tracks active in-flight chunks/transfers *)
  | StreamErrored: StreamState.

(** Represents the state of the Mojo IPC Remote<SerialPort> binding *)
Inductive MojoPortState : Type :=
  | MojoUnbound : MojoPortState
  | MojoBound   : MojoPortState.

(** Represents the composite state of blink::SerialPort *)
Record SerialPortState : Type := mkSerialPortState {
  mojo_port        : MojoPortState;
  closing_flag     : bool;
  readable_source  : StreamState;
  writable_sink    : StreamState;
  pending_open_req : bool;
  pending_close_req: bool;
  in_flight_ctrl   : Z (* Control transfers / signals e.g. setSignals, getSignals *)
}.

(** ** 2. Observables and State Queries *)

(** Extracts the number of active transfers from a StreamState *)
Definition stream_transfers (ss : StreamState) : Z :=
  match ss with
  | StreamOpen n => Z.max 0 n
  | StreamClosed => 0
  | StreamErrored => 0
  end.

(** Authoritative check for whether the device port is open in Blink:
    corresponds to [port_.is_bound() && !closing_] *)
Definition is_open (s : SerialPortState) : bool :=
  match s.(mojo_port) with
  | MojoBound => negb s.(closing_flag)
  | MojoUnbound => false
  end.

(** Total active transfers across readable source, writable sink, and control pipe *)
Definition active_transfers (s : SerialPortState) : Z :=
  stream_transfers s.(readable_source) +
  stream_transfers s.(writable_sink) +
  Z.max 0 s.(in_flight_ctrl).

(** ** 3. Hardware API Well-Formedness Invariant *)

(** Defines the structural safety invariant maintained by Blink's SerialPort *)
Definition WellFormedPort (s : SerialPortState) : Prop :=
  (* 1. Control transfers are non-negative *)
  s.(in_flight_ctrl) >= 0 /\
  (* 2. Stream transfer counts are non-negative when open *)
  (forall n, s.(readable_source) = StreamOpen n -> n >= 0) /\
  (forall n, s.(writable_sink) = StreamOpen n -> n >= 0) /\
  (* 3. If Mojo port is unbound, streams cannot be open and no control transfers exist *)
  (s.(mojo_port) = MojoUnbound ->
    s.(closing_flag) = false /\
    s.(readable_source) <> StreamOpen 0 /\
    (forall n, s.(readable_source) <> StreamOpen n) /\
    (forall n, s.(writable_sink) <> StreamOpen n) /\
    s.(in_flight_ctrl) = 0 /\
    s.(pending_open_req) = false /\
    s.(pending_close_req) = false).

(** ** 4. Operational Transitions *)

(** Initial closed state of a newly constructed SerialPort *)
Definition init_port_state : SerialPortState := {|
  mojo_port         := MojoUnbound;
  closing_flag      := false;
  readable_source   := StreamClosed;
  writable_sink     := StreamClosed;
  pending_open_req  := false;
  pending_close_req := false;
  in_flight_ctrl    := 0
|}.

(** Transition: Opening a port (SerialPort::Open -> OnOpen) *)
Definition open_port (s : SerialPortState) : SerialPortState :=
  match s.(mojo_port) with
  | MojoUnbound => {|
      mojo_port         := MojoBound;
      closing_flag      := false;
      readable_source   := StreamOpen 0;
      writable_sink     := StreamOpen 0;
      pending_open_req  := false;
      pending_close_req := false;
      in_flight_ctrl    := 0
    |}
  | MojoBound => s
  end.

(** Transition: Enqueueing a read transfer on the readable stream *)
Definition start_read (s : SerialPortState) : SerialPortState :=
  if is_open s then
    match s.(readable_source) with
    | StreamOpen n => {|
        mojo_port         := s.(mojo_port);
        closing_flag      := s.(closing_flag);
        readable_source   := StreamOpen (Z.max 0 n + 1);
        writable_sink     := s.(writable_sink);
        pending_open_req  := s.(pending_open_req);
        pending_close_req := s.(pending_close_req);
        in_flight_ctrl    := s.(in_flight_ctrl)
      |}
    | _ => s
    end
  else s.

(** Transition: Enqueueing a write transfer on the writable stream *)
Definition start_write (s : SerialPortState) : SerialPortState :=
  if is_open s then
    match s.(writable_sink) with
    | StreamOpen n => {|
        mojo_port         := s.(mojo_port);
        closing_flag      := s.(closing_flag);
        readable_source   := s.(readable_source);
        writable_sink     := StreamOpen (Z.max 0 n + 1);
        pending_open_req  := s.(pending_open_req);
        pending_close_req := s.(pending_close_req);
        in_flight_ctrl    := s.(in_flight_ctrl)
      |}
    | _ => s
    end
  else s.

(** Helper: SignalErrorOnClose transition for a stream *)
Definition signal_error_on_close (ss : StreamState) : StreamState :=
  match ss with
  | StreamOpen _ => StreamErrored
  | StreamClosed => StreamClosed
  | StreamErrored => StreamErrored
  end.

(** Transition: Physical/Logical Device Disconnection
    Models [SerialPort::OnConnectionError()] in serial_port.cc *)
Definition disconnect (s : SerialPortState) : SerialPortState := {|
  mojo_port         := MojoUnbound;
  closing_flag      := false;
  readable_source   := signal_error_on_close s.(readable_source);
  writable_sink     := signal_error_on_close s.(writable_sink);
  pending_open_req  := false;
  pending_close_req := false;
  in_flight_ctrl    := 0
|}.
```

---

## 4. Concrete Theorems and Complete Proofs

The following Rocq/Coq code provides the complete, admitted-free verification of the target mathematical property alongside auxiliary lemmas demonstrating invariant preservation, stream termination, and idempotence.

```coq
(** ** 5. Formal Verification and Proofs *)

(** Lemma 1: [signal_error_on_close] always reduces stream transfers to 0 *)
Lemma signal_error_zero_transfers : forall (ss : StreamState),
  stream_transfers (signal_error_on_close ss) = 0.
Proof.
  intros ss.
  destruct ss as [ | n | ]; simpl; reflexivity.
Qed.

(** Lemma 2: [signal_error_on_close] never produces an open stream *)
Lemma signal_error_not_open : forall (ss : StreamState) (n : Z),
  signal_error_on_close ss <> StreamOpen n.
Proof.
  intros ss n H.
  destruct ss as [ | m | ]; simpl in H; discriminate H.
Qed.

(** Lemma 3: Active transfers are always non-negative for any state *)
Lemma active_transfers_nonneg : forall (s : SerialPortState),
  active_transfers s >= 0.
Proof.
  intros s.
  unfold active_transfers, stream_transfers.
  destruct (readable_source s);
  destruct (writable_sink s);
  lia.
Qed.

(** Theorem 1 (Primary Target):
    Device disconnection guarantees that [is_open] becomes [false]
    and [active_transfers] becomes [0]. *)
Theorem disconnect_cleanup_correctness : forall (