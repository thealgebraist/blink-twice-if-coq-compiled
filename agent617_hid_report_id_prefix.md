# Formal Verification Research Report: WebHID Report ID Prefixing and Byte Sequence Normalization

**Agent:** Formal Verification Agent 617 (Web Hardware & Peripheral Platform APIs)  
**Topic:** WebHID Report ID Prefixing and Byte Sequence Normalization  
**Chromium Target:** `third_party/blink/renderer/modules/hid/hid_device.cc`  
**Specification:** W3C WebHID API §4.2 (Input/Output/Feature Report ID Prefixing)  
**Formal Theory Target:** `BlinkWebHIDReportIDPrefixSemantics.v`  

---

## 1. Normative W3C WebHID Specification Requirements

The W3C WebHID API Specification (specifically Section 4.2, *HIDDevice Interface*, covering `sendReport`, `sendFeatureReport`, `receiveFeatureReport`, and `HIDInputReportEvent`) establishes strict separation between the **Report ID** (an unsigned 8-bit integer, `octet`) and the **Report Payload** (a `BufferSource` / `DataView`) at the WebIDL JavaScript boundary, while the underlying OS/Device transport protocol (USB HID / Bluetooth HID) transmits reports as a single contiguous byte sequence where the Report ID is optionally prefixed as the initial byte (`byte[0]`).

### 1.1 Report ID Domain Constraints
According to the USB HID 1.11 specification (§6.2.2.7) and W3C WebHID:
* A Report ID is an 8-bit unsigned integer in the range $[0, 255]$.
* **Report ID $0$ is reserved** and indicates that the HID report descriptor does not declare any Report ID tags. If a device uses Report IDs at all, all reports have a non-zero Report ID in $[1, 255]$.
* A device cannot mix unnumbered reports (Report ID $= 0$) and numbered reports (Report ID $\in [1, 255]$) within the same report type domain without adhering to the prefixing rules:
  * **Unnumbered Report ($\text{reportId} = 0$):** No Report ID byte is transmitted over the wire/bus. The raw report sequence consists solely of payload bytes.
  * **Numbered Report ($\text{reportId} \in [1, 255]$):** The 1-byte Report ID is prepended to the payload bytes at the transport layer.

### 1.2 Normative Algorithms (W3C WebHID §4.2)

#### Output & Feature Report Transmission (`sendReport` / `sendFeatureReport`)
1. Let `reportId` be the `octet` argument passed to `sendReport(reportId, data)`.
2. Let `bytes` be the byte sequence obtained by getting a copy of the bytes held by the `BufferSource` `data`.
3. At the Mojo / Platform HID service boundary, the API separates `reportId` and `bytes`. However, if an underlying platform layer or normalization buffer constructs a raw wire packet:
   $$\text{wire\_len}(\text{payload\_len}, \text{has\_id}) = \begin{cases} \text{payload\_len} + 1 & \text{if } \text{has\_id} = \text{true} \\ \text{payload\_len} & \text{if } \text{has\_id} = \text{false} \end{cases}$$

#### Input & Feature Report Reception (`oninputreport` / `receiveFeatureReport`)
When the browser receives a raw report buffer `raw_bytes` of length $\text{raw\_len}$ from the OS HID driver or Mojo service:
1. For `receiveFeatureReport(reportId)`:
   * In Chromium's Mojo `HidConnection::GetFeatureReport`, the platform HID service returns a `buffer` that **includes** the 1-byte `reportId` prefix if and only if $\text{reportId} \neq 0$ ($\text{has\_report\_id} = \text{true}$).
   * To expose the `DataView` to JavaScript (which expects *only* the report payload without the leading Report ID byte), Blink must strip the 1-byte prefix when $\text{reportId} \neq 0$:
   $$\text{report\_payload\_len}(\text{raw\_len}, \text{has\_id}) = \begin{cases} \text{raw\_len} - 1 & \text{if } \text{has\_id} = \text{true} \\ \text{raw\_len} & \text{if } \text{has\_id} = \text{false} \end{cases}$$

---

## 2. Chromium Blink Implementation & Invariants

In `third_party/blink/renderer/modules/hid/hid_device.cc`, `HIDDevice` manages communication between Blink's V8 bindings and `device::mojom::blink::HidConnection`.

### 2.1 Code Structure in `hid_device.cc`

#### 1. `HIDDevice::OnReceiveFeatureReport`
When `connection_->GetFeatureReport(report_id, ...)` completes asynchronously, it invokes `HIDDevice::FinishReceiveFeatureReport(ScriptPromiseResolver<IDLNullable<DOMDataView>>* resolver, uint8_t report_id, bool success, const std::optional<Vector<uint8_t>>& data)`:

```cpp
void HIDDevice::FinishReceiveFeatureReport(
    ScriptPromiseResolver<IDLNullable<DOMDataView>>* resolver,
    uint8_t report_id,
    bool success,
    const std::optional<Vector<uint8_t>>& data) {
  // ...
  // If the report uses a report ID, the first byte of |data| is the report ID
  // and should be stripped before exposing the buffer to script.
  size_t report_offset = (report_id == 0) ? 0 : 1;
  if (!success || !data || data->size() < report_offset) {
    resolver->Reject(V8ThrowDOMException::CreateOrEmpty(
         resolver->GetScriptState()->GetIsolate(),
        DOMExceptionCode::kNotAllowedError, kReceiveFeatureReportFailed));
    return;
  }

   wtf_size_t byte_length = data->size() - report_offset;
  DOMArrayBuffer* dom_buffer = DOMArrayBuffer::Create(
      base::span(*data).subspan(report_offset, byte_length));
  resolver->Resolve(DOMDataView::Create(dom_buffer, 0, byte_length));
}
```

#### 2. `HIDDevice::OnInputReport`
For input reports (`device::mojom::blink::HidConnectionClient::OnInputReport`), the Mojo IPC already splits `uint8_t report_id` and `const Vector<uint8_t>& buffer` in `services/device/hid/hid_connection.cc` using the exact same prefix stripping logic before dispatching across the Mojo pipe:
```cpp
// In services/device/hid/hid_connection.cc:
// If report_id != 0, the first byte of the raw OS buffer is the report_id,
// which is extracted into `report_id` and stripped from the payload span.
```

### 2.2 Critical Memory Safety & Protocol Invariants
1. **Underflow Prevention Invariant:**  
   In `FinishReceiveFeatureReport`, computing `data->size() - report_offset` in unsigned arithmetic (`wtf_size_t` / `size_t`) would wrap around to `SIZE_MAX` if `data->size() == 0` and `report_id != 0` (`report_offset == 1`). Blink explicitly guards this with `if (!success || !data || data->size() < report_offset)`.
2. **Exact Payload Length Invariant:**  
   Whenever `data->size() >= report_offset`, the resulting `DOMDataView` byte length is exactly:
   $$\text{byte\_length} = \text{raw\_len} - (\text{if } \text{has\_id} \text{ then } 1 \text{ else } 0)$$
3. **Round-Trip Byte Sequence Preservation (Bijection):**  
   Prepending a non-zero `report_id` byte to a payload $P$ and subsequently normalizing/stripping the raw report under `has_report_id = true` yields the exact original `(report_id, P)` pair with zero byte corruption or truncation.

---

## 3. Formal Specification in Rocq / Coq

Below is the self-contained formalization module `BlinkWebHIDReportIDPrefixSemantics.v`. It models byte sequences, Report ID predicates, prefix injection (wire encoding), prefix stripping (Blink `FinishReceiveFeatureReport` normalization), and proves key safety and round-trip theorems with **0 admits**.

```coq
(** * BlinkWebHIDReportIDPrefixSemantics.v
    Formal Verification of W3C WebHID §4.2 & Chromium Blink hid_device.cc
    Report ID Prefixing and Byte Sequence Normalization.
*)

From Coq Require Import Bool ZArith List Lia.
Import ListNotations.
Open Scope Z_scope.

(** ** 1. Core Domain Types and Predicates *)

(** A byte (octet) is modeled as an integer in [0, 255]. *)
Definition Byte := Z.

Definition valid_byte (b : Byte) : Prop :=
  0 <= b <= 255.

(** A byte sequence is a list of bytes, each satisfying [valid_byte]. *)
Definition ByteSeq := list Byte.

Definition valid_byte_seq (bs : ByteSeq) : Prop :=
  Forall valid_byte bs.

(** Boolean check for whether a Report ID is non-zero (uses report ID prefix).
    In Blink hid_device.cc: [report_id != 0]. *)
Definition has_report_id_of_id (report_id : Byte) : bool :=
  negb (Z.eqb report_id 0).

(** Report offset in Blink's FinishReceiveFeatureReport:
    [size_t report_offset = (report_id == 0) ? 0 : 1;] *)
Definition report_offset (has_report_id : bool) : Z :=
  if has_report_id then 1 else 0.

(** ** 2. Mathematical Payload Length Specification *)

(** Target Mathematical Property:
    report_payload_len(raw_len, has_report_id) =
      if has_id then raw_len - 1 else raw_len *)
Definition report_payload_len (raw_len : Z) (has_report_id : bool) : Z :=
  if has_report_id then raw_len - 1 else raw_len.

(** Wire buffer length when constructing a raw report from a payload. *)
Definition wire_report_len (payload_len : Z) (has_report_id : bool) : Z :=
  if has_report_id then payload_len + 1 else payload_len.

(** Guard condition in Blink hid_device.cc:
    [data->size() >= report_offset] and [raw_len >= 0] *)
Definition valid_raw_buffer_len (raw_len : Z) (has_report_id : bool) : Prop :=
  raw_len >= report_offset has_report_id.

(** Boolean decision procedure for the Blink length guard:
    [if (data->size() < report_offset) return Reject(...);] *)
Definition check_raw_buffer_len (raw_len : Z) (has_report_id : bool) : bool :=
  Z.geb raw_len (report_offset has_report_id).

(** ** 3. Byte Sequence Prefixing and Normalization Operations *)

(** Length of a ByteSeq in Z. *)
Definition seq_len (bs : ByteSeq) : Z :=
  Z.of_nat (length bs).

(** Construct a raw wire report from (report_id, payload):
    If report_id != 0, prepend report_id to payload; otherwise return payload. *)
Definition encode_wire_report (report_id : Byte) (payload : ByteSeq) : ByteSeq :=
  if has_report_id_of_id report_id then
    report_id :: payload
  else
    payload.

(** Blink FinishReceiveFeatureReport normalization:
    Returns [Some payload] if the raw buffer has sufficient length,
    or [None] (corresponding to Promise Rejection with NotAllowedError)
    if [data->size() < report_offset]. *)
Definition normalize_received_report
    (report_id : Byte) (raw_data : ByteSeq) : option ByteSeq :=
  if has_report_id_of_id report_id then
    match raw_data with
    | [] => None
    | _id_byte :: payload => Some payload
    end
  else
    Some raw_data.

(** Strict normalization that also validates that the leading byte matches
    the expected [report_id] when [report_id != 0]. *)
Definition normalize_received_report_strict
    (report_id : Byte) (raw_data : ByteSeq) : option ByteSeq :=
  if has_report_id_of_id report_id then
    match raw_data with
    | [] => None
    | id_byte :: payload =>
        if Z.eqb id_byte report_id then Some payload else None
    end
  else
    Some raw_data.
```

---

## 4. Concrete Theorems and Complete Admitted-Free Proofs

We now state and prove the core verification theorems establishing arithmetic equivalence, absence of integer underflow, exactness of `subspan` byte length, and round-trip codec invertibility.

```coq
(** ** 4. Formal Verification Theorems & Proofs *)

(** Theorem 1: Equivalence between the mathematical property [report_payload_len]
    and Blink's offset subtraction [raw_len - report_offset(has_report_id)]. *)
Theorem report_payload_len_offset_equiv :
  forall (raw_len : Z) (has_id : bool),
    report_payload_len raw_len has_id = raw_len - report_offset has_id.
Proof.
  intros raw_len has_id.
  destruct has_id; unfold report_payload_len, report_offset; lia.
Qed.

(** Theorem 2: Correctness of the boolean guard [check_raw_buffer_len]
    with respect to [valid_raw_buffer_len]. *)
Theorem check_raw_buffer_len_correct :
  forall (raw_len : Z) (has_id : bool),
    check_raw_buffer_len raw_len has_id = true <->
    valid_raw_buffer_len raw_len has_id.
Proof.
  intros raw_len has_id.
  unfold check_raw_buffer_len, valid_raw_buffer_len.
  rewrite Z.geb_le.
  lia.
Qed.

(** Theorem 3: Non-negativity (No Unsigned Underflow) Invariant.
    In Blink's [FinishReceiveFeatureReport], if the guard
    [valid_raw_buffer_len raw_len has_id] holds, then
    [report_payload_len raw_len has_id >= 0], guaranteeing that
    [wtf_size_t byte_length = data->size() - report_offset] never underflows. *)
Theorem report_payload_len_nonneg :
  forall (raw_len : Z) (has_id : bool),
    valid_raw_buffer_len raw_len has