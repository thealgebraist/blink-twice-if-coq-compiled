# Formal Verification Report: WebUSB Endpoint Direction and Transfer Type Classification
**Agent ID:** 615 (Web Hardware & Peripheral Platform APIs)  
**Target Module:** `third_party/blink/renderer/modules/webusb/usb_endpoint.cc`  
**Specifications:** W3C WebUSB API §3.7, Universal Serial Bus Revision 2.0 Specification §9.6.6  
**Formal Theory:** `BlinkWebUSBEndpointDirectionSemantics.v`  

---

## 1. Normative Specification Requirements

### 1.1 Universal Serial Bus Revision 2.0 Specification (§9.6.6)
In the USB 2.0 Hardware Specification, Section 9.6.6 defines the **Standard Endpoint Descriptor** (`bDescriptorType = 0x05`). Two bitfields within this descriptor govern endpoint addressing, data flow direction, and transfer semantics:

1. **`bEndpointAddress` (Offset 2, 1 Byte / `uint8_t`):**
   * **Bits 3..0 (`0x0F`):** The endpoint number (`0` through `15`).
   * **Bits 6..4 (`0x70`):** Reserved, reset to zero.
   * **Bit 7 (`0x80`):** Direction. Ignored for control endpoints (`00b` in `bmAttributes`).
     * `0` = `OUT` endpoint (Host-to-Device).
     * `1` = `IN` endpoint (Device-to-Host).

2. **`bmAttributes` (Offset 3, 1 Byte / `uint8_t`):**
   * **Bits 1..0 (`0x03`):** Transfer Type.
     * `00b` (`0`) = Control
     * `01b` (`1`) = Isochronous
     * `10b` (`2`) = Bulk
     * `11b` (`3`) = Interrupt
   * **Bits 3..2 (`0x0C`):** Synchronization Type (Isochronous only).
   * **Bits 5..4 (`0x30`):** Usage Type (Isochronous / Interrupt in USB 3.0).
   * **Bits 7..6 (`0xC0`):** Reserved, must be zero.

### 1.2 W3C WebUSB API Specification (§3.7 `USBEndpoint`)
The W3C WebUSB API specification exposes hardware endpoint descriptors to the ECMAScript execution environment via the `USBEndpoint` interface:

```webidl
enum USBSDirection {
  "in",
  "out"
};

enum USBEndpointType {
  "bulk",
  "interrupt",
  "isochronous"
};

[
  Exposed=(DedicatedWorker,SharedWorker,Window),
  SecureContext
]
interface USBEndpoint {
  constructor(USBAlternateInterface alternate, octet endpointNumber, USBSDirection direction);
  readonly attribute octet endpointNumber;
  readonly attribute USBSDirection direction;
  readonly attribute USBEndpointType type;
  readonly attribute unsigned long packetSize;
};
```

#### Normative Invariants:
1. **Endpoint Number Domain:** For non-control endpoints exposed via `USBEndpoint`, `endpointNumber` MUST be an integer in the closed interval $[1, 15]$, corresponding to `bEndpointAddress & 0x0F`. (Endpoint `0` is the default control pipe, managed implicitly via `controlTransferIn` / `controlTransferOut` on `USBDevice` rather than as an explicit `USBEndpoint` instance).
2. **Direction Mapping:** The `direction` attribute MUST evaluate to `"in"` if and only if bit 7 of `bEndpointAddress` is `1` (`(bEndpointAddress & 0x80) != 0`), and `"out"` if and only if bit 7 is `0`.
3. **Address Reconstruction:** Given an `endpointNumber` $n \in [1, 15]$ and `direction` $d \in \{\text{"in"}, \text{"out"}\}$, the reconstructed wire-format `bEndpointAddress` is:
   $$\text{addr}(n, d) = n \lor \begin{cases} \text{0x80} & \text{if } d = \text{"in"} \\ \text{0x00} & \text{if } d = \text{"out"} \end{cases}$$
4. **Transfer Type Exclusivity:** The `USBEndpoint` interface represents unidirectional data pipes (`"bulk"`, `"interrupt"`, `"isochronous"`). Bidirectional `"control"` endpoints (`bmAttributes & 0x03 == 0`) MUST NOT be instantiated as `USBEndpoint` objects.

---

## 2. Chromium Blink Implementation Analysis

### 2.1 Source Architecture: `third_party/blink/renderer/modules/webusb/usb_endpoint.cc`
In Chromium's Blink rendering engine, hardware descriptors are parsed by the browser process (`services/device/usb/`) into Mojo structures (`device::mojom::blink::UsbEndpointInfo`) and serialized over IPC to the renderer process.

Inside `third_party/blink/renderer/modules/webusb/usb_endpoint.cc`, `USBEndpoint` translates between Mojo enums, WebIDL strings/enums (`V8USBDirection`, `V8USBEndpointType`), and raw USB protocol values:

```cpp
// Conceptual / structural representation of third_party/blink/renderer/modules/webusb/usb_endpoint.cc

namespace blink {

namespace {

V8USBDirection::Enum ConvertDirectionToEnum(
    const device::mojom::blink::UsbTransferDirection& direction) {
  switch (direction) {
    case device::mojom::blink::UsbTransferDirection::INBOUND:
      return V8USBDirection::Enum::kIn;
    case device::mojom::blink::UsbTransferDirection::OUTBOUND:
      return V8USBDirection::Enum::kOut;
  }
  NOTREACHED();
}

V8USBEndpointType::Enum ConvertTypeToEnum(
    const device::mojom::blink::UsbTransferType& type) {
  switch (type) {
    case device::mojom::blink::UsbTransferType::BULK:
      return V8USBEndpointType::Enum::kBulk;
    case device::mojom::blink::UsbTransferType::INTERRUPT:
      return V8USBEndpointType::Enum::kInterrupt;
    case device::mojom::blink::UsbTransferType::ISOCHRONOUS:
      return V8USBEndpointType::Enum::kIsochronous;
    case device::mojom::blink::UsbTransferType::CONTROL:
      // Control endpoints are filtered out during descriptor parsing
      // and must never reach USBEndpoint construction.
      NOTREACHED();
  }
  NOTREACHED();
}

}  // namespace

USBEndpoint* USBEndpoint::Create(const USBAlternateInterface* alternate,
                                 wtf_size_t endpoint_index) {
  return MakeGarbageCollected<USBEndpoint>(alternate, endpoint_index);
}

// WebIDL Constructor: new USBEndpoint(alternate, endpointNumber, direction)
USBEndpoint* USBEndpoint::Create(const USBAlternateInterface* alternate,
                                 uint8_t endpoint_number,
                                 const V8USBDirection& direction,
                                 ExceptionState& exception_state) {
  auto mojo_direction = direction == V8USBDirection::Enum::kIn
                            ? device::mojom::blink::UsbTransferDirection::INBOUND
                            : device::mojom::blink::UsbTransferDirection::OUTBOUND;
  const auto& endpoints = alternate->Info().endpoints;
  for (wtf_size_t i = 0; i < endpoints.size(); ++i) {
    const auto& ep = endpoints[i];
    if (ep->endpoint_number == endpoint_number &&
        ep->direction == mojo_direction) {
      return USBEndpoint::Create(alternate, i);
    }
  }
  exception_state.ThrowRangeError(
      "The specified endpoint does not exist on the alternate interface.");
  return nullptr;
}
```

### 2.2 Lower-Layer Mojo Deserialization (`services/device/usb/usb_descriptors.cc`)
The Mojo `UsbEndpointInfo` struct populated from the raw USB descriptor bytes enforces the bitwise extraction:

```cpp
// In UsbEndpointDescriptor::Parse(const std::vector<uint8_t>& data)
uint8_t bEndpointAddress = data[2];
uint8_t bmAttributes = data[3];

endpoint_number = bEndpointAddress & 0x0F;
direction = (bEndpointAddress & 0x80) != 0
                ? mojom::UsbTransferDirection::INBOUND
                : mojom::UsbTransferDirection::OUTBOUND;

switch (bmAttributes & 0x03) {
  case 0x00: transfer_type = mojom::UsbTransferType::CONTROL; break;
  case 0x01: transfer_type = mojom::UsbTransferType::ISOCHRONOUS; break;
  case 0x02: transfer_type = mojom::UsbTransferType::BULK; break;
  case 0x03: transfer_type = mojom::UsbTransferType::INTERRUPT; break;
}
```

### 2.3 Critical Implementation Invariants
1. **Bitwise Orthogonality:** Bit 7 (`0x80`, direction) and Bits 3..0 (`0x0F`, endpoint number) have disjoint bitmasks (`0x80 & 0x0F == 0x00`). Modifying or extracting the direction never aliases or corrupts the endpoint number, and vice versa.
2. **Canonical Address Bijection:** For all canonical endpoint addresses where reserved bits 6..4 are cleared (`(addr & 0x70) == 0`), the pair `(endpoint_number(addr), endpoint_dir(addr))` forms a strict bijection with the byte `addr`.
3. **Total Classification:** Every 8-bit `bEndpointAddress` maps deterministically to `In` (`>= 128`) or `Out` (`< 128` when masked with `0x70 == 0`), and every `bmAttributes` byte maps deterministically to one of the 4 hardware transfer types, with WebUSB admitting exactly the 3 non-control types (`bmAttributes & 0x03 != 0`).

---

## 3. Formal Specification & Verification in Rocq (Coq)

Below is the complete, self-contained, and admitted-free Rocq formalization `BlinkWebUSBEndpointDirectionSemantics.v`. It models the bitwise semantics over `Z` (using `ZArith` and `Lia`), establishes the hardware-to-Blink translation layers, and proves all structural invariants.

```coq
(** * BlinkWebUSBEndpointDirectionSemantics.v
    Formal Verification of WebUSB Endpoint Direction and Transfer Type Classification
    Target: third_party/blink/renderer/modules/webusb/usb_endpoint.cc
    Specs:  W3C WebUSB API §3.7, USB 2.0 Specification §9.6.6
    Agent:  615 (Web Hardware & Peripheral Platform APIs)
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micromega.Lia.
From Coq Require Import Lists.List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Hardware & WebIDL Domain Definitions *)

(** W3C WebUSB §3.7 USBSDirection / device::mojom::UsbTransferDirection *)
Inductive USBDirection : Type :=
  | Out : USBDirection (* Bit 7 = 0 : Host-to-Device (OUTBOUND) *)
  | In  : USBDirection (* Bit 7 = 1 : Device-to-Host (INBOUND)  *).

Scheme Equality for USBDirection.

(** USB 2.0 §9.6.6 bmAttributes[1:0] Hardware Transfer Types *)
Inductive USBHardwareTransferType : Type :=
  | HW_Control     : USBHardwareTransferType (* 00b = 0 *)
  | HW_Isochronous : USBHardwareTransferType (* 01b = 1 *)
  | HW_Bulk        : USBHardwareTransferType (* 10b = 2 *)
  | HW_Interrupt   : USBHardwareTransferType (* 11b = 3 *).

Scheme Equality for USBHardwareTransferType.

(** W3C WebUSB §3.7 USBEndpointType (Excludes Control endpoints) *)
Inductive WebUSBEndpointType : Type :=
  | Web_Bulk        : WebUSBEndpointType
  | Web_Interrupt   : WebUSBEndpointType
  | Web_Isochronous : WebUSBEndpointType.

Scheme Equality for WebUSBEndpointType.

(** ** 2. Bitwise Protocol Constants & Validity Predicates *)

Definition MASK_DIRECTION       : Z := 128. (* 0x80 : Bit 7 *)
Definition MASK_RESERVED_ADDR   : Z := 112. (* 0x70 : Bits 6..4 *)
Definition MASK_ENDPOINT_NUMBER : Z := 15.  (* 0x0F : Bits 3..0 *)
Definition MASK_TRANSFER_TYPE   : Z := 3.   (* 0x03 : Bits 1..0 *)

(** Valid uint8_t octet in [0, 255] *)
Definition is_uint8 (b : Z) : Prop :=
  0 <= b < 256.

(** Valid endpoint number in [0, 15] (4-bit nibble) *)
Definition is_valid_ep_num (n : Z) : Prop :=
  0 <= n < 16.

(** Valid WebUSB non-zero endpoint number in [1, 15] *)
Definition is_webusb_ep_num (n : Z) : Prop :=
  1 <= n < 16.

(** Canonical USB 2.0 §9.6.6 bEndpointAddress has reserved bits 6..4 set to 0 *)
Definition is_canonical_addr (addr : Z) : Prop :=
  is_uint8 addr /\ Z.land addr MASK_RESERVED_ADDR = 0.

(** ** 3. Functional Specification of Blink & USB Descriptors *)

(** Core Mathematical Property:
    endpoint_dir(addr) = if (addr & 0x80) != 0 then In else Out *)
Definition endpoint_dirb (addr : Z) : bool :=
  negb (Z.eqb (Z.land addr MASK_DIRECTION) 0).

Definition endpoint_dir (addr : Z) : USBDirection :=
  if endpoint_dirb addr then In else Out.

(** Extract endpoint number: addr & 0x0F *)
Definition endpoint_num (addr : Z) : Z :=
  Z.land addr MASK_ENDPOINT_NUMBER.

(** Reconstruct wire-format bEndpointAddress from endpoint number and direction *)
Definition encode_endpoint_addr (ep_num : Z) (dir : USBDirection) : Z :=
  let dir_bit := match dir with
                 | In  => MASK_DIRECTION
                 | Out => 0
                 end in
  Z.lor (Z.land ep_num MASK_ENDPOINT_NUMBER) dir_bit.

(** Decode hardware transfer type from bmAttributes (bits 1..0) *)
Definition decode_hw_transfer_type (bmAttributes : Z) : USBHardwareTransferType :=
  let bits := Z.land bmAttributes MASK