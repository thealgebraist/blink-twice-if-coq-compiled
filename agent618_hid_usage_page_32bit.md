# Formal Verification Report: WebHID 32-bit Extended Usage Code Decomposition

**Agent ID:** Agent 618 (Web Hardware & Peripheral Platform APIs)  
**Target Module:** `third_party/blink/renderer/modules/hid/hid_collection_info.cc`  
**Specification:** W3C WebHID API §3.3 & USB HID 1.11 §5.5 / §6.2.2  
**Formalization Target:** `BlinkWebHIDUsagePage32BitSemantics.v`  

---

## 1. Normative Specification Requirements

### 1.1 USB HID 1.11 Specification (§5.5 & §6.2.2)
In the USB Device Class Definition for Human Interface Devices (HID) Version 1.11, device capabilities and controls are identified using **Usages**. A complete Usage is a 32-bit unsigned integer composed of two distinct 16-bit fields:
1. **Usage Page (High 16 bits, bits 31–16):** Defines the general category or namespace of the control (e.g., `0x01` for Generic Desktop Controls, `0x07` for Keyboard/Keypad, `0x0C` for Consumer).
2. **Usage ID (Low 16 bits, bits 15–0):** Identifies the specific control or measurement within the designated Usage Page (e.g., `0x02` for Mouse, `0x06` for Keyboard under Generic Desktop).

According to USB HID 1.11 §5.5 (*Usages*) and §6.2.2.7 (*Local Items*):
$$\text{Extended Usage}_{32} = (\text{Usage Page}_{16} \ll 16) \mid \text{Usage ID}_{16}$$

### 1.2 W3C WebHID API Specification (§3.3 `HIDCollectionInfo` & `HIDReportItem`)
The W3C WebHID API exposes HID report descriptors to web applications via structured WebIDL dictionaries (`HIDCollectionInfo`, `HIDReportInfo`, and `HIDReportItem`). 

1. **Collection Decomposition (`HIDCollectionInfo`):**
   - `usagePage` (WebIDL `unsigned short`): The 16-bit usage page associated with the collection.
   - `usage` (WebIDL `unsigned short`): The 16-bit usage ID associated with the collection.
2. **Report Item Extended Usages (`HIDReportItem`):**
   - `usages` (WebIDL `sequence<unsigned long>`): Array of 32-bit extended usage values. Each element encodes both the 16-bit usage page in its upper 16 bits and the 16-bit usage ID in its lower 16 bits.
   - `usageMinimum` / `usageMaximum` (WebIDL `unsigned long`): 32-bit extended usage bounds.

**Normative Mathematical Invariant:**
For any 32-bit unsigned extended usage $u \in [0, 2^{32} - 1]$:
$$\text{usage\_page}(u) = \lfloor u / 65536 \rfloor \in [0, 65535]$$
$$\text{usage\_id}(u) = u \bmod 65536 \in [0, 65535]$$
$$u = \text{usage\_page}(u) \times 65536 + \text{usage\_id}(u)$$

---

## 2. Chromium Blink Implementation Details & Invariants

### 2.1 Source Analysis: `third_party/blink/renderer/modules/hid/hid_collection_info.cc`
In Chromium's multi-process architecture, the `device::mojom::blink::HidCollectionInfo` and `device::mojom::blink::HidReportItem` Mojo structures are deserialized in the Blink renderer process.

In `third_party/blink/renderer/modules/hid/hid_collection_info.cc` (and its companion `hid_report_item.cc`):

```cpp
// third_party/blink/renderer/modules/hid/hid_collection_info.cc
namespace blink {

HIDCollectionInfo::HIDCollectionInfo(
    const device::mojom::blink::HidCollectionInfo& collection) {
  usage_page_ = collection.usage->usage_page;
  usage_ = collection.usage->usage;
  collection_type_ = collection.collection_type;
  // ... populates children and reports
}

uint16_t HIDCollectionInfo::usagePage() const {
  return usage_page_;
}

uint16_t HIDCollectionInfo::usage() const {
  return usage_;
}

}  // namespace blink
```

And in `third_party/blink/renderer/modules/hid/hid_report_item.cc`, where 32-bit usages are constructed from `device::mojom::blink::HidUsageAndPage`:

```cpp
namespace {

uint32_t ConvertHidUsageAndPageToUint32(
    const device::mojom::blink::HidUsageAndPage& usage) {
  return static_cast<uint32_t>(usage.usage_page) << 16 | usage.usage;
}

}  // namespace
```

Conversely, when decomposing a 32-bit combined usage back into its constituent `usage_page` and `usage` (or during descriptor parsing in `services/device/public/cpp/hid/hid_report_descriptor_item.cc`):

```cpp
uint16_t usage_page = static_cast<uint16_t>((combined_usage >> 16) & 0xffff);
uint16_t usage_id = static_cast<uint16_t>(combined_usage & 0xffff);
```

### 2.2 C++ Implementation Invariants
1. **No Overflow on Composition:** Because `usage_page` is `uint16_t` ($\le 65535$), casting to `uint32_t` and shifting left by 16 bits yields a value in $\{0, 65536, \dots, 4294901760\}$ where the lower 16 bits are strictly zero. Bitwise OR (`|`) with `uint16_t usage` is strictly equivalent to integer addition (`+`).
2. **Exact Arithmetic Equivalence:** Under unsigned 32-bit semantics, `(u32 >> 16)` is identical to integer division `u32 / 65536`, and `(u32 & 0xFFFF)` is identical to Euclidean modulo `u32 % 65536`.
3. **Bijectivity:** The mapping between $\mathbb{Z}_{2^{32}}$ and $\mathbb{Z}_{2^{16}} \times \mathbb{Z}_{2^{16}}$ is a total bijection, preventing any Usage Page spoofing or truncation bugs across the Mojo IPC boundary and WebIDL bindings.

---

## 3. Formal Specification in Rocq/Coq

Below is the self-contained formalization in `BlinkWebHIDUsagePage32BitSemantics.v`. It models both the arithmetic specification (`Z.div`, `Z.modulo`, multiplication, addition) and the C++ bitwise operations (`Z.shiftr`, `Z.shiftl`, `Z.land`, `Z.lor`) over bounded 16-bit and 32-bit integers.

## 4. Concrete Theorems and Complete Proofs (`BlinkWebHIDUsagePage32BitSemantics.v`)

```coq
(** * BlinkWebHIDUsagePage32BitSemantics.v
    Formal Verification of WebHID 32-bit Usage Code Decomposition
    Chromium Source: third_party/blink/renderer/modules/hid/hid_collection_info.cc
    Specification: W3C WebHID API §3.3 / USB HID 1.11 §5.5 *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Hardware & WebIDL Integer Bounds *)

Definition U16_BOUND : Z := 65536.          (* 2^16 *)
Definition U16_MAX   : Z := 65535.          (* 2^16 - 1 *)
Definition U32_BOUND : Z := 4294967296.     (* 2^32 *)
Definition U32_MAX   : Z := 4294967295.     (* 2^32 - 1 *)

(** Validity predicates corresponding to uint16_t and uint32_t *)
Definition is_u16 (x : Z) : Prop := 0 <= x < U16_BOUND.
Definition is_u32 (x : Z) : Prop := 0 <= x < U32_BOUND.

(** Decidable boolean counterparts *)
Definition is_u16_b (x : Z) : bool := (0 <=? x) && (x <? U16_BOUND).
Definition is_u32_b (x : Z) : bool := (0 <=? x) && (x <? U32_BOUND).

(** ** 2. Specification-Level Arithmetic Definitions *)

(** Extract top 16 bits (Usage Page) via division by 65536 *)
Definition usage_page (u32 : Z) : Z :=
  u32 / U16_BOUND.

(** Extract low 16 bits (Usage ID) via modulo 65536 *)
Definition usage_id (u32 : Z) : Z :=
  u32 mod U16_BOUND.

(** Compose 16-bit Usage Page and 16-bit Usage ID into 32-bit Extended Usage *)
Definition compose_usage (page id : Z) : Z :=
  page * U16_BOUND + id.

(** ** 3. Blink C++ Bitwise Implementation Definitions *)

(** Corresponds to: static_cast<uint16_t>((u32 >> 16) & 0xFFFF) *)
Definition blink_extract_usage_page (u32 : Z) : Z :=
  Z.shiftr u32 16.

(** Corresponds to: static_cast<uint16_t>(u32 & 0xFFFF) *)
Definition blink_extract_usage_id (u32 : Z) : Z :=
  Z.land u32 U16_MAX.

(** Corresponds to: (static_cast<uint32_t>(page) << 16) | id *)
Definition blink_compose_usage (page id : Z) : Z :=
  Z.lor (Z.shiftl page 16) id.

(** ** 4. Fundamental Decomposition & Range Theorems *)

Lemma u16_bound_pos : U16_BOUND > 0.
Proof.
  unfold U16_BOUND. lia.
Qed.

Lemma u32_bound_factor : U32_BOUND = U16_BOUND * U16_BOUND.
Proof.
  unfold U32_BOUND, U16_BOUND. lia.
Qed.

(** Theorem 1: Fundamental Reconstruction Identity
    u32 = usage_page(u32) * 65536 + usage_id(u32) *)
Theorem usage_decomposition_identity : forall u32 : Z,
  u32 = usage_page u32 * 65536 + usage_id u32.
Proof.
  intros u32.
  unfold usage_page, usage_id, U16_BOUND.
  pose proof (Z_div_mod_eq_full u32 65536) as Hdiv.
  lia.
Qed.

(** Theorem 2: Usage ID is strictly within 16-bit unsigned bounds [0, 65535] *)
Theorem usage_id_is_u16 : forall u32 : Z,
  is_u16 (usage_id u32).
Proof.
  intros u32.
  unfold is_u16, usage_id, U16_BOUND.
  apply Z.mod_pos_bound.
  lia.
Qed.

(** Theorem 3: For any valid 32-bit usage, Usage Page is within 16-bit bounds [0, 65535] *)
Theorem usage_page_is_u16 : forall u32 : Z,
  is_u32 u32 ->
  is_u16 (usage_page u32).
Proof.
  intros u32 [Hge Hlt].
  unfold is_u16, usage_page, U16_BOUND in *.
  unfold U32_BOUND in Hlt.
  split.
  - apply Z.div_pos; lia.
  - apply Z.div_lt_upper_bound; lia.
Qed.

(** Theorem 4: Composing valid 16-bit page and ID yields a valid 32-bit usage *)
Theorem compose_usage_is_u32 : forall page id : Z,
  is_u16 page ->
  is_u16 id ->
  is_u32 (compose_usage page id).
Proof.
  intros page id [Hp_ge Hp_lt] [Hi_ge Hi_lt].
  unfold is_u32, compose_usage, U16_BOUND, U32_BOUND in *.
  lia.
Qed.

(** ** 5. Bijection & Round-Trip Inversion Theorems *)

(** Theorem 5: Decomposing and recomposing any 32-bit usage is the identity *)
Theorem decompose_compose_roundtrip : forall u32 : Z,
  compose_usage (usage_page u32) (usage_id u32) = u32.
Proof.
  intros u32.
  unfold compose_usage, U16_BOUND.
  symmetry.
  apply usage_decomposition_identity.
Qed.

(** Theorem 6: Extracting Usage Page from a composed 32-bit usage recovers page *)
Theorem compose_extract_page : forall page id : Z,
  is_u16 id ->
  usage_page (compose_usage page id) = page.
Proof.
  intros page id [Hi_ge Hi_lt].
  unfold usage_page, compose_usage, U16_BOUND in *.
  rewrite Z.div_add_l by lia.
  rewrite (Z.div_small id 65536) by lia.
  lia.
Qed.

(** Theorem 7: Extracting Usage ID from a composed 32-bit usage recovers id *)
Theorem compose_extract_id : forall page id : Z,
  is_u16 id ->
  usage_id (compose_usage page id) = id.
Proof.
  intros page id [Hi_ge Hi_lt].
  unfold usage_id, compose_usage, U16_BOUND in *.
  rewrite Z.add_comm.
  rewrite Z.mod_add by lia.
  apply Z.mod_small.
  lia.
Qed.

(** Theorem 8: Canonic