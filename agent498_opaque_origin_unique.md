# Formal Verification Report: Opaque Origin Uniqueness in Chromium Blink

**Formal Theory Target**: `BlinkOriginOpaqueUniquenessSemantics.v`  
**Chromium Subsystem**: `url::Origin` / `blink::SecurityOrigin` (`services/network/public/cpp/origin.cc` & `url/origin.cc`)  
**Normative Specification**: WHATWG HTML Standard §7.5 (Origin)  
**Mathematical Property**: $\forall \text{id}_1, \text{id}_2 \in \mathbb{Z}, \text{id}_1 \neq \text{id}_2 \implies \text{OpaqueOrigin}(\text{id}_1) \neq \text{OpaqueOrigin}(\text{id}_2)$

---

## 1. Normative Specification Requirements (WHATWG HTML Standard §7.5)

In the Web Platform security model, the **origin** is the fundamental unit of isolation governing the Same-Origin Policy (SOP), storage partitioning, and cross-origin access control. According to the **WHATWG HTML Standard §7.5 (Origins)**, origins are classified into two distinct algebraic variants:

1. **Tuple Origins**: Consisting of a `(scheme, host, port, domain)` 4-tuple representing standard network endpoints (e.g., `https://example.com:443`).
2. **Opaque Origins**: An internal value with no accessible component parts, serialized strictly as the string `"null"`, for which the only meaningful operation is testing for equality.

### Normative Requirements for Opaque Origins
* **Creation Uniqueness**: Whenever the specification requires creating a *new opaque origin* (e.g., for `<iframe sandbox>` without `allow-same-origin`, `data:` URLs, `file:` URLs in certain contexts, or `Cross-Origin-Opener-Policy` enforcement), the user agent must instantiate an internal token guaranteed to be distinct from all previously and subsequently instantiated origins.
* **Same-Origin Comparison (§7.5.4)**: Two origins $A$ and $B$ are defined to be *same origin* if and only if:
  * If $A$ and $B$ are both tuple origins: their schemes, hosts, and ports are identical.
  * If $A$ and $B$ are both opaque origins: they are the **exact same instance** (referential/token identity).
  * Otherwise, they are *not* same origin.
* **Serialization Invariant (§7.5.5)**: The ASCII or Unicode serialization of any opaque origin is always `"null"`. Consequently, **serialization is non-injective**: two distinct opaque origins serialize to `"null"`, yet remain strictly cross-origin to one another ($\text{Serialize}(O_1) = \text{Serialize}(O_2) \centernot\implies \text{SameOrigin}(O_1, O_2)$).

---

## 2. Chromium Implementation Details and Invariants

In Chromium's multiprocess architecture, origins are represented across process boundaries by `url::Origin`, renderer-side by `blink::SecurityOrigin`, and serialized via Mojo IPC traits (`services/network/public/cpp/origin_mojom_traits.cc` / `url/mojom/origin_mojom_traits.cc`).

### Architecture of `url::Origin::Nonce`
In `url/origin.h` and `url/origin.cc` (and mirrored across the network service boundary in `services/network/public/cpp/`), Chromium represents an origin as an optional `url::Origin::Nonce` paired with a `url::SchemeHostPort` tuple:

```cpp
class COMPONENT_EXPORT(URL) Origin {
 public:
  // Creates a new opaque Origin guaranteed to be cross-origin to all
  // currently existing Origins.
  Origin();
  ...
 private:
  // The tuple is used for both tuple origins (e.g. https://example.com:80) as
  // well as for precursor information of opaque origins.
  SchemeHostPort tuple_;

  // The nonce is used for opaque origins. It is nullopt for tuple origins.
  absl::optional<Nonce> nonce_;
};
```

### Core Implementation Invariants

1. **Cryptographic Token Backing (`base::UnguessableToken`)**:
   An opaque origin's identity is backed by `url::Origin::Nonce`, which wraps a 128-bit `base::UnguessableToken`. When a new opaque origin is constructed or derived via `Origin::DeriveNewOpaqueOrigin()`, a fresh unguessable token is generated via the OS CSPRNG (`crypto::RandBytes`).
2. **Precursor Separation**:
   When an opaque origin is derived from an existing tuple origin (such as a `https://example.com` document creating a sandboxed iframe), `tuple_` retains `https://example.com` as the *precursor tuple* for CSP/reporting purposes, while `nonce_` is populated with a fresh `Nonce`. Crucially, equality (`operator==`) and `IsSameOriginWith()` on opaque origins compare **only the `nonce_`** and completely ignore differences or similarities in `tuple_`:

```cpp
bool Origin::operator==(const Origin& other) const {
  if (opaque() != other.opaque())
    return false;
  if (opaque())
    return *nonce_ == *other.nonce_; // Precursor tuple_ is ignored for equality!
  return tuple_ == other.tuple_;
}
```

3. **Monotonic Allocation Model**:
   In formal semantics, the generation of unique 128-bit unguessable tokens without collision is modeled as a strictly monotonic allocator state over $\mathbb{Z}$. Every call to allocate an opaque origin produces a fresh nonce identifier $\text{id} \in \mathbb{Z}$ and increments the global allocation counter, guaranteeing $\text{id}_1 \neq \text{id}_2$ across distinct allocations.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkOriginOpaqueUniquenessSemantics.v`. It models both Tuple and Opaque origins (including precursor tuples), the boolean and propositional Same-Origin relation, serialization non-injectivity, and stateful monotonic nonce allocation.

```coq
(** * BlinkOriginOpaqueUniquenessSemantics.v
    Formal verification of Opaque Origin Uniqueness in Chromium Blink
    Specification: WHATWG HTML Standard §7.5
    Implementation: url/origin.cc, services/network/public/cpp/origin.cc
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.

Open Scope Z_scope.

(** ** 1. Core Domain Types *)

(** Identifiers for schemes, hosts, ports, and cryptographic nonces. *)
Definition SchemeId := Z.
Definition HostId   := Z.
Definition PortId   := Z.
Definition NonceId  := Z.

(** Represents [url::SchemeHostPort]. *)
Record SchemeHostPort : Type := mkTuple {
  shp_scheme : SchemeId;
  shp_host   : HostId;
  shp_port   : PortId
}.

(** Decidable boolean equality for [SchemeHostPort]. *)
Definition shp_eqb (t1 t2 : SchemeHostPort) : bool :=
  (Z.eqb (shp_scheme t1) (shp_scheme t2)) &&
  (Z.eqb (shp_host t1) (shp_host t2)) &&
  (Z.eqb (shp_port t1) (shp_port t2)).

(** Represents [url::Origin] / [blink::SecurityOrigin].
    An origin is either:
    - [TupleOrigin]: A standard (scheme, host, port) origin.
    - [OpaqueOrigin]: A unique [NonceId] along with an optional precursor
      [SchemeHostPort] (used for CSP/auditing, ignored for Same-Origin checks). *)
Inductive Origin : Type :=
  | TupleOrigin  (tuple : SchemeHostPort)
  | OpaqueOrigin (nonce : NonceId) (precursor : option SchemeHostPort).

(** Helper constructor for a fresh opaque origin without a precursor. *)
Definition opaque_origin (id : NonceId) : Origin :=
  OpaqueOrigin id None.

(** Helper constructor for a derived opaque origin preserving a precursor. *)
Definition derive_opaque_origin (id : NonceId) (p : SchemeHostPort) : Origin :=
  OpaqueOrigin id (Some p).

(** Predicate checking whether an origin is opaque. *)
Definition is_opaque (o : Origin) : bool :=
  match o with
  | TupleOrigin _ => false
  | OpaqueOrigin _ _ => true
  end.

(** ** 2. Same-Origin Policy Semantics (HTML §7.5.4) *)

(** Mirrors [Origin::IsSameOriginWith] in Chromium.
    Notice that for [OpaqueOrigin], only the [nonce] is compared;
    the [precursor] is intentionally ignored per HTML §7.5.4 and url/origin.cc. *)
Definition same_origin_b (o1 o2 : Origin) : bool :=
  match o1, o2 with
  | TupleOrigin t1, TupleOrigin t2 => shp_eqb t1 t2
  | OpaqueOrigin id1 _, OpaqueOrigin id2 _ => Z.eqb id1 id2
  | _, _ => false
  end.

(** Strict Structural Equality of [Origin] values (includes precursor). *)
Definition origin_struct_eqb (o1 o2 : Origin) : bool :=
  match o1, o2 with
  | TupleOrigin t1, TupleOrigin t2 => shp_eqb t1 t2
  | OpaqueOrigin id1 None, OpaqueOrigin id2 None => Z.eqb id1 id2
  | OpaqueOrigin id1 (Some p1), OpaqueOrigin id2 (Some p2) =>
      (Z.eqb id1 id2) && (shp_eqb p1 p2)
  | _, _ => false
  end.

(** ** 3. Serialization Semantics (HTML §7.5.5) *)

Inductive SerializedOrigin : Type :=
  | SerNull
  | SerTuple (t : SchemeHostPort).

Definition serialize_origin (o : Origin) : SerializedOrigin :=
  match o with
  | TupleOrigin t => SerTuple t
  | OpaqueOrigin _ _ => SerNull
  end.

(** ** 4. Stateful Nonce Allocator Semantics *)

(** Models the global monotonic nonce generator in [url::Origin::Nonce]. *)
Record AllocatorState : Type := mkAllocState {
  next_nonce : NonceId
}.

(** Allocates a fresh opaque origin and advances the generator state. *)
Definition allocate_opaque_origin (st : AllocatorState) (precursor : option SchemeHostPort)
  : (Origin * AllocatorState) :=
  (OpaqueOrigin (next_nonce st) precursor, mkAllocState (next_nonce st + 1)).
```

---

## 4. Concrete Theorems and Complete Rocq / Coq Proofs

Below are the complete, admitted-free proofs verifying the target property and all supporting security invariants.

```coq
(** ** 5. Formal Verification & Proofs *)

(** *** Theorem 1: Primary Target Property — Opaque Origin Uniqueness (Propositional)
    Mathematical Property:
    id1 <> id2 -> opaque_origin(id1) <> opaque_origin(id2) *)
Theorem opaque_origin_uniqueness :
  forall (id1 id2 : NonceId),
    id1 <> id2 ->
    opaque_origin id1 <> opaque_origin id2.
Proof.
  intros id1 id2 Hneq Heq.
  unfold opaque_origin in Heq.
  inversion Heq as [Hid].
  apply Hneq.
  exact Hid.
Qed.

(** *** Theorem 2: Generalized Opaque Origin Structural Inequality
    Regardless of precursor tuples, distinct nonces imply distinct origins. *)
Theorem opaque_origin_general_uniqueness :
  forall (id1 id2 : NonceId) (p1 p2 : option SchemeHostPort),
    id1 <> id2 ->
    OpaqueOrigin id1 p1 <> OpaqueOrigin id2 p2.
Proof.
  intros id1 id2 p1 p2 Hneq Heq.
  inversion Heq as [Hid].
  apply Hneq.
  exact Hid.
Qed.

(** *** Theorem 3: Same-Origin Isolation for Distinct Nonces
    Two opaque origins with distinct nonces are strictly cross-origin
    ([same_origin_b = false]), even if they share the exact same precursor tuple! *)
Theorem opaque_same_origin_isolation :
  forall (id1 id2 : NonceId) (p1 p2 : option SchemeHostPort),
    id1 <> id2 ->
    same_origin_b (OpaqueOrigin id1 p1) (OpaqueOrigin id2 p2) = false.
Proof.
  intros id1 id2 p1 p2 Hneq.
  simpl.
  apply Z.eqb_neq.
  exact Hneq.
Qed.

(** *** Theorem 4: Exact Equivalence of Nonce Equality and Same-Origin for Opaque Origins *)
Theorem opaque_same_origin_iff_nonce_eq :
  forall (id1 id2 : NonceId) (p1 p2 : option SchemeHostPort),
    same_origin_b (OpaqueOrigin id1 p1) (OpaqueOrigin id2 p2) = true <-> id1 = id2.
Proof.
  intros id1 id2 p1 p2.
  simpl.
   apply Z.eqb_eq.
Qed.

(** *** Theorem 5: Opaque and Tuple Origins are Strictly Disjoint
    An opaque origin is never same-origin with any tuple origin, even if the
    opaque origin was derived from that exact tuple origin as its precursor. *)
Theorem opaque_tuple_disjoint :
  forall (id : NonceId) (t : SchemeHostPort),
    same_origin_b (OpaqueOrigin id (Some t)) (TupleOrigin t) = false /\
    same_origin_b (TupleOrigin t) (OpaqueOrigin id (Some t)) = false.
Proof.
  intros id t.
  simpl.
  split; reflexivity.
Qed.

(** *** Theorem 6: Reflexivity, Symmetry, and Transitivity of [same_origin_b] *)

Lemma shp_eqb_refl : forall t : SchemeHostPort, shp_eqb t t = true.
Proof.
  intros [s h p].
  unfold shp_eqb; simpl.
  repeat rewrite Z.eqb_refl.
  reflexivity.
Qed.

Lemma shp_eqb_eq : forall t1 t2 : SchemeHostPort,
  shp_eqb t1 t2 = true <-> t1 = t2.
Proof.
  intros [s1 h1 p1] [s2 h2 p2].
  unfold shp_eqb; simpl.
  rewrite andb_true_iff, andb_true_iff.
  repeat rewrite Z.eqb_eq.
  split.
  - intros [[Hs Hh] Hp]. subst. reflexivity.
  - intros Heq. inversion Heq. subst. auto.
Qed.

Theorem same_origin_b_refl :
  forall o : Origin, same_origin_b o o = true.
Proof.
  intros [t | id p].
  - simpl. apply shp_eqb_refl.
  - simpl. apply Z.eqb_refl.
Qed.

Theorem