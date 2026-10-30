# Formal Verification of Chromium Blink `PasswordCredential` Non-Empty Validity Invariants

**Target Component:** `third_party/blink/renderer/modules/credentialmanagement/password_credential.cc`  
**Normative Specification:** W3C Credential Management Level 1 (§5.1, §5.2, §5.3)  
**Formal Theory Module:** `BlinkPasswordCredentialNonEmptySemantics.v`  
**Verification Engine:** Rocq / Coq Proof Assistant (`ZArith`, `Lia`, `Bool`)  
**Mathematical Invariant:** $\text{valid\_password\_cred}(u_{\text{len}}, p_{\text{len}}) = (0 < u_{\text{len}}) \land (0 < p_{\text{len}})$

---

## 1. Normative W3C Credential Management Specification Requirements

In the Web Authentication (WebAuthn) and broader W3C Credential Management ecosystem, `PasswordCredential` objects share the `navigator.credentials` orchestration pipeline with `PublicKeyCredential` (Passkeys) and `FederatedCredential`. Ensuring strict input validation at the `PasswordCredential` construction boundary is essential to prevent malformed state injection into the browser's underlying password store and credential mediation UI.

### 1.1 W3C Credential Management Level 1 (§5.1 - §5.3)

The normative construction semantics for `PasswordCredential` are defined in **Section 5.1 (`PasswordCredential` Interface)**, **Section 5.2 (`PasswordCredentialData` Dictionary)**, and **Section 5.3 (`HTMLFormElement` Overloading)** of the W3C Credential Management Level 1 specification.

A `PasswordCredential` can be instantiated via two overloaded WebIDL constructors:
```webidl
[Exposed=Window, SecureContext]
interface PasswordCredential : Credential {
  constructor(HTMLFormElement form);
  constructor(PasswordCredentialData data);
  readonly attribute USVString password;
  readonly attribute USVString name;
  readonly attribute USVString iconURL;
};

dictionary PasswordCredentialData : CredentialData {
  required USVString password;
  USVString name;
  USVString iconURL;
  required USVString origin;
};

dictionary CredentialData {
  required USVString id;
};
```

#### Normative Validation Rules
When the `PasswordCredential(data)` constructor is invoked, the specification mandates the following validation steps:

1. **ID (Username) Non-Emptiness:** Inherited from `CredentialData`, the `id` member represents the user's identifier (username). Under **§5.2.1 ("Create a `PasswordCredential` from `PasswordCredentialData`")**:
   * *Step 2:* If `data.id` is the empty string (`""`), throw a `TypeError` (or `NotSupportedError` in legacy spec revisions; standardized as `TypeError` in modern Blink/W3C WebIDL).
2. **Password Non-Emptiness:** Under **§5.2.1**:
   * *Step 3:* If `data.password` is the empty string (`""`), throw a `TypeError`.

Similarly, when constructed from an `HTMLFormElement` (**§5.3.1 "Create a `PasswordCredential` from an `HTMLFormElement`"**), the extracted `id` (mapped from `autocomplete="username"`) and `password` (mapped from `autocomplete="current-password"` or `autocomplete="new-password"`) are passed directly into the `PasswordCredentialData` creation algorithm, triggering the exact same non-empty validation predicates.

### 1.2 Security Implications for WebAuthn / Passkey Mediation
In modern hybrid authentication flows (such as Conditional UI / Passkey Autofill alongside password fallback via `navigator.credentials.get({ password: true, publicKey: ... })`), the browser's `CredentialManager` Mojo interface processes credentials uniformly. If a `PasswordCredential` were permitted to have a zero-length identifier ($u_{\text{len}} \le 0$) or a zero-length secret ($p_{\text{len}} \le 0$), it could induce:
* **UI Spoofing / Blank Account Selection:** Rendering an account chooser entry with an empty username string.
* **Silent Unauthenticated Submission:** Storing or transmitting a blank secret without user awareness, bypassing client-side entropy checks.
* **IPC Deserialization Faults:** Violating `DCHECK(!id.IsEmpty())` assertions across the Blink-to-Browser Mojo boundary (`blink::mojom::CredentialInfo`).

---

## 2. Chromium Blink Implementation Analysis

In Chromium's Blink rendering engine, the normative specification requirements are enforced in `third_party/blink/renderer/modules/credentialmanagement/password_credential.cc`.

### 2.1 Source Code Inspection (`password_credential.cc`)

```cpp
// third_party/blink/renderer/modules/credentialmanagement/password_credential.cc

PasswordCredential* PasswordCredential::Create(
    const PasswordCredentialData* data,
    ExceptionState& exception_state) {
  if (data->id().empty()) {
    exception_state.ThrowTypeError("'id' must not be empty.");
    return nullptr;
  }
  if (data->password().empty()) {
    exception_state.ThrowTypeError("'password' must not be empty.");
    return nullptr;
  }

  KURL icon_url = ParseStringAsURL(data->iconURL(), exception_state);
  if (exception_state.HadException())
    return nullptr;

  return MakeGarbageCollected<PasswordCredential>(
      data->id(), data->password(), data->name(), icon_url);
}
```

When constructed via an `HTMLFormElement`, `PasswordCredential::Create(HTMLFormElement* form, ExceptionState& exception_state)` extracts the form fields into a `PasswordCredentialData` instance and delegates directly to `PasswordCredential::Create(data, exception_state)`:

```cpp
// Delegation invariant in PasswordCredential::Create(HTMLFormElement*, ExceptionState&)
PasswordCredentialData* data = PasswordCredentialData::Create();
// ... [extracts username and password from form elements] ...
return PasswordCredential::Create(data, exception_state);
```

### 2.2 Implementation Invariants

Let $u_{\text{len}} \in \mathbb{Z}$ denote the length of `data->id()` and $p_{\text{len}} \in \mathbb{Z}$ denote the length of `data->password()`. In Blink's `WTF::String` implementation:
* `String::empty()` evaluates to `true` if and only if the string is null or its character length is $0$ (in general integer domain modeling, $\text{len} \le 0$).
* Conversely, `!String::empty()` evaluates to `true` if and only if $0 < \text{len}$.

The control flow of `PasswordCredential::Create` establishes three strict invariants:

1. **Sequential Guard Evaluation:**
   * Guard 1 checks `data->id().empty()`. If $u_{\text{len}} \le 0$, execution halts immediately with `TypeError("'id' must not be empty.")` and returns `nullptr`.
   * Guard 2 checks `data->password().empty()`. This guard is only reached if $u_{\text{len}} > 0$. If $p_{\text{len}} \le 0$, execution halts with `TypeError("'password' must not be empty.")` and returns `nullptr`.
2. **Boolean Conjunction Equivalence:**
   Despite being implemented as sequential early-return `if` statements in C++, the reachability of `MakeGarbageCollected<PasswordCredential>(...)` (assuming valid `iconURL`) is mathematically equivalent to the boolean conjunction:
   $$\text{valid\_password\_cred}(u_{\text{len}}, p_{\text{len}}) \iff (0 < u_{\text{len}}) \land (0 < p_{\text{len}})$$
3. **Post-Construction Heap Invariant:**
   For any non-null `PasswordCredential*` object allocated on the Oilpan heap (`MakeGarbageCollected`), both `cred->id().length() > 0` and `cred->password().length() > 0` hold invariantly throughout the object's lifetime (since both attributes are `readonly` in WebIDL and immutable in the C++ class definition).

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization module `BlinkPasswordCredentialNonEmptySemantics.v`. It models both the pure mathematical validity predicate and the imperative sequential exception-throwing semantics of `password_credential.cc`, followed by machine-checked proofs of their equivalence and security properties.

```coq
(** * BlinkPasswordCredentialNonEmptySemantics.v
    Formal verification of Chromium Blink's PasswordCredential
    username (id) and password non-empty validity invariants.
    
    Source: third_party/blink/renderer/modules/credentialmanagement/password_credential.cc
    Spec:   W3C Credential Management Level 1, Section 5.1 & 5.2
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import Lia.

Open Scope Z_scope.
Open Scope bool_scope.

(* ========================================================================== *)
(* 1. Mathematical Validity Predicate                                         *)
(* ========================================================================== *)

(** The core mathematical property governing whether a username length [u_len]
    and password length [p_len] form a valid PasswordCredential. *)
Definition valid_password_cred (u_len p_len : Z) : bool :=
  (0 <? u_len) && (0 <? p_len).

(** Propositional counterpart of [valid_password_cred]. *)
Definition ValidPasswordCredProp (u_len p_len : Z) : Prop :=
  0 < u_len /\ 0 < p_len.

(* ========================================================================== *)
(* 2. Blink C++ Implementation Model (password_credential.cc)                 *)
(* ========================================================================== *)

(** Models the discrete exception states thrown by Blink's [ExceptionState]
    during [PasswordCredential::Create]. *)
Inductive BlinkException : Type :=
  | ExTypeErrorIdEmpty : BlinkException       (* "'id' must not be empty." *)
  | ExTypeErrorPasswordEmpty : BlinkException (* "'password' must not be empty." *)
  | ExTypeErrorInvalidIconURL : BlinkException.

(** Models the Oilpan heap-allocated [PasswordCredential] object. *)
Record PasswordCredentialObj : Type := mkPasswordCredential {
  cred_id_len : Z;
  cred_password_len : Z;
  cred_name_len : Z;
  cred_icon_url_valid : bool
}.

(** Models the return value of [PasswordCredential::Create]: either a
    valid Oilpan pointer [ Some cred ] or [ None ] accompanied by an
    [ExceptionState] mutation. *)
Inductive CreateResult : Type :=
  | CreateSuccess (cred : PasswordCredentialObj) : CreateResult
  | CreateFailure (ex : BlinkException) : CreateResult.

(** Models [WTF::String::empty()] in Blink for length [len].
    In WTF::String, lengths are non-negative, and empty() is (len <=? 0). *)
Definition blink_string_empty (len : Z) : bool :=
  len <=? 0.

(** Exact control-flow model of [PasswordCredential::Create] in
    [third_party/blink/renderer/modules/credentialmanagement/password_credential.cc]. *)
Definition blink_password_credential_create
  (u_len p_len name_len : Z) (icon_url_ok : bool) : CreateResult :=
  if blink_string_empty u_len then
    CreateFailure ExTypeErrorIdEmpty
  else if blink_string_empty p_len then
    CreateFailure ExTypeErrorPasswordEmpty
  else if negb icon_url_ok then
    CreateFailure ExTypeErrorInvalidIconURL
  else
    CreateSuccess (mkPasswordCredential u_len p_len name_len icon_url_ok).

(** Predicate stating that [CreateResult] succeeded and returned a non-null
    [PasswordCredential] object. *)
Definition is_create_success (res : CreateResult) : bool :=
  match res with
  | CreateSuccess _ => true
  | CreateFailure _ => false
  end.
```

---

## 4. Concrete Theorems and Complete Proofs

We now state and prove the core verification theorems in Rocq/Coq. Every theorem is proved completely using `ZArith`, `Bool`, and `Lia` with **zero admitted lemmas**.

```coq
(* ========================================================================== *)
(* 3. Formal Theorems and Proofs                                              *)
(* ========================================================================== *)

(** Theorem 1: Reflection equivalence between the boolean specification
    [valid_password_cred] and the propositional specification [ValidPasswordCredProp]. *)
Theorem valid_password_cred_iff :
  forall (u_len p_len : Z),
    valid_password_cred u_len p_len = true <-> ValidPasswordCredProp u_len p_len.
Proof.
  intros u_len p_len.
  unfold valid_password_cred, ValidPasswordCredProp.
  rewrite andb_true_iff.
  rewrite !Z.ltb_lt.
  reflexivity.
Qed.

(** Theorem 2: Exact negative reflection for [valid_password_cred].
    A credential is invalid iff the username is empty/non-positive OR the
    password is empty/non-positive. *)
Theorem valid_password_cred_false_iff :
  forall (u_len p_len : Z),
    valid_password_cred u_len p_len = false <-> (u_len <= 0 \/ p_len <= 0).
Proof.
  intros u_len p_len.
  unfold valid_password_cred.
  rewrite andb_false_iff.
  rewrite !Z.ltb_ge.
  reflexivity.
Qed.

(** Theorem 3: Negation bridge between Blink's [WTF::String::empty()] check
    and the strict positivity check [(0 <? len)]. *)
Lemma negb_blink_string_empty_eq :
  forall (len : Z),
    negb (blink_string_empty len) = (0 <? len).
Proof.
  intros len.
  unfold blink_string_empty.
  destruct (0 <? len) eqn:Hlt; destruct (len <=? 0) eqn:Hle; simpl; auto.
  - apply Z.ltb_lt in Hlt. apply Z.leb_le in Hle. lia.
  - apply Z.ltb_ge in Hlt. apply Z.leb_gt in Hle. lia.
Qed.

(** Theorem 4: Equivalence between Blink's sequential C++ guard clauses
    and the mathematical conjunction [valid_password_cred].
    When iconURL parsing succeeds, [blink_password_credential_create] succeeds
    if and only if [valid_password_cred u_len p_len = true]. *)
Theorem blink_create_matches_valid_password_cred :
  forall (u_len p_len name_len : Z),
    is_create_success (blink_password_credential_create u_len p_len name_len true) =
    valid_password_cred u_len p_len.
Proof.
  intros u_len p_len name_len.
  unfold blink_password_credential_create, valid_password_cred.
  rewrite <- (negb_blink_string_empty_eq u_len).
  rewrite <- (negb