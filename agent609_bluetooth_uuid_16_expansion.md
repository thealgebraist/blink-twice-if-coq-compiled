# Formal Verification Report: Web Bluetooth 16-bit to 128-bit UUID Expansion Semantics

**Agent:** Formal Verification Agent 609 (Web Hardware & Peripheral Platform APIs)  
**Target Component:** `third_party/blink/renderer/modules/bluetooth/bluetooth_uuid.cc`  
**Specification:** W3C Web Bluetooth §3.4.1 / Bluetooth Core Specification v5.4, Vol 3, Part B, §2.5.1  
**Formal Theory Target:** `BlinkWebBluetoothUUID16ExpansionSemantics.v`  
**Mathematical Property:** $\text{uuid}_{128} = (\text{uuid}_{16} \ll 96) \lor \text{BASE\_UUID}$; expansion is strictly injective and reversible.

---

## 1. Normative Specification Requirements

In the Web Bluetooth API (and shared UUID resolution pipelines across WebHID and WebUSB GATT/HID descriptor bridges), device services, characteristics, and descriptors are identified by Universally Unique Identifiers (UUIDs). To conserve radio bandwidth over the Bluetooth Low Energy (BLE) Attribute Protocol (ATT), the Bluetooth Special Interest Group (SIG) assigns 16-bit and 32-bit short aliases for commonly used standard UUIDs.

### 1.1 W3C Web Bluetooth §3.4.1 (`BluetoothUUID.canonicalUUID`)
According to the W3C Web Bluetooth specification (§3.4.1), the static method `BluetoothUUID.canonicalUUID(alias)` must resolve an unsigned 32-bit integer `[EnforceRange] unsigned long alias` into a canonical 128-bit UUID string formatted as `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (lowercase hexadecimal). 

The normative algorithm states:
1. Let `alias` be an unsigned 32-bit integer (in the 16-bit SIG alias case, restricted to the range $[0, 2^{16}-1]$).
2. Return the 32-bit value formatted as 8 lowercase hex digits, followed by the constant suffix `"-0000-1000-8000-00805f9b34fb"`.

### 1.2 Bluetooth Core Specification v5.4, Vol 3, Part B, §2.5.1 (SDP UUID)
The Bluetooth Core Specification defines the underlying arithmetic transformation used by `canonicalUUID`. All 16-bit and 32-bit UUIDs are projected into the 128-bit UUID space using the **Bluetooth_Base_UUID**:

$$\text{Bluetooth\_Base\_UUID} = \texttt{00000000-0000-1000-8000-00805F9B34FB}_{16}$$

As a 128-bit unsigned integer, the Base UUID is:
$$\text{BASE\_UUID} = \texttt{0x0000000000001000800000805F9B34FB}$$

The arithmetic expansion of a 16-bit UUID ($\text{uuid}_{16} \in [0, 2^{16}-1]$) or 32-bit UUID ($\text{uuid}_{32} \in [0, 2^{32}-1]$) to a 128-bit UUID is defined as:

$$\text{uuid}_{128} = \text{uuid}_{\text{short}} \times 2^{96} + \text{Bluetooth\_Base\_UUID}$$

Because the upper 32 bits (bits 96 through 127) of $\text{Bluetooth\_Base\_UUID}$ are strictly zero ($\lfloor \text{BASE\_UUID} / 2^{96} \rfloor = 0$), addition is bitwise disjoint from the lower 96 bits. Therefore, arithmetic addition is strictly isomorphic to bitwise disjunction (`OR`):

$$\text{uuid}_{128} = (\text{uuid}_{16} \ll 96) \lor \text{BASE\_UUID}$$

---

## 2. Chromium Blink Implementation & Invariants

In Chromium, the Web Bluetooth UUID canonicalization logic is implemented in `third_party/blink/renderer/modules/bluetooth/bluetooth_uuid.cc` and backed by `device/bluetooth/public/cpp/bluetooth_uuid.cc`.

### 2.1 Implementation Mechanics (`bluetooth_uuid.cc`)
In Blink, `BluetoothUUID::canonicalUUID(uint32_t alias)` delegates to `String::Format("%08x-0000-1000-8000-00805f9b34fb", alias)`:

```cpp
// third_party/blink/renderer/modules/bluetooth/bluetooth_uuid.cc
String BluetoothUUID::canonicalUUID(uint32_t alias) {
  return String::Format("%08x-0000-1000-8000-00805f9b34fb", alias);
}
```

When parsed into a binary representation by the browser's Mojo boundary and `device::BluetoothUUID` parser, the string is converted into a 16-byte array (`std::array<uint8_t, 16>`) in network byte order (big-endian):
* Bytes $0..1$ (bits $112..127$): $0x0000$ (for 16-bit aliases)
* Bytes $2..3$ (bits $96..111$): $\text{uuid}_{16}$
* Bytes $4..15$ (bits $0..95$): $\texttt{00 00 10 00 80 00 00 80 5F 9B 34 FB}$

### 2.2 Critical Security & Platform Invariants
1. **Non-Interference / Disjointness Invariant:** A 16-bit alias must never corrupt or carry into bits $0..95$ (the Base UUID suffix) or bits $112..127$ (the upper 16 bits of the 32-bit prefix).
2. **Strict Injectivity (Collision Freedom):** Two distinct 16-bit GATT service/characteristic aliases $u_1 \neq u_2$ must never map to the same 128-bit canonical UUID. In Web Bluetooth, GATT blocklists (e.g., blocking Human Interface Device service `0x1812` or Serial Port `0x1101`) rely on canonical 128-bit UUID comparisons. A collision would allow a blocked 16-bit alias to bypass the security blocklist.
3. **Deterministic Reversibility (Left-Inverse):** Given any expanded 128-bit UUID, extracting bits $96..111$ (`uuid128 >> 96`) must uniquely and Losslessly recover the exact original 16-bit alias, and the lower 96 bits (`uuid128 & ((1 << 96) - 1)`) must identically equal `BASE_UUID`.

---

## 3. Formal Specification in Rocq/Coq

Below is the complete, self-contained formalization of the Web Bluetooth 16-bit to 128-bit UUID expansion semantics in Rocq/Coq (`BlinkWebBluetoothUUID16ExpansionSemantics.v`). We model the bit-vector domain using `ZArith` arbitrary-precision integers constrained by range predicates, ensuring exact bitwise and arithmetic correspondence.

```coq
(** * BlinkWebBluetoothUUID16ExpansionSemantics.v
    Formal Verification of Web Bluetooth 16-bit to 128-bit UUID Expansion
    Target: third_party/blink/renderer/modules/bluetooth/bluetooth_uuid.cc
    Spec: W3C Web Bluetooth §3.4.1 / Bluetooth Core Spec v5.4 Vol 3 Part B §2.5.1 *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

(** ** 1. Architectural Constants and Domain Bounds *)

Definition BOUND_16 : Z := 2 ^ 16.
Definition BOUND_32 : Z := 2 ^ 32.
Definition SHIFT_96 : Z := 96.
Definition BOUND_96 : Z := 2 ^ 96.
Definition BOUND_128 : Z := 2 ^ 128.

(** The Bluetooth Base UUID: 00000000-0000-1000-8000-00805F9B34FB
    Expressed in Z via 32-bit/64-bit limbs to avoid parser overflow and clarify structure:
    - Bits 96..127: 0x00000000
    - Bits 64..95 : 0x00001000
    - Bits 32..63 : 0x80000080
    - Bits 0..31  : 0x5F9B34FB
    Value = 0x1000 * 2^64 + 0x80000080 * 2^32 + 0x5F9B34FB
          = 1208925819614629174706176 + 9223372586675372032 + 1604007163
          = 1208935042987217454083259 *)
Definition BASE_UUID : Z :=
  4096 * (2 ^ 64) + 2147483776 * (2 ^ 32) + 1604007163.

(** ** 2. Domain Predicates *)

(** Valid 16-bit Bluetooth UUID alias: u in [0, 2^16 - 1] *)
Definition is_uuid16 (u : Z) : Prop :=
  0 <= u < BOUND_16.

(** Valid 128-bit UUID: U in [0, 2^128 - 1] *)
Definition is_uuid128 (U : Z) : Prop :=
  0 <= U < BOUND_128.

(** Predicate characterizing a 128-bit UUID that is in the image of 16-bit expansion *)
Definition is_expanded_uuid16 (U : Z) : Prop :=
  is_uuid128 U /\
  (U mod BOUND_96 = BASE_UUID) /\
  (0 <= U / BOUND_96 < BOUND_16).

(** ** 3. Expansion and Extraction Functions *)

(** Core Spec arithmetic definition: uuid16 * 2^96 + BASE_UUID *)
Definition expand_uuid16_arith (u16 : Z) : Z :=
  u16 * BOUND_96 + BASE_UUID.

(** Bitwise specification definition: (uuid16 << 96) | BASE_UUID *)
Definition expand_uuid16_bw (u16 : Z) : Z :=
  Z.lor (Z.shiftl u16 SHIFT_96) BASE_UUID.

(** Reversal / Extraction of the 16-bit alias: uuid128 >> 96 *)
Definition extract_uuid16_bw (u128 : Z) : Z :=
  Z.shiftr u128 SHIFT_96.

(** Extraction of the lower 96-bit Base UUID suffix: uuid128 & ((1 << 96) - 1) *)
Definition extract_base_bw (u128 : Z) : Z :=
  Z.land u128 (Z.ones SHIFT_96).
```

---

## 4. Concrete Theorems and Complete Proofs

We now prove the foundational properties required by the formal verification target:
1. `BASE_UUID` is strictly bounded within $[0, 2^{96})$.
2. The bitwise shift/OR expansion `(uuid16 << 96) | BASE_UUID` is strictly identical to the arithmetic expansion `uuid16 * 2^96 + BASE_UUID` (`expand_bw_eq_arith`).
3. Every expanded 16-bit UUID is a valid 128-bit UUID (`expand_uuid16_in_bounds`).
4. Expansion is **strictly reversible** via bitwise right-shift (`extract_expand_roundtrip`).
5. The lower 96 bits of any expanded UUID are invariant and equal to `BASE_UUID` (`extract_base_invariant`).
6. Expansion is **strictly injective** (`expand_uuid16_injective`).
7. Exact **bijective characterization** of the 16-bit UUID subset within the 128-bit space (`canonical_uuid16_bijection`).

```coq
(** ** 4. Lemmas & Formal Proofs *)

Lemma base_uuid_bounds : 0 <= BASE_UUID < BOUND_96.
Proof.
  unfold BASE_UUID, BOUND_96.
  change (2 ^ 64) with 18446744073709551616.
  change (2 ^ 32) with 4294967296.
  change (2 ^ 96) with 79228162514264337593543950336.
  lia.
Qed.

Lemma bound96_pos : 0 < BOUND_96.
Proof.
  unfold BOUND_96.
  change (2 ^ 96) with 79228162514264337593543950336.
  lia.
Qed.

(** Bitwise disjointness: (u16 << 96) and BASE_UUID share no set bits *)
Lemma shift_and_base_disjoint : forall u16 : Z,
  0 <= u16 ->
  Z.land (Z.shiftl u16 SHIFT_96) BASE_UUID = 0.
Proof.
  intros u16 Hu16.
  apply Z.bits_inj_0.
  intros n.
  destruct (Z.lt_ge_cases n 0) as [Hn_neg | Hn_pos].
  - rewrite Z.testbit_neg_r by lia. reflexivity.
  - rewrite Z.land_spec.
    destruct (Z.lt_ge_cases n SHIFT_96) as [Hn_low | Hn_high].
    + (* For bits 0..95, (u16 << 96) has only 0 bits *)
      rewrite Z.shiftl_spec_low by (unfold SHIFT_96 in *; lia).
      simpl. reflexivity.
    + (* For bits >= 96, BASE_UUID < 2^96 has only 0 bits *)
      pose proof base_uuid_bounds as [Hbase_nonneg Hbase_lt].
      assert (Hbit_base : Z.testbit BASE_UUID n = false).
      {