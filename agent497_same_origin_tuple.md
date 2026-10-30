# Formal Verification of Chromium's Same-Origin Tuple Equivalence Semantics

**Target File:** `BlinkOriginSameOriginTupleSemantics.v`  
**Chromium Subsystem:** `url::Origin` / `blink::SecurityOrigin` (`url/origin.cc`, `url/scheme_host_port.cc`, `services/network/public/cpp/...`)  
**Normative Standards:** WHATWG HTML Standard §7.5 (Origin), IETF RFC 6454 (The Web Origin Concept)  
**Mathematical Property:** Tuple equivalence ($\text{scheme}_1 = \text{scheme}_2 \land \text{host}_1 = \text{host}_2 \land \text{port}_1 = \text{port}_2$) forms a strict Equivalence Relation (Reflexive, Symmetric, Transitive) over the space of non-opaque tuple origins, whereas full origin equivalence forms a Partial Equivalence Relation (PER) across the complete origin domain (including opaque origins).

---

## 1. Normative Specification Analysis

The **Same-Origin Policy (SOP)** is the foundational security boundary of the Web Platform. It isolates potentially malicious documents and scripts from accessing resources, DOM state, cookies, and storage belonging to different origins.

### 1.1 WHATWG HTML Standard §7.5 (Origins)
According to the WHATWG HTML Living Standard (§7.5), an **origin** is one of two distinct variants:
1. **An opaque origin:** An internal value with no serialized inner structure (beyond a cryptographically random nonce or capability token), for which the only meaningful operation is testing for exact identity against itself.
2. **A tuple origin:** Consisting of:
   - A **scheme** (an ASCII string, lowercase, e.g., `"https"`).
   - A **host** (a domain, IPv4 address, IPv6 address, or opaque host).
   - A **port** (null or a 16-bit unsigned integer $p \in [0, 65535]$).
   - An optional **domain** (null or a domain, used exclusively for legacy `document.domain` mutation in `same origin-domain` checks, deliberately excluded from strict `same origin` checks).

#### The "Same Origin" Algorithm (HTML §7.5)
Two origins, $A$ and $B$, are said to be **same origin** if the following algorithm returns `true`:
1. If $A$ and $B$ are the same opaque origin, then return `true`.
2. If $A$ and $B$ are both tuple origins and their schemes, hosts, and ports are identical, then return `true`.
3. Return `false`.

### 1.2 IETF RFC 6454 (The Web Origin Concept)
In RFC 6454 §5 ("Comparing Origins"), two origins are "the same" if:
- Neither is a globally unique identifier (opaque), and their scheme, host, and port components are identical after canonicalization.
- Or both are the exact same globally unique identifier reference.

*Note on Specification Evolution:* While HTML §7.5 considers an opaque origin equal to *itself* (same reference/nonce), certain low-level tuple-only comparison APIs treat any comparison involving an opaque origin as `false`. In our formalization below, we model both **pure tuple equivalence** (where opaque origins fail tuple matching, forming a Partial Equivalence Relation over all origins and a total Equivalence Relation over tuple origins) and **full origin identity** (where opaque nonces are compared).

---

## 2. Chromium & Blink Implementation Analysis

In Chromium, origin representation is split across the browser/network boundary (`url::Origin` in `url/origin.cc` and Mojo traits in `services/network/public/cpp/`) and the renderer engine (`blink::SecurityOrigin` in `third_party/blink/renderer/platform/weborigin/security_origin.cc`).

### 2.1 Architecture of `url::Origin` and `url::SchemeHostPort`
Chromium decomposes an origin into two primary components inside `url::Origin`:
```cpp
class COMPONENT_EXPORT(URL) Origin {
 private:
  // The tuple is used for all non-opaque origins (e.g., https://example.com:443).
  // If the origin is opaque, `tuple_` may still hold a precursor origin, 
  // while `nonce_` is populated with a base::UnguessableToken.
  SchemeHostPort tuple_;
  absl::optional<Nonce> nonce_;
};
```

The underlying tuple comparison is delegated to `url::SchemeHostPort` (`url/scheme_host_port.h` / `.cc`):
```cpp
class COMPONENT_EXPORT(URL) SchemeHostPort {
 public:
  bool operator==(const SchemeHostPort& other) const {
    return scheme_ == other.scheme_ && 
           host_ == other.host_ && 
           port_ == other.port_;
  }
 private:
  std::string scheme_;
  std::string host_;
  uint16_t port_ = 0;
};
```

### 2.2 `IsSameOriginWith` Implementation (`url/origin.cc` & `services/network/public/cpp/`)
When `Origin::IsSameOriginWith(const Origin& other)` or `operator==` is invoked:
```cpp
bool Origin::IsSameOriginWith(const Origin& other) const {
  // 1. Both must share the same opacity state.
  // 2. If opaque, their nonces must match.
  // 3. If non-opaque (tuple origins), their SchemeHostPort tuples must match.
  return std::tie(nonce_, tuple_) == std::tie(other.nonce_, other.tuple_);
}
```
When evaluating strict **tuple equivalence** (e.g., matching against network rules, CORS origin patterns, or storage keys restricted to standard network schemes in `services/network/public/cpp/`):
1. Both origins are checked for `!opaque()`.
2. The canonicalized `scheme` (represented as an interned ID or canonical ASCII string), `host` (canonicalized via `url::CanonicalizeHost`), and `port` (uint16_t normalized to default port for standard schemes) are compared via component-wise equality:
$$\text{SameTuple}(O_1, O_2) \iff \neg\text{opaque}(O_1) \land \neg\text{opaque}(O_2) \land (s_1 = s_2) \land (h_1 = h_2) \land (p_1 = p_2)$$

### 2.3 Security Invariants in Chromium
1. **Canonicalization Prerequisite:** `SchemeHostPort` enforces that strings are canonicalized upon construction. Equivalence relies on syntactic equality of canonical forms coinciding with semantic equality.
2. **Transitivity of Access Control:** If Execution Context $A$ is same-origin with $B$, and $B$ is same-origin with $C$, then $A$ MUST be same-origin with $C$. A violation of transitivity would allow privilege escalation via cross-frame scripting (e.g., $A$ scripts $B$, $B$ scripts $C$, granting $A$ indirect control over $C$ despite $A \not\equiv C$).
3. **Symmetry of Isolation:** If $A$ can access $B$ under SOP, $B$ can access $A$.
4. **Reflexivity of Tuple Origins:** Every valid tuple origin is same-origin with itself, ensuring a frame can always access its own DOM and local storage.

---

## 3. Formal Specification in Rocq / Coq

We construct the formal theory `BlinkOriginSameOriginTupleSemantics.v`. To ensure the proofs are completely self-contained, executable, and compatible with `ZArith`, `Lia`, and `Bool`, we represent canonicalized schemes, hosts, ports, and cryptographic nonces using arbitrary mathematical integers (`Z`). Because canonical strings in memory are finite byte arrays, they inject bijectively into $\mathbb{Z}$.

### 3.1 Domain Modeling
- **`TupleOrigin`**: A record containing `scheme : Z`, `host : Z`, and `port : Z`, along with a well-formedness predicate restricting `port` to the valid TCP/UDP port range $[0, 65535]$.
- **`Origin`**: An algebraic data type encompassing both `OriginTuple (t : TupleOrigin)` and `OriginOpaque (nonce : Z) (precursor : option TupleOrigin)`.
- **Boolean vs. Propositional Equivalence**: We define executable boolean deciders (`tuple_eqb`, `same_origin_tuple_only_b`, `same_origin_full_b`) that mirror C++ runtime checks, alongside propositional specifications (`TupleEq`, `SameOriginTupleOnly`, `SameOriginFull`), and prove their exact reflection (`iff`).

---

## 4. Formal Verification (`BlinkOriginSameOriginTupleSemantics.v`)

Below is the complete, self-contained, admitted-free Rocq/Coq verification artifact.

```coq
(** * BlinkOriginSameOriginTupleSemantics.v
    Formal Verification of Chromium's Same-Origin Tuple Equivalence
    Target: services/network/public/cpp/origin.cc, url/origin.cc
    Specifications: WHATWG HTML Standard §7.5, IETF RFC 6454
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micega.Lia.
From Coq Require Import Relations.Relations.
From Coq Require Import Classes.RelationClasses.

Open Scope Z_scope.
Open Scope bool_scope.

(** ========================================================================= *)
(** * 1. Data Types and Structural Invariants                                 *)
(** ========================================================================= *)

(** Canonicalized schemes and hosts are finite byte sequences, which inject 
    into Z. Ports are 16-bit unsigned integers (0 <= port <= 65535). *)
Record TupleOrigin : Type := mkTuple {
  scheme : Z;
  host   : Z;
  port   : Z
}.

(** Well-formedness invariant for a canonicalized Chromium SchemeHostPort *)
Definition wf_tuple (t : TupleOrigin) : Prop :=
  0 <= scheme t /\
  0 <= host t /\
  0 <= port t <= 65535.

Definition wf_tuple_b (t : TupleOrigin) : bool :=
  (0 <=? scheme t) && (0 <=? host t) && (0 <=? port t) && (port t <=? 65535).

Lemma wf_tuple_reflect : forall t,
   wf_tuple_b t = true <-> wf_tuple t.
Proof.
  intros [s h p]. unfold wf_tuple_b, wf_tuple. simpl.
  repeat rewrite andb_true_iff.
  repeat rewrite Z.leb_le.
  lia.
Qed.

(** Full Chromium url::Origin representation:
    Either a valid TupleOrigin (SchemeHostPort), or an Opaque origin carrying
    an UnguessableToken (nonce) and an optional precursor TupleOrigin. *)
Inductive Origin : Type :=
  | OriginTuple  (t : TupleOrigin)
  | OriginOpaque (nonce : Z) (precursor : option TupleOrigin).

(** ========================================================================= *)
(** * 2. Tuple Equivalence Definitions (Propositional & Boolean)              *)
(** ========================================================================= *)

(** Propositional specification of tuple equivalence:
    (scheme1 = scheme2 /\ host1 = host2 /\ port1 = port2) *)
Definition TupleEq (t1 t2 : TupleOrigin) : Prop :=
  scheme t1 = scheme t2 /\
  host t1 = host t2 /\
  port t1 = port t2.

(** Executable C++ operator== equivalent for url::SchemeHostPort *)
Definition tuple_eqb (t1 t2 : TupleOrigin) : bool :=
  (scheme t1 =? scheme t2) &&
  (host t1 =? host t2) &&
  (port t1 =? port t2).

(** Reflection theorem: boolean decision procedure matches propositional spec *)
Theorem tuple_eqb_spec : forall t1 t2 : TupleOrigin,
  tuple_eqb t1 t2 = true <-> TupleEq t1 t2.
Proof.
  intros [s1 h1 p1] [s2 h2 p2].
  unfold tuple_eqb, TupleEq. simpl.
  repeat rewrite andb_true_iff.
  repeat rewrite Z.eqb_eq.
  tauto.
Qed.

Theorem tuple_eqb_false_spec : forall t1 t2 : TupleOrigin,
  tuple_eqb t1 t2 = false <-> ~ TupleEq t1 t2.
Proof.
  intros t1 t2.
  pose proof (tuple_eqb_spec t1 t2) as H.
  destruct (tuple_eqb t1 t2) eqn:Heq; split; intros H1; try congruence; try tauto.
  intros H2. apply H in H2. congruence.
Qed.

(** Equivalence between TupleEq and Leibniz equality on TupleOrigin records *)
Theorem TupleEq_leibniz : forall t1 t2 : TupleOrigin,
  TupleEq t1 t2 <-> t1 = t2.
Proof.
  intros [s1 h1 p1] [s2 h2 p2].
  unfold TupleEq. simpl.
  split.
  - intros [Hs [Hh Hp]]. subst. reflexivity.
  - intros Heq. inversion Heq. auto.
Qed.

(** ========================================================================= *)
(** * 3. Algebraic Properties of Tuple Equivalence                            *)
(** ========================================================================= *)

(** Theorem 3.1: Tuple Equivalence is Reflexive *)
Theorem TupleEq_refl : forall t : TupleOrigin,
  TupleEq t t.
Proof.
  intros [s h p].
  unfold TupleEq. simpl.
   repeat split; lia.
Qed.

(** Theorem 3.2: Tuple Equivalence is Symmetric *)
Theorem TupleEq_sym : forall t1 t2 : TupleOrigin,
  TupleEq t1 t2 -> TupleEq t2 t1.
Proof.
  intros [s1 h1 p1] [s2 h2 p2].
  unfold TupleEq. simpl.
  intros [Hs [Hh Hp]].
  repeat split; lia.
Qed.

(** Theorem 3.3: Tuple Equivalence is Transitive *)
Theorem TupleEq_trans : forall t1 t2 t3 : TupleOrigin,
  TupleEq t1 t2 -> TupleEq t2 t3 -> TupleEq t1 t3.
Proof.
  intros [s1 h1 p1] [s2 h2 p2] [s3 h3 p3].
  unfold TupleEq. simpl.
  intros [Hs12 [Hh12 Hp12]] [Hs23 [Hh23 Hp23]].
  repeat split; lia.
Qed.

(** Register TupleEq as a formal Coq Equivalence Relation *)
#[export] Instance TupleEq_Equivalence : Equivalence TupleEq := {
  Equivalence_Reflexive  := TupleEq_refl;
  Equivalence_Symmetric  := TupleEq_sym;
  Equivalence_Transitive := TupleEq_trans
}.

(** Corollary: Executable boolean tuple_eqb is reflexive, symmetric, transitive *)
Corollary tuple_eqb_refl : forall t : TupleOrigin,
  tuple_eqb t t = true.
Proof.
  intros t. apply tuple_eqb_spec. apply TupleEq_refl.
Qed.

Corollary tuple_eq