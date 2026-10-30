# Formal Verification Report: Web Serial `parity` and `stopBits` Enum Validity Semantics

**Agent:** 621 (Web Hardware & Peripheral Platform APIs)  
**Topic:** Web Serial `parity` and `stopBits` Enum Validity Semantics  
**Chromium Source:** `third_party/blink/renderer/modules/serial/serial_port.cc`  
**Specification:** W3C Web Serial API §3.2 (`SerialOptions` dictionary, `ParityType` enumeration, `stopBits` validation)  
**Formal Theory Target:** `BlinkWebSerialParityStopBitsSemantics.v`  

---

## 1. Normative W3C Web Serial Specification Requirements

Within the W3C Web Serial API specification, serial port configuration parameters are provided to the `SerialPort.open(options)` method via the `SerialOptions` WebIDL dictionary.

### 1.1 WebIDL Definitions (§3.2)

```webidl
enum ParityType {
  "none",
  "even",
  "odd"
};

dictionary SerialOptions {
  required [EnforceRange] unsigned long baudRate;
  [EnforceRange] octet dataBits = 8;
  [EnforceRange] octet stopBits = 1;
  ParityType parity = "none";
  [EnforceRange] unsigned long bufferSize = 255;
  FlowControlType flowControl = "none";
};
```

### 1.2 Normative Validation Steps in `open()` (§3.2.3)

When the `open(options)` method is invoked on a `SerialPort` instance, the user agent must validate the supplied `SerialOptions` dictionary before initiating a hardware connection request over IPC:

1. **Parity Validation (`options["parity"]`):**
   - WebIDL bindings enforce that `options["parity"]` is a valid member of the `ParityType` enumeration: `"none"`, `"even"`, or `"odd"`. Any other string provided by JavaScript throws a WebIDL `TypeError` before entering the platform implementation. Default value is `"none"`.
2. **Stop Bits Validation (`options["stopBits"]`):**
   - WebIDL `[EnforceRange] octet` ensures the value is an integer in $[0, 255]$ (defaulting to $1$).
   - **Normative Step:** *"If `options["stopBits"]` is not 1 or 2, reject `promise` with a `TypeError` and abort these steps."*

### 1.3 Mathematical Property
Let $P$ be the domain of parity representations and $S \subset \mathbb{Z}$ be the domain of stop bits values passed after WebIDL `[EnforceRange] octet` conversion. The configuration validity predicates are:
$$\text{valid\_parity}(p) \iff p \in \{\text{none}, \text{even}, \text{odd}\}$$
$$\text{valid\_stop\_bits}(s) \iff s \in \{1, 2\}$$

---

## 2. Chromium Blink Implementation & Invariants

In Chromium's Blink rendering engine (`third_party/blink/renderer/modules/serial/serial_port.cc`), `SerialPort::open` translates the Blink WebIDL `SerialOptions` object into a Mojo `device::mojom::blink::SerialConnectionOptions` struct to send across the browser/utility process boundary to the `device::SerialIoHandler`.

### 2.1 Source Analysis: `serial_port.cc`

```cpp
// third_party/blink/renderer/modules/serial/serial_port.cc

ScriptPromise<IDLUndefined> SerialPort::open(
    ScriptState* script_state,
    const SerialOptions* options,
    ExceptionState& exception_state) {
  // ... [State & baudRate / dataBits checks] ...

  auto mojo_options = device::mojom::blink::SerialConnectionOptions::New();
  
  // 1. Parity validation and Mojo mapping
  switch (options->parity().AsEnum()) {
    case V8ParityType::Enum::kNone:
      mojo_options->parity_bit = device::mojom::blink::SerialParityBit::kNoParity;
      break;
    case V8ParityType::Enum::kEven:
      mojo_options->parity_bit = device::mojom::blink::SerialParityBit::kEvenParity;
      break;
    case V8ParityType::Enum::kOdd:
      mojo_options->parity_bit = device::mojom::blink::SerialParityBit::kOddParity;
      break;
  }

  // 2. StopBits validation and Mojo mapping
  switch (options->stopBits()) {
    case 1:
      mojo_options->stop_bits = device::mojom::blink::SerialStopBits::kOneStopBit;
      break;
    case 2:
      mojo_options->stop_bits = device::mojom::blink::SerialStopBits::kTwoStopBits;
      break;
    default:
      exception_state.ThrowTypeError(
          "Requested stopBits value \"" +
          String::Number(options->stopBits()) +
          "\" is invalid. Must be either 1 or 2.");
      return EmptyPromise();
  }

  // ... [bufferSize & flowControl checks, followed by IPC call] ...
}
```

### 2.2 Implementation Invariants
1. **Total Exhaustiveness over Valid `V8ParityType`:** V8 bindings guarantee `options->parity().AsEnum()` yields one of `kNone`, `kEven`, or `kOdd`. Blink maps these injectively to `kNoParity`, `kEvenParity`, and `kOddParity`, ensuring `SerialParityBit::kUnspecified` is never sent over IPC.
2. **Strict Filtering of `stopBits`:** Although `options->stopBits()` is a `uint8_t` ($0 \dots 255$), the `switch` statement strictly accepts only `1` and `2`, mapping them to `kOneStopBit` and `kTwoStopBits`. All other 254 values trigger `exception_state.ThrowTypeError(...)` and abort IPC dispatch. `SerialStopBits::kUnspecified` is never transmitted.
3. **IPC Boundary Safety:** The hardware driver layer (`SerialIoHandler`) never receives unvalidated or `kUnspecified` parity or stop-bit flags from the renderer when `open()` succeeds.

---

## 3. Formal Specification in Rocq / Coq

Below is the self-contained, admitted-free Rocq formalization `BlinkWebSerialParityStopBitsSemantics.v`. It models the WebIDL inputs, raw integer/string representations, Mojo IPC enumerations, the Blink translation state machine, and the formal equivalence between the W3C specification predicates and Blink's implementation.

```coq
(** * BlinkWebSerialParityStopBitsSemantics.v
    Formal verification of W3C Web Serial API §3.2 ParityType and stopBits
    validation and Mojo IPC translation in Chromium Blink's serial_port.cc. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. WebIDL and Specification Domains *)

(** Raw representation of parity strings prior to / at WebIDL boundary:
    0 = "none", 1 = "even", 2 = "odd", others = invalid string. *)
Definition RawParityInput := Z.

(** WebIDL V8ParityType::Enum generated by Blink bindings *)
Inductive ParityType : Type :=
  | ParityNone : ParityType
  | ParityEven : ParityType
  | ParityOdd  : ParityType.

Scheme Equality for ParityType.

(** Raw stopBits value after WebIDL [EnforceRange] octet (0..255) *)
Definition StopBitsInput := Z.

(** ** 2. Mojo Hardware IPC Domains (device::mojom::blink) *)

Inductive MojoSerialParityBit : Type :=
  | MojoParityUnspecified : MojoSerialParityBit
  | MojoNoParity          : MojoSerialParityBit
  | MojoEvenParity        : MojoSerialParityBit
  | MojoOddParity         : MojoSerialParityBit.

Scheme Equality for MojoSerialParityBit.

Inductive MojoSerialStopBits : Type :=
  | MojoStopBitsUnspecified : MojoSerialStopBits
  | MojoOneStopBit          : MojoSerialStopBits
  | MojoTwoStopBits         : MojoSerialStopBits.

Scheme Equality for MojoSerialStopBits.

(** ** 3. Mathematical Specification Predicates (W3C §3.2) *)

(** Mathematical property: valid_parity(p) in {none, even, odd} *)
Definition valid_parity (p : ParityType) : Prop :=
  In p [ParityNone; ParityEven; ParityOdd].

Definition valid_raw_parity (raw_p : RawParityInput) : Prop :=
  raw_p = 0 \/ raw_p = 1 \/ raw_p = 2.

Definition valid_raw_parity_b (raw_p : RawParityInput) : bool :=
  (raw_p =? 0) || (raw_p =? 1) || (raw_p =? 2).

(** Mathematical property: valid_stop_bits(s) in {1, 2} *)
Definition valid_stop_bits (s : StopBitsInput) : Prop :=
  s = 1 \/ s = 2.

Definition valid_stop_bits_b (s : StopBitsInput) : bool :=
  (s =? 1) || (s =? 2).

(** WebIDL [EnforceRange] octet invariant *)
Definition is_octet (s : StopBitsInput) : Prop :=
  0 <= s <= 255.

(** ** 4. Blink Implementation Semantics (serial_port.cc) *)

(** V8 WebIDL binding parser for ParityType *)
Definition v8_parse_parity (raw_p : RawParityInput) : option ParityType :=
  if raw_p =? 0 then Some ParityNone
  else if raw_p =? 1 then Some ParityEven
  else if raw_p =? 2 then Some ParityOdd
  else None.

(** Blink switch(options->parity().AsEnum()) in SerialPort::open *)
Definition blink_map_parity (p : ParityType) : MojoSerialParityBit :=
  match p with
  | ParityNone => MojoNoParity
  | ParityEven => MojoEvenParity
  | ParityOdd  => MojoOddParity
  end.

(** Blink switch(options->stopBits()) in SerialPort::open *)
Inductive BlinkResult (A : Type) : Type :=
  | Ok             : A -> BlinkResult A
  | ThrowTypeError : BlinkResult A.

Arguments Ok {A} _.
Arguments ThrowTypeError {A}.

Definition blink_validate_and_map_stop_bits (s : StopBitsInput)
  : BlinkResult MojoSerialStopBits :=
  if s =? 1 then Ok MojoOneStopBit
  else if s =? 2 then Ok MojoTwoStopBits
  else ThrowTypeError.

(** Combined Blink SerialOptions validation for parity & stopBits *)
Record MojoParityStopConfig : Type := mkMojoConfig {
  mojo_parity_bit : MojoSerialParityBit;
  mojo_stop_bits  : MojoSerialStopBits
}.

Definition blink_configure_parity_stop_bits
  (p : ParityType) (s : StopBitsInput) : BlinkResult MojoParityStopConfig :=
  let mp := blink_map_parity p in
  match blink_validate_and_map_stop_bits s with
  | Ok ms => Ok (mkMojoConfig mp ms)
  | ThrowTypeError => ThrowTypeError
  end.

(** Full pipeline from raw JS inputs through WebIDL + SerialPort::open *)
Definition full_open_parity_stop_pipeline
  (raw_p : RawParityInput) (s : StopBitsInput)
  : BlinkResult MojoParityStopConfig :=
  match v8_parse_parity raw_p with
  | Some p => blink_configure_parity_stop_bits p s
  | None   => ThrowTypeError
  end.

(** Hardware IPC safety predicates: Mojo "Unspecified" sentinels are forbidden *)
Definition mojo_parity_specified (mp : MojoSerialParityBit) : Prop :=
  mp <> MojoParityUnspecified.

Definition mojo_stop_bits_specified (ms : MojoSerialStopBits) : Prop :=
  ms <> MojoStopBitsUnspecified.

Definition mojo_config_hardware_safe (cfg : MojoParityStopConfig) : Prop :=
  mojo_parity_specified (mojo_parity_bit cfg) /\
  mojo_stop_bits_specified (mojo_stop_bits cfg).
```

---

## 4. Concrete Theorems and Complete Rocq Proofs

```coq
(** ** 5. Formal Verification Theorems & Proofs *)

(** Theorem 1: Every V8 ParityType value satisfies valid_parity(p) in {none, even, odd}. *)
Theorem parity_type_exhaustive_validity :
  forall (p : ParityType), valid_parity p.
Proof.
  intros p.
  unfold valid_parity.
  destruct p; simpl; auto.
Qed.

(** Theorem 2: Boolean reflection for raw parity validation. *)
Theorem valid_raw_parity_reflect :
  forall (raw_p : RawParityInput),
     valid_raw_parity_b raw_p = true <-> valid_raw_parity raw_p.
Proof.
  intros raw_p.
  unfold valid_raw_parity_b, valid_raw_parity.
  repeat rewrite orb_true_iff.
  repeat rewrite Z.eqb_eq.
  tauto.
Qed.

(** Theorem 3: V8 parity parser succeeds if and only if raw input is in {0, 1, 2}. *)
Theorem v8_parse_parity_iff_valid_raw :
  forall (raw_p : RawParityInput),
    (exists p, v8_parse_parity raw_p = Some p) <-> valid_raw_parity raw_p.
Proof.
  intros raw_p.
  unfold v8_parse_parity, valid_raw_parity.
  destruct (raw_p =? 0) eqn:E0.
  - rewrite Z.eqb_eq in E0. split; intros _; [left; exact E0 | exists ParityNone; reflexivity].
  - destruct (raw_p =? 1) eqn:E1.
    + rewrite Z.eqb_eq in E1. split; intros _; [right; left; exact E1 | exists ParityEven; reflexivity].
    + destruct (raw_p =? 2) eqn:E2.
      * rewrite Z.eqb_eq in E2. split; intros _; [right; right; exact E2 | exists ParityOdd; reflexivity].
      * rewrite Z.eqb_neq in E0, E1, E2.
        split.
        -- intros [p H]. discriminate H.
        -- intros [H | [H | H]]; lia.
Qed.

(** Theorem 4: Boolean reflection for valid_stop_bits(s) in {1, 2}. *)
Theorem valid_stop_bits_reflect :
  forall (s : StopBitsInput),
    valid_stop_bits_b s = true <-> valid_stop_bits s.
Proof.
  intros s.
  unfold valid_stop_bits_b, valid_stop_bits.
  rewrite orb_true