# Formal Verification Report: Chromium WebAuthn Timeout Clamping Semantics

**Target Component**: Chromium Blink / FIDO Device Layer (`device/fido/fido_constants.cc`, `content/browser/webauthn/authenticator_common_impl.cc`)  
**Specification**: W3C Web Authentication: An API for accessing Public Key Credentials Level 3 (§5.1.3, §5.1.4)  
**Formal Theory Target**: `BlinkWebAuthnTimeoutClampingSemantics.v`  
**Verification Engine**: Rocq / Coq Proof Assistant (`ZArith`, `Lia`, `Bool`)

---

## 1. Normative W3C WebAuthn & Credential Management Requirements

In the W3C Web Authentication (WebAuthn) Level 3 specification, Relying Parties (RPs) may specify an optional `timeout` member inside `PublicKeyCredentialCreationOptions` (§5.4) or `PublicKeyCredentialRequestOptions` (§5.5). This value represents the time, in milliseconds, that the caller is willing to wait for the call to complete.

### 1.1 Normative Algorithm Rules (§5.1.3 & §5.1.4)
Both **§5.1.3 (Create a New Credential - `[[Create]]`)** and **§5.1.4 (Use an Existing Credential to Make an Assertion - `[[Get]]`)** enforce strict bounds on how User Agents (UAs) calculate the effective timer value (`lifetimeTimer`):

1. **Type Representation**: In WebIDL, `timeout` is defined as an `unsigned long` (`[0, 2^32 - 1]`).
2. **Permissive Guidance Overriding**: The specification explicitly states: *"This member is treated as a hint, and the user agent MAY override the value."*
3. **Default Value Resolution**:
   * If `options.timeout` is **not** present:
     * If `userVerification` is set to `"required"`, set `lifetimeTimer` to a browser-specific or platform-specific default (suggested: `120000` ms to `300000` ms).
     * Otherwise, set `lifetimeTimer` to an implementation-defined default.
4. **Clamping Invariant**:
   * If `options.timeout` **is** present, set `lifetimeTimer` to `options.timeout`.
   * If `lifetimeTimer` is less than a minimum reasonable threshold determined by the UA, set `lifetimeTimer` to that minimum threshold.
   * If `lifetimeTimer` is greater than a maximum reasonable threshold determined by the UA, set `lifetimeTimer` to that maximum threshold.

### 1.2 Security & Availability Rationale
Without strict engine-enforced clamping:
* **Underflow / Starvation Attacks ($t \to 0$)**: A malicious or misconfigured script could pass `timeout: 0` or `timeout: 1`, causing instantaneous `NotAllowedError` aborts before IPC traversal to the platform authenticator completes, or creating race conditions in UI rendering (e.g., transient permission prompt flashing / UI spoofing).
* **Resource Exhaustion / Hanging Requests ($t \to 2^{32}-1$)**: Since WebAuthn requests acquire exclusive locks over physical USB/NFC HID channels (`FidoRequestHandlerBase`) and maintain active modal UI surfaces, an unbounded timeout (up to ~49.7 days for `uint32_t`) enables denial-of-service (DoS) against concurrent frames or background tabs attempting to use the authenticator.

---

## 2. Chromium Blink & Content Implementation Analysis

In Chromium, the translation from Blink's Mojo interface (`blink::mojom::PublicKeyCredentialCreationOptions` / `RequestOptions`) to the browser process (`content::AuthenticatorCommonImpl`) enforces deterministic clamping based on constants defined in the FIDO device layer.

### 2.1 Source Code Architecture (`device/fido/fido_constants.cc`)

In `device/fido/fido_constants.h` and `device/fido/fido_constants.cc`, the global bounding constants for WebAuthn request timeouts are defined using `base::TimeDelta`:

```cpp
// device/fido/fido_constants.cc
namespace device {

constexpr base::TimeDelta kMinWebAuthnTimeout = base::Seconds(1);       // 1,000 ms
constexpr base::TimeDelta kMaxWebAuthnTimeout = base::Minutes(10);      // 600,000 ms
constexpr base::TimeDelta kDefaultWebAuthnTimeout = base::Minutes(10);  // 600,000 ms

}  // namespace device
```

In `content/browser/webauthn/authenticator_common_impl.cc`, the timeout adjustment function `AdjustTimeout` processes the optional `base::TimeDelta` passed over Mojo from Blink (`third_party/blink/renderer/modules/credentialmanagement/authentication_credentials_container.cc`):

```cpp
// content/browser/webauthn/authenticator_common_impl.cc
base::TimeDelta AdjustTimeout(absl::optional<base::TimeDelta> timeout,
                              RenderFrameHost* render_frame_host) {
  if (!timeout) {
    return device::kDefaultWebAuthnTimeout;
  }
  return std::clamp(*timeout, device::kMinWebAuthnTimeout,
                    device::kMaxWebAuthnTimeout);
}
```

### 2.2 Implementation Invariants
Let $T_{\min} = 1000\text{ ms}$ and $T_{\max} = 600000\text{ ms}$. For any input $t \in \mathbb{Z}$ (representing milliseconds extracted from the WebIDL `unsigned long` or signed `base::TimeDelta` internal microsecond/millisecond representation):

$$\text{clamped\_timeout}(t) = \min(600000, \max(1000, t))$$

The implementation maintains five core security invariants:
1. **Strict Bounds**: $\forall t \in \mathbb{Z}, 1000 \le \text{clamped\_timeout}(t) \le 600000$.
2. **Identity Preservation (Transparency)**: $\forall t \in [1000, 600000], \text{clamped\_timeout}(t) = t$.
3. **Idempotence**: Clamping an already-clamped timeout across process boundaries (e.g., Blink $\to$ Browser $\to$ Platform API) yields the exact same duration: $\text{clamped\_timeout}(\text{clamped\_timeout}(t)) = \text{clamped\_timeout}(t)$.
4. **Monotonicity**: If RP request $A$ specifies a smaller or equal timeout than request $B$ ($t_1 \le t_2$), the engine will never grant request $A$ a strictly longer lifetime than request $B$: $\text{clamped\_timeout}(t_1) \le \text{clamped\_timeout}(t_2)$.
5. **Default Safety**: When `timeout` is omitted (`None`), the fallback value (`kDefaultWebAuthnTimeout` = $600000\text{ ms}$) satisfies the exact same bounds invariant and is stable under clamping.

---

## 3. Formal Specification & Verification in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkWebAuthnTimeoutClampingSemantics.v`. It models both raw timeout clamping and optional Mojo `TimeDelta` resolution, proving all algebraic and security invariants over $\mathbb{Z}$ without any axioms or admitted obligations.

```coq
(** * BlinkWebAuthnTimeoutClampingSemantics.v
    Formal Verification of Chromium WebAuthn Timeout Clamping Semantics
    Source: device/fido/fido_constants.cc & content/browser/webauthn/authenticator_common_impl.cc
    Specification: W3C WebAuthn Level 3 §5.1.3 & §5.1.4 *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.

Section WebAuthnTimeoutClamping.

  (** ** 1. Engine Constants (device/fido/fido_constants.cc) *)

  (** [kMinWebAuthnTimeout = base::Seconds(1)] -> 1000 ms *)
  Definition kMinWebAuthnTimeout : Z := 1000.

  (** [kMaxWebAuthnTimeout = base::Minutes(10)] -> 600000 ms *)
  Definition kMaxWebAuthnTimeout : Z := 600000.

  (** [kDefaultWebAuthnTimeout = base::Minutes(10)] -> 600000 ms *)
  Definition kDefaultWebAuthnTimeout : Z := 600000.

  (** Well-formedness of engine constants *)
  Lemma engine_bounds_wf : kMinWebAuthnTimeout <= kMaxWebAuthnTimeout.
  Proof.
    unfold kMinWebAuthnTimeout, kMaxWebAuthnTimeout.
    lia.
  Qed.

  (** ** 2. Formal Specification of Clamping Semantics *)

  (** Mathematical specification:
      clamped_timeout(t) = min(600000, max(1000, t)) *)
  Definition clamped_timeout (t : Z) : Z :=
    Z.min kMaxWebAuthnTimeout (Z.max kMinWebAuthnTimeout t).

  (** Alternative formulation with outer max and inner min (std::clamp equivalence) *)
  Definition clamped_timeout_alt (t : Z) : Z :=
    Z.max kMinWebAuthnTimeout (Z.min kMaxWebAuthnTimeout t).

  (** Model of Mojo optional<TimeDelta> resolution in AdjustTimeout() *)
  Definition adjust_timeout (opt_t : option Z) : Z :=
    match opt_t with
    | None => kDefaultWebAuthnTimeout
    | Some t => clamped_timeout t
    end.

  (** Predicate defining a valid engine lifetimeTimer value *)
  Definition is_valid_engine_timeout (t : Z) : Prop :=
    kMinWebAuthnTimeout <= t /\ t <= kMaxWebAuthnTimeout.

  (** Executable boolean checker for engine timeout validity *)
  Definition is_valid_engine_timeout_b (t : Z) : bool :=
    (kMinWebAuthnTimeout <=? t) && (t <=? kMaxWebAuthnTimeout).

  (** ** 3. Core Verification Theorems *)

  (** Theorem 1: Fundamental Bounds Invariant
      For any integer input t, 1000 <= clamped_timeout(t) <= 600000. *)
  Theorem clamped_timeout_in_bounds :
    forall t : Z,
      kMinWebAuthnTimeout <= clamped_timeout t <= kMaxWebAuthnTimeout.
  Proof.
    intros t.
    unfold clamped_timeout, kMinWebAuthnTimeout, kMaxWebAuthnTimeout.
    lia.
  Qed.

  (** Corollary 1.1: clamped_timeout always satisfies [is_valid_engine_timeout]. *)
  Corollary clamped_timeout_valid :
    forall t : Z,
      is_valid_engine_timeout (clamped_timeout t).
  Proof.
    intros t.
    unfold is_valid_engine_timeout.
    apply clamped_timeout_in_bounds.
  Qed.

  (** Theorem 2: Equivalence of Boolean and Propositional Validity *)
  Theorem is_valid_engine_timeout_reflect :
    forall t : Z,
      is_valid_engine_timeout_b t = true <-> is_valid_engine_timeout t.
  Proof.
    intros t.
    unfold is_valid_engine_timeout_b, is_valid_engine_timeout.
    rewrite andb_true_iff.
    rewrite Z.leb_le, Z.leb_le.
    reflexivity.
  Qed.

  (** Theorem 3: Executable Validity Check Always Succeeds on Clamped Output *)
  Theorem clamped_timeout_valid_b :
    forall t : Z,
      is_valid_engine_timeout_b (clamped_timeout t) = true.
  Proof.
    intros t.
    apply is_valid_engine_timeout_reflect.
    apply clamped_timeout_valid.
  Qed.

  (** Theorem 4: Commutativity of Min/Max Clamping Formulations
      Proves that min(max_bound, max(min_bound, t)) = max(min_bound, min(max_bound, t)). *)
  Theorem clamped_timeout_sym_equiv :
    forall t : Z,
      clamped_timeout t = clamped_timeout_alt t.
  Proof.
    intros t.
    unfold clamped_timeout, clamped_timeout_alt, kMinWebAuthnTimeout, kMaxWebAuthnTimeout.
    lia.
  Qed.

  (** Theorem 5: Exact Piecewise Characterization
      - Underflow (< 1000ms) clamps to 1000ms.
      - In-bounds ([1000ms, 600000ms]) remains unchanged.
      - Overflow (> 600000ms) clamps to 600000ms. *)
  Theorem clamped_timeout_underflow :
    forall t : Z,
      t < kMinWebAuthnTimeout ->
      clamped_timeout t = kMinWebAuthnTimeout.
  Proof.
    intros t Hlt.
    unfold clamped_timeout, kMinWebAuthnTimeout, kMaxWebAuthnTimeout in *.
    lia.
  Qed.

  Theorem clamped_timeout_in_range_identity :
    forall t : Z,
      kMinWebAuthnTimeout <= t <= kMaxWebAuthnTimeout ->
      clamped_timeout t = t.
  Proof.
    intros t Hrange.
    unfold clamped_timeout, kMinWebAuthnTimeout, kMaxWebAuthnTimeout in *.
    lia.
  Qed.

  Theorem clamped_timeout_overflow :
    forall t : Z,
      t > kMaxWebAuthnTimeout ->
      clamped_timeout t = kMaxWebAuthnTimeout.
  Proof.
    intros t Hgt.
    unfold clamped_timeout, kMinWebAuthnTimeout, kMaxWebAuthnTimeout in *.
    lia.
  Qed.

  (** Theorem 6: Fixed-Point Characterization
      A timeout t is unchanged by clamping if and only if it is already within bounds. *)
  Theorem clamped_timeout_fixed_point_iff :
    forall t : Z,
      clamped_timeout t = t <-> is_valid_engine_timeout t.
  Proof.
    intros t.
    unfold is_valid_engine_timeout, clamped_timeout, kMinWebAuthnTimeout, kMaxWebAuthnTimeout.
    lia.
  Qed.

  (** Theorem 7: Idempotence of Clamping
      Re-clamping an already-clamped timeout across IPC/layer boundaries is a no-op. *)
  Theorem clamped_timeout_idempotent :
    forall t : Z,
      clamped_timeout (clamped_timeout t) = clamped_timeout t.
  Proof.
    intros t.
    unfold clamped_timeout, kMinWebAuthnTimeout, kMaxWebAuthnTimeout.
    lia.
  