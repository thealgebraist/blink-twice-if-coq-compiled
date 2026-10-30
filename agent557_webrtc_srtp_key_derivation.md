# Formal Verification Report: WebRTC SRTP Key Derivation Length Preservation in Chromium

**Formal Theory Target:** `BlinkWebRTCSRTPKeyDerivationLengthSemantics.v`  
**Chromium Subsystem:** `third_party/webrtc/pc/dtls_srtp_transport.cc`  
**Normative Specification:** IETF RFC 5764 §4.1.2, §4.2 (DTLS Extension to Establish Keys for the Secure Real-time Transport Protocol)  
**Mathematical Property:** Exactness of exporter buffer allocation and slicing invariants across directional key/salt boundaries ($16\text{ bytes}$ key / $14\text{ bytes}$ salt for AES-128; $32\text{ bytes}$ key / $12\text{ or }14\text{ bytes}$ salt for AES-256).

---

## 1. Normative Specification Requirements (RFC 5764 & RFC 7714)

WebRTC mandates Secure Real-time Transport Protocol (SRTP) keyed via Datagram Transport Layer Security (DTLS-SRTP) as defined in W3C WebRTC 1.0 and IETF RFC 8827. The cryptographic key extraction mechanism is governed by **RFC 5764 §4.2 (Key Derivation)** and **RFC 5705 (Keying Material Exporters for TLS)**.

When DTLS handshakes complete, both endpoints extract shared keying material from the TLS Pseudo-Random Function (PRF) or HKDF-Expand-Label (in DTLS 1.3) using the disambiguating ASCII label `"EXTRACTOR-dtls_srtp"` without context. 

Per **RFC 5764 §4.2**, the total exported keying material length $L_{\text{export}}$ is a strict linear function of the negotiated SRTP protection profile's master key length ($L_{\text{key}}$) and master salt length ($L_{\text{salt}}$):

$$L_{\text{export}} = 2 \times (L_{\text{key}} + L_{\text{salt}})$$

The exported byte stream $B[0 \dots L_{\text{export}} - 1]$ is partitioned strictly without padding or overlap into four contiguous segments:

1. **Client Write SRTP Master Key:** $B[0 \dots L_{\text{key}} - 1]$ (Length: $L_{\text{key}}$)
2. **Server Write SRTP Master Key:** $B[L_{\text{key}} \dots 2L_{\text{key}} - 1]$ (Length: $L_{\text{key}}$)
3. **Client Write SRTP Master Salt:** $B[2L_{\text{key}} \dots 2L_{\text{key}} + L_{\text{salt}} - 1]$ (Length: $L_{\text{salt}}$)
4. **Server Write SRTP Master Salt:** $B[2L_{\text{key}} + L_{\text{salt}} \dots 2(L_{\text{key}} + L_{\text{salt}}) - 1]$ (Length: $L_{\text{salt}}$)

Subsequently, these master keys and salts are concatenated into directional composite buffers ($K_{\text{client}} = \text{Key}_{\text{client}} \parallel \text{Salt}_{\text{client}}$ and $K_{\text{server}} = \text{Key}_{\text{server}} \parallel \text{Salt}_{\text{server}}$) and passed to the underlying SRTP engine (`libsrtp`), which runs the SRTP Key Derivation Function (RFC 3711 §4.3) to generate session encryption, authentication, and salting keys.

### Normative Protection Profile Constants (RFC 5764 §4.1.2 & RFC 7714 §14.2)

| SRTP Protection Profile | Cipher | $L_{\text{key}}$ (Bits / Bytes) | $L_{\text{salt}}$ (Bits / Bytes) | Composite Key+Salt ($L_{\text{comp}}$) | Total Export ($L_{\text{export}}$) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `SRTP_AES128_CM_HMAC_SHA1_80` | AES-128-ICM | $128\text{ b} \;/\; 16\text{ B}$ | $112\text{ b} \;/\; 14\text{ B}$ | $30\text{ B}$ | $60\text{ B}$ |
| `SRTP_AES128_CM_HMAC_SHA1_32` | AES-128-ICM | $128\text{ b} \;/\; 16\text{ B}$ | $112\text{ b} \;/\; 14\text{ B}$ | $30\text{ B}$ | $60\text{ B}$ |
| `SRTP_AEAD_AES_128_GCM` | AES-128-GCM | $128\text{ b} \;/\; 16\text{ B}$ | $96\text{ b} \;/\; 12\text{ B}$ | $28\text{ B}$ | $56\text{ B}$ |
| `SRTP_AEAD_AES_256_GCM` | AES-256-GCM | $256\text{ b} \;/\; 32\text{ B}$ | $96\text{ b} \;/\; 12\text{ B}$ | $44\text{ B}$ | $88\text{ B}$ |

---

## 2. Chromium / WebRTC Implementation & Invariants

In Chromium's WebRTC implementation (`third_party/webrtc/pc/dtls_srtp_transport.cc` and `rtc_base/ssl_stream_adapter.cc`), key derivation and transport provisioning occur inside `DtlsSrtpTransport::SetupRtpDtlsSrtp()` and `DtlsSrtpTransport::ExtractParams()`.

### Implementation Mechanics (`DtlsSrtpTransport::ExtractParams`)

1. **Profile Negotiation Query:**  
   The transport queries the selected DTLS-SRTP protection profile via `dtls_transport->GetSrtpCryptoSuite(&selected_crypto_suite)`.
2. **Dimension Resolution:**  
   `rtc::GetSrtpKeyAndSaltLengths(selected_crypto_suite, &key_len, &salt_len)` maps the profile constant to exact byte lengths (`key_len` $\in \{16, 32\}$, `salt_len` $\in \{12, 14\}$).
3. **Exporter Buffer Allocation:**  
   A `rtc::ZeroOnFreeBuffer<uint8_t> dtls_buffer(key_len * 2 + salt_len * 2)` is allocated to hold the raw TLS exporter output.
4. **TLS Keying Material Extraction:**  
   `dtls_transport->ExportKeyingMaterial(kDtlsSrtpExporterLabel, NULL, 0, false, dtls_buffer.data(), dtls_buffer.size())` populates the buffer.
5. **Directional De-interleaving and Re-concatenation:**  
   Two directional `rtc::ZeroOnFreeBuffer<uint8_t>` buffers, `client_write_key(key_len + salt_len)` and `server_write_key(key_len + salt_len)`, are allocated. The implementation slices `dtls_buffer` using pointer offsets:
   - `client_write_key[0 .. key_len - 1]` $\leftarrow$ `dtls_buffer[0 .. key_len - 1]`
   - `client_write_key[key_len .. key_len + salt_len - 1]` $\leftarrow$ `dtls_buffer[2 * key_len .. 2 * key_len + salt_len - 1]`
   - `server_write_key[0 .. key_len - 1]` $\leftarrow$ `dtls_buffer[key_len .. 2 * key_len - 1]`
   - `server_write_key[key_len .. key_len + salt_len - 1]` $\leftarrow$ `dtls_buffer[2 * key_len + salt_len .. 2 * key_len + 2 * salt_len - 1]`

### Critical Implementation Invariants

* **Invariant I1 (Cipher Key Length Preservation):** For any valid negotiated suite $c$, the extracted key slice length is strictly $16\text{ bytes}$ if $\text{Cipher}(c) = \text{AES-128}$ and $32\text{ bytes}$ if $\text{Cipher}(c) = \text{AES-256}$.
* **Invariant I2 (Memory Safety & Zero Out-of-Bounds Slicing):** All four offset intervals $[0, L_{\text{key}})$, $[L_{\text{key}}, 2L_{\text{key}})$, $[2L_{\text{key}}, 2L_{\text{key}} + L_{\text{salt}})$, and $[2L_{\text{key}} + L_{\text{salt}}, 2L_{\text{key}} + 2L_{\text{salt}})$ are strictly non-overlapping, exhaustive partitions of $[0, L_{\text{export}})$.
* **Invariant I3 (Directional Role Symmetry):** If an endpoint acts as `SSL_CLIENT` (active DTLS role) and its peer acts as `SSL_SERVER` (passive DTLS role) over identical exported material, the client's `send_key` is bit-identical to the server's `recv_key`, and its key segment length matches the underlying block cipher requirement.

---

## 3. Formal Specification in Rocq/Coq

Below is the self-contained formalization module `BlinkWebRTCSRTPKeyDerivationLengthSemantics.v`. It models the protection profiles, cipher classes, byte buffers via `List`, pointer slicing semantics in `ExtractParams`, and the SRTP KDF input validation gates.

```coq
(** * BlinkWebRTCSRTPKeyDerivationLengthSemantics.v
    Formal Verification of WebRTC DTLS-SRTP Key Derivation Length Preservation
    Target: third_party/webrtc/pc/dtls_srtp_transport.cc
    Specification: IETF RFC 5764 Section 4.1.2 & Section 4.2, RFC 7714 Section 14.2
*)

From Coq Require Import List.
From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Cryptographic Primitives and Protection Profiles *)

Inductive CipherRequirement : Type :=
  | Cipher_AES_128 : CipherRequirement
  | Cipher_AES_256 : CipherRequirement.

Definition cipher_required_key_bytes (c : CipherRequirement) : Z :=
  match c with
  | Cipher_AES_128 => 16
  | Cipher_AES_256 => 32
  end.

(** Negotiable SRTP Protection Profiles in Chromium (rtc_base/ssl_stream_adapter.h) *)
Inductive SrtpCryptoSuite : Type :=
  | SRTP_AES128_CM_HMAC_SHA1_80 : SrtpCryptoSuite
  | SRTP_AES128_CM_HMAC_SHA1_32 : SrtpCryptoSuite
  | SRTP_AEAD_AES_128_GCM       : SrtpCryptoSuite
  | SRTP_AEAD_AES_256_GCM       : SrtpCryptoSuite.

Definition suite_cipher (suite : SrtpCryptoSuite) : CipherRequirement :=
  match suite with
  | SRTP_AES128_CM_HMAC_SHA1_80 => Cipher_AES_128
  | SRTP_AES128_CM_HMAC_SHA1_32 => Cipher_AES_128
  | SRTP_AEAD_AES_128_GCM       => Cipher_AES_128
  | SRTP_AEAD_AES_256_GCM       => Cipher_AES_256
  end.

(** Model of rtc::GetSrtpKeyAndSaltLengths (ssl_stream_adapter.cc) *)
Definition get_srtp_key_and_salt_lengths (suite : SrtpCryptoSuite) : (Z * Z) :=
  match suite with
  | SRTP_AES128_CM_HMAC_SHA1_80 => (16, 14)
  | SRTP_AES128_CM_HMAC_SHA1_32 => (16, 14)
  | SRTP_AEAD_AES_128_GCM       => (16, 12)
  | SRTP_AEAD_AES_256_GCM       => (32, 12)
  end.

Definition suite_key_len (suite : SrtpCryptoSuite) : Z :=
  fst (get_srtp_key_and_salt_lengths suite).

Definition suite_salt_len (suite : SrtpCryptoSuite) : Z :=
  snd (get_srtp_key_and_salt_lengths suite).

(** Total exporter buffer allocation size: 2 * (key_len + salt_len) *)
Definition exporter_alloc_len (suite : SrtpCryptoSuite) : Z :=
  let (k, s) := get_srtp_key_and_salt_lengths suite in
  2 * k + 2 * s.

(** ** 2. Byte Buffer and Slicing Semantics *)

Definition Byte := Z.
Definition Buffer := list Byte.

Definition buf_len (b : Buffer) : Z := Z.of_nat (length b).

(** Slice [offset, offset + len) from a buffer *)
Definition slice (b : Buffer) (offset len : Z) : Buffer :=
  firstn (Z.to_nat len) (skipn (Z.to_nat offset) b).

(** De-interleaved Master Key and Master Salt structure *)
Record SrtpMasterKeyMaterial : Type := mkMasterMaterial {
  master_key  : Buffer;
  master_salt : Buffer;
  composite_buffer : Buffer (* key || salt passed to libsrtp *)
}.

Inductive DtlsRole : Type :=
  | Role_Client : DtlsRole
  | Role_Server : DtlsRole.

Record DirectionalSrtpKeys : Type := mkDirectionalKeys {
  send_material : SrtpMasterKeyMaterial;
  recv_material : SrtpMasterKeyMaterial
}.

(** ** 3. Chromium DtlsSrtpTransport::ExtractParams Model *)

Definition extract_client_material (dtls_buffer : Buffer) (k_len s_len : Z) : SrtpMasterKeyMaterial :=
  let c_key  := slice dtls_buffer 0 k_len in
  let c_salt := slice dtls_buffer (2 * k_len) s_len in
  mkMasterMaterial c_key c_salt (c_key ++ c_salt).

Definition extract_server_material (dtls_buffer : Buffer) (k_len s_len : Z) : SrtpMasterKeyMaterial :=
  let s_key  := slice dtls_buffer k_len k_len in
  let s_salt := slice dtls_buffer (2 * k_len + s_len) s_len in
  mkMasterMaterial s_key s_salt (s_key ++ s_salt).

Definition extract