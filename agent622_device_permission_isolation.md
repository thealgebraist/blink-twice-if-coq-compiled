# Formal Verification Report: Peripheral Device Access Permission Isolation per Origin

**Agent**: Formal Verification Agent 622 (Web Hardware & Peripheral Platform APIs)  
**Topic**: Peripheral Device Access Permission Isolation per Origin  
**Chromium Target**: `third_party/blink/renderer/modules/permissions/permission_utils.cc`  
**Specifications**: W3C Permissions API §4, WebUSB §3, Web Bluetooth §4, WebHID §4, Web Serial §3  
**Formal Theory Target**: `BlinkWebDevicePermissionIsolationSemantics.v`  

---

## 1. Normative W3C Specification Requirements

Web Hardware and Peripheral Platform APIs expose low-level hardware communication buses (USB, Bluetooth GATT, HID reports, RS-232/UART serial lines) directly to JavaScript execution contexts. Because hardware peripherals rarely implement origin-aware authentication or session isolation in firmware, the browser engine must strictly isolate device access permissions by web origin (RFC 6454 / WHATWG URL Standard).

### 1.1 W3C Permissions API (§4 Permission Store & Permission Key)
Under the W3C Permissions API specification:
1. **Permission Store Keying**: All permission states stored in the User Agent's permission store are indexed by a *permission store key*. Unless explicitly overridden by a powerful feature specification, the permission store key is a tuple of `(top-level origin, embedding origin)` or strictly the `environment settings object's origin`.
2. **Non-Transitivity Across Origins**: Granting a permission descriptor $D$ in context of origin $O_1$ mutates only entries keyed by $O_1$. Querying or requesting permission for $D$ under $O_2$ where $O_1 \neq O_2$ evaluates against an independent permission store entry.

### 1.2 WebUSB Specification (§3 Permissions & Device Enumeration)
In the W3C WebUSB specification:
1. **`AllowedUSBDevice` Records**: Permission to access a physical USB peripheral (identified by `vendorId`, `productId`, and `serialNumber`) is stored in an `AllowedUSBDevice` record bound inside a per-origin `usb-devices` permission storage slot.
2. **`navigator.usb.getDevices()` Isolation**: When invoked in an execution context with origin $O$, the method returns only the intersection of currently attached physical USB devices and the `AllowedUSBDevice` list associated with $O$.
3. **Opaque Origin Rejection**: If the execution context's origin is an *opaque origin* (e.g., sandboxed `iframe` without `allow-same-origin` or `data:` URLs), device permission requests and queries unconditionally fail with a `SecurityError` or return `"denied"`.

### 1.3 Web Bluetooth Specification (§4 Privacy and Security / Device Access)
In the W3C Web Bluetooth specification:
1. **Per-Origin `AllowedBluetoothDevice` Map**: Each origin has an isolated `AllowedBluetoothDevice` map. Furthermore, the `BluetoothDevice.id` attribute is a generated 128-bit pseudonymous identifier seeded uniquely per `(origin, physical_MAC_address)` pair to prevent cross-origin device fingerprinting.
2. **GATT Access Isolation**: Calling `device.gatt.connect()` verifies that the current origin's `AllowedBluetoothDevice` map contains an active entry for that device with `mayUseGATT == true`.

### 1.4 WebHID & Web Serial Specifications
Both WebHID and Web Serial enforce identical invariants:
* Device permissions granted via `requestDevice()` (WebHID) or `requestPort()` (Web Serial) bind the hardware device identifier (VID/PID/Serial or system device path) strictly to `(requesting_origin, embedding_origin)`.
* Cross-origin frames cannot inherit device handles without explicit Permissions Policy delegation (`usb`, `bluetooth`, `hid`, `serial`), and even with delegation, permission state remains partitioned by the origin key.

---

## 2. Chromium Blink Implementation & Invariants

In Chromium, permission descriptor parsing, validation, and Mojo IPC marshaling between Blink (`renderer/modules/permissions/`) and the Browser process (`content/browser/permissions/` and `chrome/browser/usb/`, `bluetooth/`, etc.) are mediated by `third_party/blink/renderer/modules/permissions/permission_utils.cc`.

### 2.1 Architectural Flow in `permission_utils.cc`

1. **Descriptor Creation (`CreatePermissionDescriptor` / `ParsePermissionDescriptor`)**:
   `permission_utils.cc` translates WebIDL `PermissionDescriptor` dictionaries (such as `BluetoothPermissionDescriptor`, `UsbPermissionDescriptor`, `HidPermissionDescriptor`, `SerialPermissionDescriptor`) into `mojom::blink::PermissionDescriptorPtr` structures.
   ```cpp
   // Conceptual structure in permission_utils.cc
   mojom::blink::PermissionDescriptorPtr CreatePermissionDescriptor(
       mojom::blink::PermissionName name) {
     auto descriptor = mojom::blink::PermissionDescriptor::New();
     descriptor->name = name;
     return descriptor;
   }
   ```
2. **Execution Context Origin Binding**:
   Blink never permits JavaScript to pass an arbitrary origin string in a `PermissionDescriptor`. Instead, when `Permissions::query()`, `USB::getDevices()`, or `USB::requestDevice()` executes, Blink resolves the `ExecutionContext*` to its `SecurityOrigin*` (`execution_context->GetSecurityOrigin()`).
3. **Opaque Origin Fast-Path Denial**:
   Before crossing the Mojo boundary or within the permission service proxy connected to the `ExecutionContext`'s `BrowserInterfaceBroker`, opaque origins (`security_origin->IsOpaque()`) are rejected. An opaque origin cannot match any another origin (not even another opaque origin, unless identical by pointer/nonce, and for hardware APIs, opaque origins are forbidden from holding device grants altogether).
4. **Browser-Side Enforcement via Mojo Receiver**:
   The Mojo remote `mojom::blink::PermissionService` and device-specific managers (`mojom::blink::WebUsbService`, `mojom::blink::WebBluetoothService`) are bound in the browser process to a specific `RenderFrameHostImpl`. The browser extracts `render_frame_host->GetLastCommittedOrigin()` and pairs it with the `PermissionDescriptorPtr` constructed by `permission_utils.cc`.

### 2.2 Key Implementation Invariants

* **Invariant 1 (No Cross-Origin Grant Leakage)**: Granting permission for device $d$ on hardware bus $b$ to origin $O_1$ updates the permission map solely at key $(O_1, b, d)$. For any $O_2 \neq O_1$, the permission state at $(O_2, b, d)$ remains invariant (`===` before and after the grant).
* **Invariant 2 (Opaque Origin Disqualification)**: If `IsOpaque(O) == true`, `has_permission(state, d, O)` evaluates to `false` regardless of the contents of the underlying permission store.
* **Invariant 3 (Non-Implication of Distinct Origins)**: For any two distinct origins $O_1 \neq O_2$, the proposition `has_permission(state, d, O1)` does not entail `has_permission(state, d, O2)`. Specifically, there exists a reachable browser permission state where $O_1$ holds permission for $d$ and $O_2$ does not.
* **Invariant 4 (Cross-Origin Revocation Independence)**: Revoking permission for device $d$ from origin $O_1$ preserves any existing permission for device $d$ held by origin $O_2$ ($O_1 \neq O_2$).

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkWebDevicePermissionIsolationSemantics.v`. It models web origins (both tuple origins and opaque origins with nonces), hardware peripheral buses, physical device identifiers, permission states, and Blink/Browser state transition operations (`grant_device_permission`, `revoke_device_permission`, `has_permission`).

## 4. Concrete Theorems and Complete Admitted-Free Proofs

```coq
(** * BlinkWebDevicePermissionIsolationSemantics.v
    Formal Verification of Peripheral Device Access Permission Isolation per Origin
    in Chromium Blink (third_party/blink/renderer/modules/permissions/permission_utils.cc)
    and W3C Permissions / WebUSB / WebBluetooth / WebHID / WebSerial Specifications.
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micromega.Lia.
From Coq Require Import Lists.List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Hardware Buses and Peripheral Device Identifiers *)

Inductive HardwareBus : Type :=
  | Bus_WebUSB : HardwareBus
  | Bus_WebBluetooth : HardwareBus
  | Bus_WebHID : HardwareBus
  | Bus_WebSerial : HardwareBus.

Definition hardware_bus_eqb (b1 b2 : HardwareBus) : bool :=
  match b1, b2 with
  | Bus_WebUSB, Bus_WebUSB => true
  | Bus_WebBluetooth, Bus_WebBluetooth => true
  | Bus_WebHID, Bus_WebHID => true
  | Bus_WebSerial, Bus_WebSerial => true
  | _, _ => false
  end.

Lemma hardware_bus_eqb_spec : forall b1 b2 : HardwareBus,
  hardware_bus_eqb b1 b2 = true <-> b1 = b2.
Proof.
  intros b1 b2; destruct b1, b2; simpl; split; intro H; try reflexivity; try discriminate.
Qed.

(** A physical device descriptor modeled with bus type, vendor ID, product ID,
    and unique hardware serial/MAC identifier. *)
Record PeripheralDevice : Type := mkDevice {
  dev_bus : HardwareBus;
  dev_vendor_id : Z;
  dev_product_id : Z;
  dev_serial_id : Z
}.

Definition device_eqb (d1 d2 : PeripheralDevice) : bool :=
  hardware_bus_eqb (dev_bus d1) (dev_bus d2) &&
  Z.eqb (dev_vendor_id d1) (dev_vendor_id d2) &&
  Z.eqb (dev_product_id d1) (dev_product_id d2) &&
  Z.eqb (dev_serial_id d1) (dev_serial_id d2).

Lemma device_eqb_refl : forall d : PeripheralDevice,
  device_eqb d d = true.
Proof.
  intros [b v p s]; unfold device_eqb; simpl.
  destruct b; simpl; repeat rewrite Z.eqb_refl; reflexivity.
Qed.

Lemma device_eqb_spec : forall d1 d2 : PeripheralDevice,
  device_eqb d1 d2 = true <-> d1 = d2.
Proof.
  intros [b1 v1 p1 s1] [b2 v2 p2 s2]; unfold device_eqb; simpl.
  rewrite !andb_true_iff.
  rewrite hardware_bus_eqb_spec.
  rewrite !Z.eqb_eq.
  split.
  - intros [[[Hb Hv] Hp] Hs]; subst; reflexivity.
  - intro H; inversion H; subst; repeat split; reflexivity.
Qed.

Lemma device_eqb_neq : forall d1 d2 : PeripheralDevice,
  d1 <> d2 -> device_eqb d1 d2 = false.
Proof.
  intros d1 d2 Hneq.
  destruct (device_eqb d1 d2) eqn:Heq; [|reflexivity].
  apply device_eqb_spec in Heq.
  contradiction.
Qed.

(** ** 2. Web Origins (WHATWG URL / RFC 6454 / Blink SecurityOrigin) *)

(** An Origin is either a standard tuple origin (scheme, host, port)
    requiring a secure context (HTTPS/WSS/localhost) or an Opaque origin
    identified by an internal capability nonce. *)
Inductive Origin : Type :=
  | TupleOrigin (scheme_id : Z) (host_id : Z) (port : Z) (is_secure_context : bool)
  | OpaqueOrigin (nonce : Z).

Definition origin_eqb (o1 o2 : Origin) : bool :=
  match o1, o2 with
  | TupleOrigin s1 h1 p1 sec1, TupleOrigin s2 h2 p2 sec2 =>
      Z.eqb s1 s2 && Z.eqb h1 h2 && Z.eqb p1 p2 && Bool.eqb sec1 sec2
  | OpaqueOrigin n1, OpaqueOrigin n2 =>
      Z.eqb n1 n2
  | _, _ => false
  end.

Lemma origin_eqb_refl : forall o : Origin,
  origin_eqb o o = true.
Proof.
  intros [s h p sec | n]; simpl.
  - rewrite !Z.eqb_refl, Bool.eqb_reflx; reflexivity.
  - rewrite Z.eqb_refl; reflexivity.
Qed.

Lemma origin_eqb_spec : forall o1 o2 : Origin,
  origin_eqb o1 o2 = true <-> o1 = o2.
Proof.
  intros [s1 h1 p1 sec1 | n1] [s2 h2 p2 sec2 | n2]; simpl.
  - rewrite !andb_true_iff, !Z.eqb_eq, Bool.eqb_true_iff.
    split.
    + intros [[[Hs Hh] Hp] Hsec]; subst; reflexivity.
    + intro H; inversion H; subst; repeat split; reflexivity.
  - split; intro H; discriminate.
  - split; intro H; discriminate.
  - rewrite Z.eqb_eq; split; intro H; subst; try reflexivity.
    inversion H; reflexivity.
Qed.

Lemma origin_eqb_neq : forall o1 o2 : Origin,
  o1 <> o2 -> origin_eqb o1 o2 = false.
Proof.
  intros o1 o2 Hneq.
  destruct (origin_eqb o1 o2) eqn:Heq; [|reflexivity].
  apply origin_eqb_spec in Heq; contradiction.
Qed.

(** Blink SecurityOrigin::IsOpaque and SecureContext checks for Web Hardware APIs *)
Definition is_opaque_origin (o : Origin) : bool :=
  match o with
  | TupleOrigin _ _ _ _ => false
  | OpaqueOrigin _ => true
  end.

Definition is_eligible_hardware_origin (o : Origin) : bool :=
  match o with
  | TupleOrigin _ _ _ sec => sec
  | OpaqueOrigin _ => false
  end.

(** ** 3. W3C Permission State and Blink Permission Store *)

Inductive PermissionStatus : Type :=
  | Perm_Granted : PermissionStatus
  | Perm_Denied  : PermissionStatus
  | Perm_Prompt  : PermissionStatus.

Record PermissionEntry : Type := mkPermEntry {
  pe_origin : Origin;
  pe_device : PeripheralDevice;
  pe_status : PermissionStatus
}.

Definition PermissionStore : Type := list PermissionEntry.

(** Lookup permission status in the store for a specific (Origin, PeripheralDevice) key.
    Defaults to Perm_Prompt if not explicitly recorded. *)
Fixpoint lookup_store_status (store : PermissionStore) (d : PeripheralDevice) (o : Origin) : PermissionStatus :=
  match store with
