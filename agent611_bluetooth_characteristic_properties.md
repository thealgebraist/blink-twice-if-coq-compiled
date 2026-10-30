# Formal Verification Report: Web Bluetooth GATT Characteristic Properties Bitmask Semantics

**Agent**: Formal Verification Agent 611 (Web Hardware & Peripheral Platform APIs)  
**Target Source**: `third_party/blink/renderer/modules/bluetooth/bluetooth_remote_gatt_characteristic.cc`  
**Specification**: W3C Web Bluetooth Specification §4.5 (Characteristic Properties Bitmask)  
**Formal Theory Target**: `BlinkWebBluetoothCharacteristicPropertiesSemantics.v`  

---

## 1. Normative W3C Web Bluetooth Specification Requirements

In the W3C Web Bluetooth Specification, a `BluetoothRemoteGATTCharacteristic` represents a GATT Characteristic, which is a basic data element used to construct a GATT service. Each characteristic exposes a `properties` attribute of interface type `BluetoothCharacteristicProperties`, which wraps the underlying Bluetooth Core Specification Characteristic Properties bitfield (a single-octet bitmask, extended in Web Bluetooth via the Characteristic Extended Properties descriptor).

### 1.1 Characteristic Properties Bitmask (§4.5 & Bluetooth Core Spec Vol 3, Part G, §3.3.1.1)

The characteristic properties bitmask defines how the characteristic's value can be used and how its descriptors can be accessed. The standard bit flags are defined as follows:

| Property Name | Bit Position | Hex Value | Decimal Value | W3C WebIDL Attribute |
| :--- | :--- | :--- | :--- | :--- |
| `Broadcast` | Bit 0 | `0x01` | $1$ | `broadcast` |
| `Read` | Bit 1 | `0x02` | $2$ | `read` |
| `WriteWithoutResponse` | Bit 2 | `0x04` | $4$ | `writeWithoutResponse` |
| `Write` | Bit 3 | `0x08` | $8$ | `write` |
| `Notify` | Bit 4 | `0x10` | $16$ | `notify` |
| `Indicate` | Bit 5 | `0x20` | $32$ | `indicate` |
| `AuthenticatedSignedWrites` | Bit 6 | `0x40` | $64$ | `authenticatedSignedWrites` |
| `ExtendedProperties` | Bit 7 | `0x80` | $128$ | *(Internal flag)* |
| `ReliableWrite` (Extended) | Bit 8 | `0x100` | $256$ | `reliableWrite` |
| `WritableAuxiliaries` (Extended) | Bit 9 | `0x200` | $512$ | `writableAuxiliaries` |

### 1.2 Operational Permission Invariants (§4.4 `BluetoothRemoteGATTCharacteristic`)

Before dispatching any hardware I/O request over Mojo IPC to the browser process (and subsequently the OS Bluetooth stack), the user agent must validate the characteristic's properties bitmask:

1. **`readValue()`**:
   * **Normative step**: "If `this.properties.read` is `false`, return a promise rejected with a `NotSupportedError`."
   * **Bitmask condition**: `(mask & 0x02) != 0`.

2. **`writeValueWithResponse(value)`**:
   * **Normative step**: "If `this.properties.write` is `false`, return a promise rejected with a `NotSupportedError`."
   * **Bitmask condition**: `(mask & 0x08) != 0`.

3. **`writeValueWithoutResponse(value)`**:
   * **Normative step**: "If `this.properties.writeWithoutResponse` is `false`, return a promise rejected with a `NotSupportedError`."
   * **Bitmask condition**: `(mask & 0x04) != 0`.

4. **`writeValue(value)` (Legacy/Deprecated Combined Write)**:
   * **Normative step**: "If neither `this.properties.write` nor `this.properties.writeWithoutResponse` nor `this.properties.authenticatedSignedWrites` is `true`, return a promise rejected with a `NotSupportedError`."
   * **Bitmask condition**: `(mask & (0x08 | 0x04 | 0x40)) != 0`.

5. **`startNotifications()` / `stopNotifications()`**:
   * **Normative step**: "If neither `this.properties.notify` nor `this.properties.indicate` is `true`, return a promise rejected with a `NotSupportedError`."
   * **Bitmask condition**: `(mask & (0x10 | 0x20)) != 0`.

---

## 2. Chromium Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, the GATT characteristic implementation resides in:
* `third_party/blink/renderer/modules/bluetooth/bluetooth_remote_gatt_characteristic.cc`
* `third_party/blink/renderer/modules/bluetooth/bluetooth_characteristic_properties.cc`

### 2.1 Representation in `BluetoothCharacteristicProperties`

When a characteristic is constructed from a `mojom::blink::WebBluetoothRemoteGATTCharacteristicPtr`, the `uint32_t properties` bitfield is passed to `BluetoothCharacteristicProperties::Create(uint32_t properties)`.

In `bluetooth_characteristic_properties.cc`, each boolean property getter computes:

```cpp
bool BluetoothCharacteristicProperties::read() const {
  return properties_ &
         static_cast<uint32_t>(
             mojom::blink::WebBluetoothGATTCharacteristicProperties::kRead);
}
```

### 2.2 Gatekeeping in `BluetoothRemoteGATTCharacteristic`

In `bluetooth_remote_gatt_characteristic.cc`, operations are guarded by synchronous checks prior to Mojo call dispatch (or rejected at the Mojo boundary coupled with renderer checks):

1. **GATT Connection State Check**:
   ```cpp
   if (!GetGatt()->connected()) {
     return ScriptPromise::RejectWithDOMException(
         script_state,
         BluetoothError::CreateNotConnectedException(
             BluetoothOperation::kCharacteristicsRetrieval));
   }
   ```
2. **Bitmask Permission Gate**:
   * For `readValue()`: Checks `if (!properties_->read())` (or delegates to the browser process where `WebBluetoothServiceImpl` enforces `(properties & kRead) != 0`, returning `WebBluetoothResult::GATT_NOT_SUPPORTED`).
   * For `writeValueWithResponse()`: Enforces `properties_->write()`.
   * For `writeValueWithoutResponse()`: Enforces `properties_->writeWithoutResponse()`.
   * For `startNotifications()`: Enforces `properties_->notify() || properties_->indicate()`.

### 2.3 Key Implementation Invariants

* **Invariant 1 (Bitwise Disjointness)**: Every distinct `WebBluetoothGATTCharacteristicProperties` enum constant is a distinct power of two $2^k$, ensuring zero aliasing between permission flags.
* **Invariant 2 (Monotonicity under Bitwise OR)**: Adding capabilities to a bitmask via bitwise OR (`Z.lor`) never revokes an already granted capability.
* **Invariant 3 (Strict Operation Soundness)**: Any GATT operation returning `Ok` (resolving the `ScriptPromise`) strictly implies both `gatt_connected = true` and the corresponding bitmask predicate `has_property(mask, required_prop) = true`.
* **Invariant 4 (Idempotence & Masking Safety)**: Masking out unrelated bits (`Z.land mask (Z.lnot other_prop)`) preserves the permission status of target properties.

---

## 3. Formal Specification & Proofs in Rocq/Coq

Below is the complete, self-contained formalization in `BlinkWebBluetoothCharacteristicPropertiesSemantics.v`. It uses `ZArith`, `Bool`, and `Lia` to model exact fixed-width bitmask arithmetic and operation state transitions.

```coq
(** * BlinkWebBluetoothCharacteristicPropertiesSemantics.v
    Formal verification of W3C Web Bluetooth §4.5 Characteristic Properties Bitmask
    and Chromium Blink BluetoothRemoteGATTCharacteristic operation semantics. *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

Section WebBluetoothCharacteristicProperties.

  (** ** 1. Characteristic Property Bitmask Constants (W3C §4.5) *)

  Definition PROP_NONE                        : Z := 0.
  Definition PROP_BROADCAST                   : Z := 1.   (* 1 << 0 = 0x01 *)
  Definition PROP_READ                        : Z := 2.   (* 1 << 1 = 0x02 *)
  Definition PROP_WRITE_WITHOUT_RESPONSE      : Z := 4.   (* 1 << 2 = 0x04 *)
  Definition PROP_WRITE                       : Z := 8.   (* 1 << 3 = 0x08 *)
  Definition PROP_NOTIFY                      : Z := 16.  (* 1 << 4 = 0x10 *)
  Definition PROP_INDICATE                    : Z := 32.  (* 1 << 5 = 0x20 *)
  Definition PROP_AUTHENTICATED_SIGNED_WRITES : Z := 64.  (* 1 << 6 = 0x40 *)
  Definition PROP_EXTENDED_PROPERTIES         : Z := 128. (* 1 << 7 = 0x80 *)
  Definition PROP_RELIABLE_WRITE              : Z := 256. (* 1 << 8 = 0x100 *)
  Definition PROP_WRITABLE_AUXILIARIES        : Z := 512. (* 1 << 9 = 0x200 *)

  (** Composite masks used by combined operations *)
  Definition MASK_ANY_WRITE : Z :=
    Z.lor (Z.lor PROP_WRITE PROP_WRITE_WITHOUT_RESPONSE)
          PROP_AUTHENTICATED_SIGNED_WRITES.

  Definition MASK_ANY_NOTIFICATION : Z :=
    Z.lor PROP_NOTIFY PROP_INDICATE.

  (** ** 2. Core Mathematical Property: Bitmask Testing *)

  (** Mathematical Property: has_property(mask, prop) = (mask & prop) != 0 *)
  Definition has_property (mask prop : Z) : bool :=
    negb (Z.eqb (Z.land mask prop) 0).

  (** Exact single-bit test equivalence helper *)
  Definition has_bit (mask : Z) (bit_index : Z) : bool :=
    Z.testbit mask bit_index.

  (** ** 3. WebIDL BluetoothCharacteristicProperties Interface Projection *)

  Record CharacteristicPropertiesView : Type := mkPropsView {
    view_broadcast                   : bool;
    view_read                        : bool;
    view_write_without_response      : bool;
    view_write                       : bool;
    view_notify                      : bool;
    view_indicate                    : bool;
    view_authenticated_signed_writes : bool;
    view_reliable_write              : bool;
    view_writable_auxiliaries        : bool
  }.

  Definition project_properties (mask : Z) : CharacteristicPropertiesView :=
    mkPropsView
      (has_property mask PROP_BROADCAST)
      (has_property mask PROP_READ)
      (has_property mask PROP_WRITE_WITHOUT_RESPONSE)
      (has_property mask PROP_WRITE)
      (has_property mask PROP_NOTIFY)
      (has_property mask PROP_INDICATE)
      (has_property mask PROP_AUTHENTICATED_SIGNED_WRITES)
      (has_property mask PROP_RELIABLE_WRITE)
      (has_property mask PROP_WRITABLE_AUXILIARIES).

  (** ** 4. Blink GATT Characteristic State and Operations *)

  Record RemoteGATTCharacteristic : Type := mkCharacteristic {
    gatt_connected : bool;
    properties_mask : Z
  }.

  Inductive GATTOperation : Type :=
    | OpReadValue
    | OpWriteValueWithResponse
    | OpWriteValueWithoutResponse
    | OpWriteValueLegacy
    | OpStartNotifications
    | OpStopNotifications.

  Inductive DOMExceptionCode : Type :=
    | NetworkError       (* GATT server disconnected *)
    | NotSupportedError. (* Operation not permitted by characteristic properties *)

  Inductive OperationResult : Type :=
    | ResultOk
    | ResultReject (err : DOMExceptionCode).

  (** Required property mask for each operation *)
  Definition required_mask_for_op (op : GATTOperation) : Z :=
    match op with
    | OpReadValue                  => PROP_READ
    | OpWriteValueWithResponse     => PROP_WRITE
    | OpWriteValueWithoutResponse  => PROP_WRITE_WITHOUT_RESPONSE
    | OpWriteValueLegacy           => MASK_ANY_WRITE
    | OpStartNotifications         => MASK_ANY_NOTIFICATION
    | OpStopNotifications          => MASK_ANY_NOTIFICATION
    end.

  (** Blink BluetoothRemoteGATTCharacteristic execution semantics *)
  Definition execute_gatt_operation
    (ch : RemoteGATTCharacteristic) (op : GATTOperation) : OperationResult :=
    if negb (gatt_connected ch) then
      ResultReject NetworkError
    else if has_property (properties_mask ch) (required_mask_for_op op) then
      ResultOk
    else
      ResultReject NotSupportedError.

  (** ** 5. Concrete Theorems and Complete Proofs *)

  (** Theorem 1: Fundamental algebraic characterization of [has_property]. *)
  Theorem has_property_spec :
    forall mask prop : Z,
      has_property mask prop = true <-> Z.land mask prop <> 0.
  Proof.
    intros mask prop.
    unfold has_property.
    rewrite negb_true_iff.
    rewrite Z.eqb_neq.
    reflexivity.
  Qed.

  Theorem has_property_false_spec :
    forall mask prop : Z,
      has_property mask prop = false <-> Z.land mask prop = 0.
  Proof.
    intros mask prop.
    unfold has_property.
    rewrite negb_false_iff.
    rewrite Z.eqb_eq.
    reflexivity.
  Qed.

  (** Theorem 2: Zero mask grants no properties. *)
  Theorem empty_mask_has_no_property :
    forall prop : Z,
      has_property PROP_NONE prop = false.
  Proof.
    intros prop.
    unfold has_property, PROP_NONE.
    rewrite Z.land_0_l.
    reflexivity.
  Qed.

  (** Theorem 3: Reflexivity for non-zero property masks. *)
  Theorem has_property_refl :
    forall prop : Z,
      prop <> 0 ->
      has_property prop prop = true.
  Proof.
    intros prop Hneq.
    apply has_property_spec.
    rewrite Z.land_diag.
    exact Hneq.
  Qed.

  (** Theorem 4: Disjointness of standard GATT property flags.
      Setting one standard flag never enables another distinct flag. *)
  Theorem read_write_disjoint :
    has_property PROP_READ PROP_WRITE = false /\
    has_property PROP_WRITE PROP_READ = false /\
    has_property PROP_READ PROP_NOTIFY = false /\
    has_property PROP_WRITE PROP_WRITE_WITHOUT_RESPONSE = false /\
    has_property PROP_NOTIFY PROP_INDICATE = false.
  Proof.
    repeat split; vm_compute; reflexivity.
  Qed