# Formal Verification Report: WebUSB Control Transfer Setup Packet 8-Byte Layout Soundness

**Agent:** 616 (Web Hardware & Peripheral Platform APIs)  
**Chromium Component:** `third_party/blink/renderer/modules/webusb/usb_device.cc`  
**Specifications:** W3C WebUSB API §3.3 (Control Transfers), USB 2.0 Specification §9.3 (USB Device Requests: Setup Packet)  
**Formal Theory Target:** `BlinkWebUSBSetupPacketLengthSemantics.v`  
**Mathematical Property:** $\text{setup\_packet\_size} = 1 + 1 + 2 + 2 + 2 = 8 \text{ bytes invariant}$  

---

## 1. Normative Specification Requirements

### 1.1 USB 2.0 Specification §9.3 (USB Device Requests)
All USB devices respond to requests from the host on the device's Default Control Pipe. These requests are made using control transfers. The request and the request's parameters are sent to the device by the host in the **Setup packet**. Every Setup packet has a strict, immutable 8-byte binary layout defined in Table 9-2 (*Format of Setup Data*):

| Offset | Field | Size (Bytes) | Value / Description |
| :--- | :--- | :--- | :--- |
| 0 | `bmRequestType` | 1 | Characteristics of request:<ul><li>Bit 7: Transfer direction (`0` = Host-to-device, `1` = Device-to-host)</li><li>Bits 6..5: Type (`0` = Standard, `1` = Class, `2` = Vendor, `3` = Reserved)</li><li>Bits 4..0: Recipient (`0` = Device, `1` = Interface, `2` = Endpoint, `3` = Other, `4..31` = Reserved)</li></ul> |
| 1 | `bRequest` | 1 | Specific request (uint8: $0 \dots 255$). |
| 2 | `wValue` | 2 | Word-sized field that varies according to request (uint16 little-endian: $0 \dots 65535$). |
| 4 | `wIndex` | 2 | Word-sized field that varies according to request; typically used to pass an index or offset (uint16 little-endian: $0 \dots 65535$). |
| 6 | `wLength` | 2 | Number of bytes to transfer if there is a Data stage (uint16 little-endian: $0 \dots 65535$). |

**Total Hardware Packet Size Invariant:**
$$\text{Size}(\text{SetupPacket}) = \text{Size}(\text{bmRequestType}) + \text{Size}(\text{bRequest}) + \text{Size}(\text{wValue}) + \text{Size}(\text{wIndex}) + \text{Size}(\text{wLength}) = 1 + 1 + 2 + 2 + 2 = 8\text{ bytes}$$

### 1.2 W3C WebUSB API §3.3 (`USBControlTransferParameters`)
The W3C WebUSB specification abstracts the 8-byte USB Setup packet through the `USBControlTransferParameters` WebIDL dictionary and the `controlTransferIn(setup, length)` / `controlTransferOut(setup, data)` methods on the `USBDevice` interface:

```webidl
enum USBRequestType {
  "standard",
  "class",
  "vendor"
};

enum USBRecipient {
  "device",
  "interface",
  "endpoint",
  "other"
};

dictionary USBControlTransferParameters {
  required USBRequestType requestType;
  required USBRecipient recipient;
  required octet request;
  required unsigned short value;
  required unsigned short index;
};
```

Normative requirements under `controlTransferIn(setup, length)` and `controlTransferOut(setup, data)`:
1. **Direction Bit Synthesis:** `controlTransferIn` sets bit 7 of `bmRequestType` to `1` (Device-to-host / `IN`). `controlTransferOut` sets bit 7 of `bmRequestType` to `0` (Host-to-device / `OUT`).
2. **Type and Recipient Packing:** `requestType` maps to bits $6..5$ ($0, 1, 2$) and `recipient` maps to bits $4..0$ ($0, 1, 2, 3$) of the 1-byte `bmRequestType` field.
3. **Field Bounds:** WebIDL enforces `octet` ($[0, 255]$, 1 byte) for `request`, and `unsigned short` ($[0, 65535]$, 2 bytes) for `value` and `index`.
4. **Length Bounding (`wLength`):**
   - In `controlTransferIn(setup, length)`, `length` is passed as an `unsigned short` ($[0, 65535]$, 2 bytes), directly populating `wLength`.
   - In `controlTransferOut(setup, data)`, if `data` (`BufferSource`) is provided, its `byteLength` MUST not exceed `65535` ($2^{16}-1$, fitting in the 2-byte `wLength` field). If `data.byteLength > 65535`, the user agent MUST reject the promise with a `TypeError` (or `InvalidStateError` / buffer overflow check in Mojo serialization).

---

## 2. Chromium Blink Implementation & Invariants

In Chromium's Blink rendering engine, `third_party/blink/renderer/modules/webusb/usb_device.cc` implements the translation from WebIDL JavaScript bindings to the `device::mojom::blink::UsbControlTransferParams` Mojo struct, which is subsequently serialized into the hardware 8-byte Setup packet by the USB service (`services/device/usb/usb_device_handle_impl.cc` / `libusb`).

### 2.1 Code Structure in `usb_device.cc`
The core helper function in `third_party/blink/renderer/modules/webusb/usb_device.cc` is `ConvertControlTransferParameters`:

```cpp
// third_party/blink/renderer/modules/webusb/usb_device.cc
UsbControlTransferParamsPtr USBDevice::ConvertControlTransferParameters(
    const USBControlTransferParameters* parameters,
    ExceptionState& exception_state) const {
  auto mojo_parameters = device::mojom::blink::UsbControlTransferParams::New();

  // 1. Maps to bits 6..5 of bmRequestType (1 byte total when combined)
  switch (parameters->requestType().AsEnum()) {
    case V8USBRequestType::Enum::kStandard:
      mojo_parameters->type = UsbControlTransferType::STANDARD;
      break;
    case V8USBRequestType::Enum::kClass:
      mojo_parameters->type = UsbControlTransferType::CLASS;
      break;
    case V8USBRequestType::Enum::kVendor:
      mojo_parameters->type = UsbControlTransferType::VENDOR;
      break;
  }

  // 2. Maps to bits 4..0 of bmRequestType
  switch (parameters->recipient().AsEnum()) {
    case V8USBRecipient::Enum::kDevice:
      mojo_parameters->recipient = UsbControlTransferRecipient::DEVICE;
      break;
    case V8USBRecipient::Enum::kInterface: {
      uint8_t interface_number = parameters->index() & 0xff;
      if (! EnsureInterfaceClaimed(interface_number, exception_state))
        return nullptr;
      mojo_parameters->recipient = UsbControlTransferRecipient::INTERFACE;
      break;
    }
    case V8USBRecipient::Enum::kEndpoint: {
      uint8_t endpoint_number = parameters->index() & 0x0f;
      bool in_transfer = (parameters->index() & 0x80) != 0;
      if (!EnsureEndpointAvailable(in_transfer, endpoint_number,
                                   exception_state)) {
        return nullptr;
      }
      mojo_parameters->recipient = UsbControlTransferRecipient::ENDPOINT;
      break;
    }
    case V8USBRecipient::Enum::kOther:
      mojo_parameters->recipient = UsbControlTransferRecipient::OTHER;
      break;
  }

  // 3. bRequest: uint8_t (1 byte)
  mojo_parameters->request = parameters->request();
  // 4. wValue: uint16_t (2 bytes)
  mojo_parameters->value = parameters->value();
  // 5. wIndex: uint16_t (2 bytes)
  mojo_parameters->index = parameters->index();

  return mojo_parameters;
}
```

And in `controlTransferIn` / `controlTransferOut`:
- `controlTransferIn(ScriptState*, const USBControlTransferParameters* setup, uint16_t length, ExceptionState&)`:
  `length` is strongly typed as `uint16_t` (2 bytes), directly enforcing $0 \le \text{wLength} \le 65535$.
- `controlTransferOut(ScriptState*, const USBControlTransferParameters* setup, const MaybeShared<DOMArrayBufferView>& data, ExceptionState&)`:
  Validates `buffer_size` fits within `uint16_t` (`wLength` 2-byte boundary) before dispatching `device_->ControlTransferOut(std::move(parameters), data, timeout, callback)`.

### 2.2 Implementation Invariants
1. **Bitfield Disjointness & 1-Byte Closure (`bmRequestType`):**
   $$\text{bmRequestType} = (\text{direction} \ll 7) \mid (\text{type} \ll 5) \mid \text{recipient}$$
   With $\text{direction} \in \{0,1\}$, $\text{type} \in \{0,1,2\}$, and $\text{recipient} \in \{0,1,2,3\}$, the synthesized byte strictly satisfies $0 \le \text{bmRequestType} \le 255$, occupying exactly **1 byte**.
2. **Fixed Width Scalar Serialization:**
   - `bRequest`: `uint8_t` $\implies$ **1 byte**.
   - `wValue`: `uint16_t` $\implies$ **2 bytes** (little-endian `[wValue & 0xFF, (wValue >> 8) & 0xFF]`).
   - `wIndex`: `uint16_t` $\implies$ **2 bytes** (little-endian `[wIndex & 0xFF, (wIndex >> 8) & 0xFF]`).
   - `wLength`: `uint16_t` $\implies$ **2 bytes** (little-endian `[wLength & 0xFF, (wLength >> 8) & 0xFF]`).
3. **Total Packet Length Invariant:**
   The serialized setup buffer length is strictly $1 + 1 + 2 + 2 + 2 = 8$ bytes across all valid executions of `controlTransferIn` and `controlTransferOut`.

---

## 3. Formal Specification in Rocq/Coq

Below is the self-contained, complete, and admitted-free Rocq/Coq formalization (`BlinkWebUSBSetupPacketLengthSemantics.v`) modeling the WebUSB control transfer parameter conversion, recipient security checks, bitwise `bmRequestType` synthesis, little-endian byte serialization, and the 8-byte layout soundness theorems.

```coq
(** * BlinkWebUSBSetupPacketLengthSemantics.v
    Formal Verification of WebUSB Control Transfer Setup Packet 8-Byte Layout Soundness
    Chromium Source: third_party/blink/renderer/modules/webusb/usb_device.cc
    Specifications: W3C WebUSB API §3.3 / USB 2.0 §9.3 Setup Packet *)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. WebUSB & USB 2.0 §9.3 Data Types *)

(** Transfer direction: Bit 7 of bmRequestType *)
Inductive USBTransferDirection : Type :=
  | DirectionOut (* 0: Host-to-device *)
  | DirectionIn. (* 1: Device-to-host *)

(** Request type: Bits 6..5 of bmRequestType *)
Inductive USBRequestType : Type :=
  | RequestTypeStandard (* 0 *)
  | RequestTypeClass    (* 1 *)
  | RequestTypeVendor.  (* 2 *)

(** Recipient: Bits 4..0 of bmRequestType *)
Inductive USBRecipient : Type :=
  | RecipientDevice    (* 0 *)
  | RecipientInterface (* 1 *)
  | RecipientEndpoint  (* 2 *)
  | RecipientOther.    (* 3 *)

(** WebIDL USBControlTransferParameters dictionary *)
Record USBControlTransferParameters : Type := mkUSBControlTransferParams {
  param_requestType : USBRequestType;
  param_recipient   : USBRecipient;
  param_request     : Z; (* octet: 0..255 *)
  param_value       : Z; (* unsigned short: 0..65535 *)
  param_index       : Z  (* unsigned short: 0..65535 *)
}.

(** Predicate asserting WebIDL integer type bounds on dictionary fields *)
Definition valid_webidl_params (p : USBControlTransferParameters) : Prop :=
  0 <= param_request p <= 255 /\
  0 <= param_value p <= 65535 /\
  0 <= param_index p <= 65535.

(** Device state modeling claimed interfaces and available endpoints in Blink *)
Record BlinkUSBDeviceState : Type := mkBlinkUSBDeviceState {
  device_opened : bool;
  claimed_interface : Z -> bool;         (* interface_number (0..255) -> bool *)
  available_endpoint : bool -> Z -> bool (* (in_transfer, endpoint_number 0..15) -> bool *)
}.

(** Mojo UsbControlTransferParams representation produced by Blink *)
Record MojoUsbControlTransferParams : Type := mkMojoControlParams {
  mojo_direction : USBTransferDirection;
  mojo_type      : USBRequestType;
  mojo_recipient : USBRecipient;
  mojo_request   : Z; (* uint8 *)
  mojo_value     : Z; (* uint16 *)
  mojo_index     : Z; (* uint16 *)
  mojo_length    : Z  (* uint16: wLength *)
}.

(** Hardware 8-byte USB 2.0 §9.3 Setup Packet *)
Record USBSetupPacket : Type := mkUSBSetupPacket {
  bmRequestType : list Z; (* 1 byte *)
  bRequest      : list Z; (* 1 byte *)
  wValue        : list Z; (* 2 bytes, little-endian *)
  wIndex        : list Z; (* 2 bytes, little-endian *)
  wLength       : list Z  (* 2 bytes, little-endian *)
}.

(** ** 2. Field Size Constants & Serialization Semantics *)

Definition bmRequestType_size : Z := 1.
Definition bRequest_size      :