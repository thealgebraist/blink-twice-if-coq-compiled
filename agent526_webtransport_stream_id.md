# Formal Verification of Chromium Blink WebTransport Stream ID Classification and Multiplexing Semantics

**Target Implementation**: `third_party/blink/renderer/modules/webtransport/web_transport.cc`  
**Normative Specifications**: IETF RFC 9000 §2.1 (QUIC: A UDP-Based Multiplexed and Secure Transport), W3C WebTransport Specification §5–§6  
**Formal Theory Module**: `BlinkWebTransportStreamIDMultiplexSemantics.v`  
**Verification Backend**: Rocq/Coq 8.18+ (`ZArith`, `Lia`, `Bool`, `List`)

---

## 1. Normative Specification Requirements

WebTransport over HTTP/3 (and raw QUIC) multiplexes multiple independent data streams over a single underlying transport connection. To avoid head-of-line blocking and coordination round-trips during stream creation, stream creation authority and directional topology are algebraically encoded directly into the 62-bit unsigned integer Stream ID space ($\mathbb{Z} \cap [0, 2^{62}-1]$).

### 1.1 IETF RFC 9000 §2.1 (Stream Types and Identifiers)

Per **RFC 9000 Section 2.1**, streams are identified by an unsigned 62-bit integer, referred to as the Stream ID. The least significant two bits of the Stream ID ($id \bmod 4$) partition the identifier space into four disjoint equivalence classes based on two orthogonal binary properties:

1. **Bit 0 ($2^0$, value `0x1`) — Initiator Role**:
   - `0`: Client-initiated stream.
   - `1`: Server-initiated stream.
2. **Bit 1 ($2^1$, value `0x2`) — Directionality**:
   - `0`: Bidirectional stream (data frames may flow in both directions).
   - `1`: Unidirectional stream (data frames may only flow from the initiator to the peer).

This yields the canonical classification table mandated by Table 1 of RFC 9000:

| Bits (`id mod 4`) | Binary | Stream Type | WebTransport Renderer Mapping |
| :--- | :--- | :--- | :--- |
| `0x00` (`0`) | `00` | Client-Initiated, Bidirectional | Resolved via `createBidirectionalStream()` Promise |
| `0x01` (`1`) | `01` | Server-Initiated, Bidirectional | Enqueued into `incomingBidirectionalStreams` (`ReadableStream`) |
| `0x02` (`2`) | `10` | Client-Initiated, Unidirectional | Resolved via `createUnidirectionalStream()` Promise (`SendStream`) |
| `0x03` (`3`) | `11` | Server-Initiated, Unidirectional | Enqueued into `incomingUnidirectionalStreams` (`ReceiveStream`) |

Furthermore, RFC 9000 §2.1 mandates sequential allocation within each class: a stream ID of type $t \in \{0,1,2,3\}$ with sequence index $k \in \mathbb{N}$ is strictly $4k + t$, bounded by $2^{62} - 1$.

### 1.2 W3C WebTransport API Invariants

In the W3C WebTransport specification, a user agent's renderer process always operates as the QUIC/WebTransport **Client** role relative to the remote endpoint (**Server**). Consequently:
- **Outbound stream creation** (`createBidirectionalStream`, `createUnidirectionalStream`) must strictly yield stream IDs where `id mod 2 = 0` (`Initiator = Client`).
- **Inbound stream reception** (`OnIncomingStream` IPC callbacks) must strictly yield stream IDs where `id mod 2 = 1` (`Initiator = Server`), routing `id mod 4 = 1` to `BidirectionalStream` wrappers and `id mod 4 = 3` to `ReceiveStream` wrappers.
- **Multiplexing Disjointness**: No single `stream_id` may simultaneously exist in both the unidirectional and bidirectional stream tables, nor may a client-allocated stream collide with a server-pushed stream.

---

## 2. Chromium Blink Implementation Analysis

In Chromium's multi-process architecture, the Network Service (`services/network/web_transport.cc`) manages the underlying `quic::WebTransportHttp3` session, while the Blink Renderer (`third_party/blink/renderer/modules/webtransport/web_transport.cc`) exposes the JavaScript bindings (`WebTransport`, `WebTransportBidirectionalStream`, `WebTransportSendStream`, `WebTransportReceiveStream`) and coordinates Mojo DataPipes with WHATWG Streams (`ReadableStream` and `WritableStream`).

### 2.1 Stream Tracking and Multiplexing State in `web_transport.cc`

Inside `blink::WebTransport`, active streams are indexed in a unified `HeapHashMap` (`stream_map_`) keyed by `uint32_t` (or `uint64_t` at the QUIC layer, truncated/validated over Mojo IPC) `stream_id`:

1. **`CreateWritableStream` (`createUnidirectionalStream`)**:
   - Sends a Mojo IPC request `transport_remote_->CreateStream(readable, writable, callback)` where `readable` is invalid (null handle) and `writable` is a valid Mojo `ScopedDataPipeProducerHandle`.
   - Upon IPC completion, the network service returns `stream_id`. In accordance with RFC 9000 §2.1, this ID satisfies `stream_id & 0x3 == 0x2` (Client-Initiated, Unidirectional).
   - Blink instantiates a `SendStream` (wrapping a `WritableStream`), inserts it into `stream_map_`, and resolves the script promise.

2. **`CreateBidirectionalStream` (`createBidirectionalStream`)**:
   - Sends `transport_remote_->CreateStream(incoming_consumer, outgoing_producer, callback)` with both producer and consumer handles valid.
   - The returned `stream_id` satisfies `stream_id & 0x3 == 0x0` (Client-Initiated, Bidirectional).
   - Blink constructs a `BidirectionalStream` (pairing a `SendStream` and `ReceiveStream`), registers it in `stream_map_`, and resolves the promise.

3. **`OnIncomingUnidirectionalStreamAvailable` (via `AcceptUnidirectionalStream`)**:
   - Receives `stream_id` and `ScopedDataPipeConsumerHandle` from the network process.
   - Invariant: `stream_id & 0x3 == 0x3` (Server-Initiated, Unidirectional).
   - Enqueues a newly constructed `ReceiveStream` into the `received_streams_underlying_source_` controller backing `transport.incomingUnidirectionalStreams`.

4. **`OnIncomingBidirectionalStreamAvailable` (via `AcceptBidirectionalStream`)**:
   - Receives `stream_id`, `ScopedDataPipeConsumerHandle`, and `ScopedDataPipeProducerHandle`.
   - Invariant: `stream_id & 0x3 == 0x1` (Server-Initiated, Bidirectional).
   - Enqueues a `BidirectionalStream` into `received_bidirectional_streams_underlying_source_` backing `transport.incomingBidirectionalStreams`.

### 2.2 Critical Renderer Invariants

- **DataPipe Capability Alignment**: A stream registered in `web_transport.cc` has a writable Mojo producer pipe if and only if `(stream_id mod 4) ∈ {0, 1, 2}` (i.e., `stream_id mod 4 != 3`), and a readable Mojo consumer pipe if and only if `(stream_id mod 4) ∈ {0, 1, 3}` (i.e., `stream_id mod 4 != 2`).
- **Stream Map Non-Interference**: Because client-initiated streams (`{0, 2}`) and server-initiated streams (`{1, 3}`) occupy disjoint residue classes modulo 4, asynchronous IPC races between `CreateStream` responses and `Accept*Stream` callbacks can never cause a key collision in `stream_map_`.
- **Stream Reset / Abort Routing**: When `OnOutgoingStreamClosed(stream_id)` or `ResetStream(stream_id, code)` is invoked, the capabilities of the looked-up stream in `stream_map_` are uniquely and sound-by-construction determined by `stream_id mod 4`.

---

## 3. Formal Specification & Verification in Rocq/Coq

Below is the complete, self-contained formalization `BlinkWebTransportStreamIDMultiplexSemantics.v`. Every theorem is proved constructively with zero `Admitted` statements.

```coq
(** * BlinkWebTransportStreamIDMultiplexSemantics.v
    Formal Verification of RFC 9000 §2.1 Stream ID Classification and
    Chromium Blink WebTransport Multiplexing Invariants
    (third_party/blink/renderer/modules/webtransport/web_transport.cc)
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ========================================================================= *)
(** ** 1. Normative Domain Definitions (RFC 9000 §2.1)                        *)
(** ========================================================================= *)

(** Maximum QUIC 62-bit Stream ID bound: 2^62 - 1 *)
Definition MAX_STREAM_ID : Z := 4611686018427387903.

Definition valid_stream_id (id : Z) : Prop :=
  0 <= id <= MAX_STREAM_ID.

(** Initiator role encoded in Bit 0 (2^0 = 0x1) *)
Inductive Initiator : Type :=
  | ClientInitiated : Initiator
  | ServerInitiated : Initiator.

Scheme Equality for Initiator.

(** Directionality encoded in Bit 1 (2^1 = 0x2) *)
Inductive Directionality : Type :=
  | Bidirectional  : Directionality
  | Unidirectional : Directionality.

Scheme Equality for Directionality.

(** Composite 4-way stream classification *)
Inductive StreamClass : Type :=
  | Class_ClientBidi : StreamClass (* 0x00 *)
  | Class_ServerBidi : StreamClass (* 0x01 *)
  | Class_ClientUni  : StreamClass (* 0x02 *)
  | Class_ServerUni  : StreamClass (* 0x03 *).

Scheme Equality for StreamClass.

(** Algebraic projection of Initiator from Stream ID *)
Definition get_initiator (id : Z) : Initiator :=
  if Z.eqb (id mod 2) 0 then ClientInitiated else ServerInitiated.

(** Algebraic projection of Directionality from Stream ID *)
Definition get_directionality (id : Z) : Directionality :=
  if Z.ltb (id mod 4) 2 then Bidirectional else Unidirectional.

(** Modulo-4 classifier per RFC 9000 Table 1 *)
Definition classify_stream_id (id : Z) : StreamClass :=
  let r := id mod 4 in
  if Z.eqb r 0 then Class_ClientBidi
  else if Z.eqb r 1 then Class_ServerBidi
  else if Z.eqb r 2 then Class_ClientUni
  else Class_ServerUni.

(** Pair projection from StreamClass *)
Definition class_to_props (c : StreamClass) : Initiator * Directionality :=
  match c with
  | Class_ClientBidi => (ClientInitiated, Bidirectional)
  | Class_ServerBidi => (ServerInitiated, Bidirectional)
  | Class_ClientUni  => (ClientInitiated, Unidirectional)
  | Class_ServerUni  => (ServerInitiated, Unidirectional)
  end.

(** Canonical stream ID encoder from sequence number k and class c *)
Definition encode_stream_id (k : Z) (c : StreamClass) : Z :=
  4 * k + match c with
          | Class_ClientBidi => 0
          | Class_ServerBidi => 1
          | Class_ClientUni  => 2
          | Class_ServerUni  => 3
          end.

(** Sequence index extraction *)
Definition decode_sequence_index (id : Z) : Z :=
  id / 4.

(** ========================================================================= *)
(** ** 2. Blink Renderer Capability & Multiplexing Models                     *)
(** ========================================================================= *)

(** In Blink's web_transport.cc, the renderer always acts as the QUIC client.
    Each stream has specific DataPipe capabilities:
    - Outgoing producer pipe (SendStream / WritableStream)
    - Incoming consumer pipe (ReceiveStream / ReadableStream) *)
Record BlinkStreamCapabilities : Type := mkCaps {
  can_send    : bool;
  can_receive : bool;
  is_local    : bool
}.

(** Expected capabilities derived from StreamClass in web_transport.cc *)
Definition blink_capabilities_of_class (c : StreamClass) : BlinkStreamCapabilities :=
  match c with
  | Class_ClientBidi => mkCaps true  true  true
  | Class_ServerBidi => mkCaps true  true  false
  | Class_ClientUni  => mkCaps true  false true
  | Class_ServerUni  => mkCaps false true  false
  end.

(** Direct bit-level capability predicates used in Blink/QUIC checks *)
Definition has_send_pipe (id : Z) : bool :=
  negb (Z.eqb (id mod 4) 3).

Definition has_receive_pipe (id : Z) : bool :=
  negb (Z.eqb (id mod 4) 2).

Definition is_client_initiated_bool (id : Z) : bool :=
  Z.eqb (id mod 2) 0.

(** Blink Renderer routing destinations in web_transport.cc *)
Inductive BlinkRoutingQueue : Type :=
  | Route_ResolveCreateBidiPromise      : BlinkRoutingQueue
  | Route_ResolveCreateUniPromise       : BlinkRoutingQueue
  | Route_EnqueueIncomingBidiStream     : BlinkRoutingQueue
  | Route_EnqueueIncomingUniStream      : BlinkRoutingQueue.

Definition route_stream_in_blink (id : Z) : BlinkRoutingQueue :=
  match classify_stream_id id with
  | Class_ClientBidi => Route_ResolveCreateBidiPromise
  | Class_ClientUni  => Route_ResolveCreateUniPromise
  | Class_ServerBidi => Route_EnqueueIncomingBidiStream
  | Class_ServerUni  => Route_EnqueueIncomingUniStream
  end.

(** ========================================================================= *)
(** ** 3. Core Arithmetic & Classification Theorems                           *)
(** ========================================================================= *)

(** Lemma: For any integer id, id mod 4 is strictly one of 0, 1, 2, or 3. *)
Lemma mod4_cases : forall id : Z,
  id mod 4 = 0 \/ id mod 4 = 1 \/ id mod 4 = 2 \/ id mod 4 = 3.
Proof.
  intro id.
  pose proof (Z.mod_pos_bound id 4ltac:(lia)) as Hbound.
  lia.
Qed.

(** Lemma: Relation between (id mod 4) and (id mod 2). *)
Lemma mod4_mod2_compat : forall id : Z,
  (id mod 4) mod 2 = id mod 2.
Proof.
  intro id.
  rewrite (Z_div_mod_eq_full id 