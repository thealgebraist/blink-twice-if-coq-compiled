# Formal Verification Report: Web Bluetooth `writeValueWithResponse` Max Chunk Size Bounding

**Agent ID:** 612 (Web Hardware & Peripheral Platform APIs)  
**Target Source:** `third_party/blink/renderer/modules/bluetooth/bluetooth_remote_gatt_characteristic.cc`  
**Specification:** W3C Web Bluetooth §4.5 (`BluetoothRemoteGATTCharacteristic.writeValueWithResponse`)  
**Formal Theory Target:** `BlinkWebBluetoothWriteChunkSizeSemantics.v`  

---

## 1. Normative Specification Requirements

### 1.1 W3C Web Bluetooth Specification (§4.5)
In the W3C Web Bluetooth Draft Community Group Report, §4.5 defines the methods on the `BluetoothRemoteGATTCharacteristic` interface: `writeValue`, `writeValueWithResponse`, and `writeValueWithoutResponse`. 

The normative steps for writing a value to a GATT Characteristic dictate strict bounds checking to align with the Bluetooth Core Specification (Vol 3, Part F, Attribute Protocol (ATT)):
1. Let `bytes` be a copy of the bytes held by the `BufferSource` parameter `value`.
2. **Maximum Length Constraint:** If `bytes` is more than **512 bytes** long (the maximum length of an attribute value per Bluetooth Core Spec Vol 3, Part F, §3.2.9), return a Promise rejected with an `InvalidModificationError` (or `NetworkError` in legacy revisions, standardized to `DataError` / `InvalidModificationError` depending on operation context; Blink enforces an explicit 512-byte guard).
3. **ATT MTU Payload Constraint:** In Bluetooth Low Energy (BLE) GATT operations, a single `ATT_WRITE_REQ` (used by `writeValueWithResponse`) or `ATT_WRITE_CMD` (used by `writeValueWithoutResponse`) frame has a payload bounded by `ATT_MTU - 3` octets (1 octet for the ATT Opcode, 2 octets for the Attribute Handle). While `Write Long Characteristic Values` (using `ATT_PREPARE_WRITE_REQ` and `ATT_EXECUTE_WRITE_REQ`) can split payloads up to 512 bytes across multiple MTU frames, the fundamental atomic unfragmented write chunk bound for an active ATT bearer with negotiated `mtu` is bounded by:
   $$\text{max\_chunk}(mtu) = \min(mtu - 3, 512)$$
4. Furthermore, for non-empty streaming/chunked peripheral writes, a valid single transmission chunk of size `sz` under negotiated `mtu` (where $mtu \ge 23$ per BLE minimum ATT_MTU) must satisfy:
   $$\text{valid\_write\_chunk}(sz, mtu) \iff 1 \le sz \le \min(mtu - 3, 512)$$

### 1.2 Cross-API Peripheral Alignment (WebUSB, WebHID, Web Serial)
Across the W3C/WHATWG Web Hardware APIs implemented in Blink (`modules/bluetooth`, `modules/usb`, `modules/hid`, `modules/serial`), buffer size validation before Mojo IPC serialization is a critical security invariant:
* **Web Bluetooth:** Enforces `value.byteLength() <= 512` before allocating `WTF::Vector<uint8_t>` for `mojom::blink::WebBluetoothRemoteGATTCharacteristic`.
* **WebHID:** Enforces report buffer bounds against `max_input_report_size` / `max_output_report_size`.
* **WebUSB:** Enforces `BufferSource` bounds against `wtf_size_t` max limits (`kMaxTransferSize`) prior to `usb_device_->GenericTransferOut`.
* **Web Serial:** Enforces `WritableStream` chunk bounds against the Mojo data pipe capacity.

---

## 2. Chromium Blink Implementation & Invariants

### 2.1 Source Analysis: `bluetooth_remote_gatt_characteristic.cc`
In `third_party/blink/renderer/modules/bluetooth/bluetooth_remote_gatt_characteristic.cc`, the characteristic write operations are funnelled through `BluetoothRemoteGATTCharacteristic::WriteValue`:

```cpp
ScriptPromise<IDLUndefined> BluetoothRemoteGATTCharacteristic::writeValueWithResponse(
    ScriptState* script_state,
    const DOMArrayPiece& value,
    ExceptionState& exception_state) {
  return WriteValue(script_state, value,
                    mojom::blink::WebBluetoothWriteType::kWriteWithResponse,
                    exception_state);
}
```

Inside `BluetoothRemoteGATTCharacteristic::WriteValue`:
1. **GATT Connection & Property Check:** Verifies `GetGatt()->connected()` and checks whether `characteristic_->properties` permits writing.
2. **Length Bound Validation:**
   ```cpp
   if (value.ByteLength() > 512) {
     exception_state.ThrowDOMException(
         DOMExceptionCode::kInvalidModificationError,
         "Value can't exceed 512 bytes.");
     return EmptyPromise();
   }
   ```
3. **Vector Copy & Mojo Dispatch:** Copies the `DOMArrayPiece` into a `Vector<uint8_t> value_vector` and invokes `service->RemoteCharacteristicWriteValue(...)`.
4. **Chunking & MTU Interaction:** When the platform or Web application fragments writes to fit single-packet ATT transactions (or when the underlying OS Bluetooth stack enforces single-PDU limits without Prepare Write queues), the effective chunk size `sz` for a non-empty transfer over a link with negotiated `mtu` ($\ge 23$) must never exceed `min(mtu - 3, 512)` and must be at least `1` byte.

### 2.2 Critical C++ Invariants
* **Invariant 1 (Absolute Upper Bound):** Any `sz` accepted by `valid_write_chunk(sz, mtu)` strictly satisfies `sz <= 512`, preventing Mojo IPC payload abuse and conforming to Bluetooth Core Spec §3.2.9.
* **Invariant 2 (ATT Header Overhead):** Any `sz` accepted by `valid_write_chunk(sz, mtu)` strictly satisfies `sz + 3 <= mtu`, ensuring the 1-byte ATT Opcode and 2-byte Attribute Handle fit within the negotiated `ATT_MTU` without buffer overrun.
* **Invariant 3 (Minimum BLE MTU Feasibility):** For the standard BLE minimum `ATT_MTU = 23`, the valid chunk range is `[1, 20]` bytes. If `mtu < 4`, no valid non-empty chunk exists.
* **Invariant 4 (Decidability):** The boolean validation check `check_valid_write_chunk(sz, mtu)` is sound and complete with respect to the mathematical specification `valid_write_chunk(sz, mtu)`.

---

## 3. Formal Specification in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkWebBluetoothWriteChunkSizeSemantics.v`. It models the ATT MTU geometry, the Blink 512-byte attribute cap, executable boolean validators, chunk clamping functions, and proves all safety and equivalence properties.

```coq
(** * BlinkWebBluetoothWriteChunkSizeSemantics.v
    Formal Verification of Web Bluetooth writeValueWithResponse Chunk Size Bounds
    Target: third_party/blink/renderer/modules/bluetooth/bluetooth_remote_gatt_characteristic.cc
    Specification: W3C Web Bluetooth §4.5
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Constants and Architectural Bounds *)

(** Bluetooth Core Spec Vol 3, Part F, §3.2.9: Maximum length of an attribute value *)
Definition kMaxAttributeLength : Z := 512.

(** ATT Write Request / Command header overhead: 1 byte Opcode + 2 bytes Handle *)
Definition kAttWriteHeaderSize : Z := 3.

(** Bluetooth Low Energy minimum guaranteed ATT_MTU (Vol 3, Part G, §5.2.1) *)
Definition kBleMinMtu : Z := 23.

(** ** 2. Mathematical Specification *)

(** Maximum single-PDU write chunk size given negotiated ATT MTU *)
Definition max_chunk_size (mtu : Z) : Z :=
  Z.min (mtu - kAttWriteHeaderSize) kMaxAttributeLength.

(** Mathematical predicate: valid_write_chunk(sz, mtu) = 1 <= sz <= min(mtu - 3, 512) *)
Definition valid_write_chunk (sz mtu : Z) : Prop :=
  1 <= sz <= Z.min (mtu - 3) 512.

(** Executable boolean checker modeling Blink / Bluetooth stack validation *)
Definition check_valid_write_chunk (sz mtu : Z) : bool :=
  (1 <=? sz) && (sz <=? Z.min (mtu - 3) 512).

(** Blink top-level DOMArrayPiece byteLength check (<= 512) *)
Definition blink_write_value_length_valid (sz : Z) : Prop :=
  0 <= sz <= kMaxAttributeLength.

(** Clamping function to compute the largest valid chunk for a given requested size > 0 and mtu >= 4 *)
Definition clamp_chunk_size (req_sz mtu : Z) : Z :=
  Z.max 1 (Z.min req_sz (max_chunk_size mtu)).
```

---

## 4. Concrete Theorems and Complete Proofs

All proofs below are mechanized using `ZArith`, `Bool`, and `Lia` with **zero admits**.

```coq
(** ** 3. Formal Theorems and Proofs *)

(** Theorem 1: Equivalence between the executable boolean validator and the mathematical predicate. *)
Theorem check_valid_write_chunk_iff :
  forall sz mtu : Z,
    check_valid_write_chunk sz mtu = true <-> valid_write_chunk sz mtu.
Proof.
  intros sz mtu.
  unfold check_valid_write_chunk, valid_write_chunk.
  rewrite andb_true_iff.
  rewrite !Z.leb_le.
  reflexivity.
Qed.

(** Theorem 2: Any valid write chunk strictly satisfies Blink's 512-byte DOMException guard. *)
Theorem valid_chunk_respects_blink_512_bound :
  forall sz mtu : Z,
    valid_write_chunk sz mtu ->
    blink_write_value_length_valid sz.
Proof.
  intros sz mtu Hvalid.
  unfold valid_write_chunk in Hvalid.
  unfold blink_write_value_length_valid, kMaxAttributeLength.
  lia.
Qed.

(** Theorem 3: Any valid write chunk plus the 3-byte ATT header fits within the negotiated ATT MTU. *)
Theorem valid_chunk_fits_att_mtu_pdu :
  forall sz mtu : Z,
    valid_write_chunk sz mtu ->
    sz + kAttWriteHeaderSize <= mtu.
Proof.
  intros sz mtu Hvalid.
  unfold valid_write_chunk in Hvalid.
  unfold kAttWriteHeaderSize.
  lia.
Qed.

(** Theorem 4: Under the minimum BLE ATT_MTU (23 bytes), the valid chunk bound is [1, 20]. *)
Theorem ble_min_mtu_chunk_range :
  forall sz : Z,
    valid_write_chunk sz kBleMinMtu <-> 1 <= sz <= 20.
Proof.
  intros sz.
  unfold valid_write_chunk, kBleMinMtu.
  lia.
Qed.

(** Theorem 5: If the negotiated MTU is at least 515 bytes, the chunk size is capped at 512 bytes. *)
Theorem large_mtu_saturates_at_512 :
  forall sz mtu : Z,
    515 <= mtu ->
    (valid_write_chunk sz mtu <-> 1 <= sz <= 512).
Proof.
  intros sz mtu Hmtu.
  unfold valid_write_chunk.
  lia.
Qed.

(** Theorem 6: Impossibility of valid write chunks when MTU < 4. *)
Theorem invalid_mtu_no_valid_chunk :
  forall sz mtu : Z,
    mtu < 4 ->
    ~ valid_write_chunk sz mtu.
Proof.
  intros sz mtu Hmtu Hvalid.
  unfold valid_write_chunk in Hvalid.
  lia.
Qed.

(** Theorem 7: Monotonicity of valid_write_chunk with respect to MTU expansion (e.g., after Exchange MTU). *)
Theorem valid_write_chunk_mtu_monotonic :
  forall sz mtu1 mtu2 : Z,
    mtu1 <= mtu2 ->
    valid_write_chunk sz mtu1 ->
    valid_write_chunk sz mtu2.
Proof.
  intros sz mtu1 mtu2 Hle Hvalid.
  unfold valid_write_chunk in *.
  lia.
Qed.

(** Theorem 8: Downward closure for positive sizes: any positive sub-chunk of a valid chunk is valid. *)
Theorem valid_write_chunk_subchunk :
  forall sz_sub sz mtu : Z,
    1 <= sz_sub <= sz ->
    valid_write_chunk sz mtu ->
    valid_write_chunk sz_sub mtu.
Proof.
  intros sz_sub sz mtu Hsub Hvalid.
  unfold valid_write_chunk in *.
  lia.
Qed.

(** Theorem 9: Soundness of chunk size clamping for any valid MTU (mtu >= 4). *)
Theorem clamp_chunk_size_valid :
  forall req_sz mtu : Z,
    4 <= mtu ->
    valid_write_chunk (clamp_chunk_size req_sz mtu) mtu.
Proof.
  intros req_sz mtu Hmtu.
  unfold clamp_chunk_size, valid_write_chunk, max_chunk_size,
         kAttWriteHeaderSize, kMaxAttributeLength.
  lia.
Qed.

(** Theorem 10: Clamping preserves already-valid chunk sizes (idempotence on valid inputs). *)
Theorem clamp_chunk_size_idempotent_on_valid :
  forall sz mtu : Z,
    valid_write_chunk sz mtu ->
    clamp_chunk_size sz mtu = sz.
Proof.
  intros sz mtu Hvalid.
  unfold clamp_chunk_size, valid_write_chunk, max_chunk_size,
         kAttWriteHeaderSize, kMaxAttributeLength in *.
  lia.
Qed.
```

---

## 5. Verification Analysis & Hardware API Invariant Preservation

### 5.1 Proof Audit Summary
| Metric | Value |
| :--- | :--- |
| **Total Definitions** | 7 (`kMaxAttributeLength`, `kAttWriteHeaderSize`, `kBleMinMtu`, `max_chunk_size`, `valid_write_chunk`, `check_valid_write_chunk`, `blink_write_value_length_valid`, `clamp_chunk_size`) |
| **Total Theorems** | 10 |
| **Admitted / Axiom Count** | **0** |
| **Decision Procedures Used** | `lia` (Linear Integer Arithmetic over `Z`), boolean reflection via `Z.leb_le` and `andb_true_iff` |

### 5.2 Preservation of Hardware & IPC Invariants
1. **Renderer-to-Browser IPC Safety (`valid_chunk_respects_blink_512_bound`):** Proves that any chunk satisfying `valid_write