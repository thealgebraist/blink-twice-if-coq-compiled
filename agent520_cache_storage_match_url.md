# Formal Verification Report: Blink Cache Storage Request URL Matching Semantics

**Target Component:** `third_party/blink/renderer/modules/cache_storage/cache.cc`  
**Specification:** W3C Service Workers Specification §5.4 (`Cache` Interface) & §5.5 (Query Cache Algorithm)  
**Formal Theory Target:** `BlinkCacheStorageRequestMatchingSemantics.v`  
**Verified Property:** Cache request matching satisfies exact URL equality reflexivity, query canonicalization idempotence, and query soundness across `ignoreSearch` option states.

---

## 1. Normative Specification Requirements

The W3C Service Workers specification defines the behavior of `Cache.prototype.match`, `Cache.prototype.matchAll`, `Cache.prototype.put`, and `Cache.prototype.delete` via the central **Query Cache** algorithm (Service Workers §5.5.4) and **Request Matching** algorithm (Service Workers §5.5.5).

### 1.1 Request Matching Algorithm (Service Workers §5.5.5)
Given a query request $Q$, a stored request $S$ from a request-response pair in the cache, and a `CacheQueryOptions` dictionary $O$ (containing `ignoreSearch`, `ignoreMethod`, and `ignoreVary`), the specification mandates the following evaluation sequence for URL matching:

1. **Method Validation:** Let $M_Q$ be $Q$'s method. If $O.\text{ignoreMethod}$ is `false` and $M_Q \notin \{\text{"GET"}, \text{"HEAD"}\}$, return an empty list (do not match).
2. **URL Extraction:** Let $U_Q$ be $Q$'s URL, and $U_S$ be $S$'s URL.
3. **Query String Stripping (`ignoreSearch`):** If $O.\text{ignoreSearch}$ is `true`, set both $U_Q$'s `query` component and $U_S$'s `query` component to `null` (using a clone of the URL record).
4. **URL Serialization & Equality:** Following the WHATWG URL Standard (§4.5 URL equivalence), two URLs $A$ and $B$ are equivalent if and only if their serialized forms (with the `exclude fragment flag` set, as Service Worker Cache storage strips fragments upon entry/query per §5.4) are byte-for-byte identical:
   $$\text{ URL\_Equals}(U_Q, U_S, \text{exclude\_fragment}=\text{true}) \iff \text{Serialize}(U_Q_{\setminus \text{fragment}}) = \text{Serialize}(U_S_{\setminus \text{fragment}})$$

### 1.2 Mathematical Invariants Required by the Spec
- **Reflexivity:** For any valid `GET` request $R$ stored in the cache (whose fragment is already normalized out) and any `CacheQueryOptions` $O$, matching $R$ against itself must succeed (ignoring `Vary` header discrepancies on an accompanying response).
- **Soundness under Default Options:** When $O.\text{ignoreSearch} = \text{false}$, if `RequestMatches(Q, S, O)` returns `true`, then the scheme, host, port, path, and query components of $Q$ and $S$ must be strictly equal.
- **Soundness under `ignoreSearch`:** When $O.\text{ignoreSearch} = \text{true}$, if `RequestMatches(Q, S, O)` returns `true`, then the scheme, host, port, and path components of $Q$ and $S$ must be strictly equal, regardless of their query components.

---

## 2. Blink Implementation Details & Invariants

In Chromium's Blink rendering engine, the JavaScript bindings for `Cache` delegate to `blink::Cache` implemented in `third_party/blink/renderer/modules/cache_storage/cache.cc`.

### 2.1 Execution Path in `cache.cc`
1. **Entry Point (`Cache::MatchImpl` / `Cache::DeleteImpl` / `Cache::MatchAllImpl`):**
   - Accepts a `const V8RequestInfo*` (which resolves to either a `Request*` or a USVString URL) and `const CacheQueryOptions*`.
   - If the input is a string, Blink constructs an internal `Request` object via `Request::Create(script_state, input_string, exception_state)`, which parses and canonicalizes the URL using `KURL` (`url::GURL` / `blink::KURL`).
2. **Fragment Stripping & URL Canonicalization:**
   - Before dispatching the Mojo IPC call or evaluating local cache structures, Blink normalizes the `KURL`. Specifically, in `FetchRequestData` and `Cache` preparation, fragments are stripped (`KURL::RemoveFragmentIdentifier()`).
3. **Method Guards:**
   - In `Cache::MatchImpl` and `Cache::MatchAllImpl`, Blink checks:
     ```cpp
     if (request->method() != http_names::kGET && !options->ignoreMethod()) {
       return ScriptPromise::CastUndefined(script_state); // Resolves to undefined / empty
     }
     ```
4. **Mojo IPC & Storage Evaluation:**
   - Blink converts `CacheQueryOptions` into `mojom::blink::CacheQueryOptionsPtr` via `mojo::ConvertTo<mojom::blink::CacheQueryOptionsPtr>(options)`.
   - The request URL (`KURL`) and options are passed over Mojo (`remote_cache_->Match(...)`) to the Storage Service (`content::cache_storage` / `storage::CacheStorageCache`), which executes the exact URL comparison logic over indexed `GURL` instances, stripping the query component via `GURL::Replacements::ClearQuery()` when `options->ignore_search` is set.

### 2.2 Implementation Invariants
1. **Canonical Representation:** All URLs in `blink::Request` are stored as canonicalized `blink::KURL` instances where components (scheme, host, port, path, query, fragment) are indexed by deterministic integer offsets.
2. **Side-Effect Free Projections:** Stripping the fragment or query component (`RemoveFragmentIdentifier`, `ClearQuery`) is a pure, idempotent projection over the `KURL` structure.
3. **Boolean Decidability:** `KURL` equality (`operator==`) is an equivalence relation backed by exact string comparison on the canonical spec buffer.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of Blink's Cache Storage Request URL matching semantics (`BlinkCacheStorageRequestMatchingSemantics.v`). It models HTTP methods, canonicalized URL records, `CacheQueryOptions`, URL component stripping projections, and the normative matching algorithm.

```coq
(** * BlinkCacheStorageRequestMatchingSemantics.v
    Formal verification of W3C Service Workers §5.4 / §5.5 Request URL Matching
    and Chromium Blink's implementation in:
    third_party/blink/renderer/modules/cache_storage/cache.cc
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micega.Lia.
From Coq Require Import Lists.List.
Import ListNotations.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Data Types and Structures *)

(** HTTP Methods modeled as an inductive type with decidable equality. *)
Inductive HttpMethod : Type :=
  | Method_GET
  | Method_HEAD
  | Method_POST
  | Method_PUT
  | Method_DELETE
  | Method_OPTIONS
  | Method_OTHER (id : Z).

Definition http_method_eqb (m1 m2 : HttpMethod) : bool :=
  match m1, m2 with
  | Method_GET, Method_GET => true
  | Method_HEAD, Method_HEAD => true
  | Method_POST, Method_POST => true
  | Method_PUT, Method_PUT => true
  | Method_DELETE, Method_DELETE => true
  | Method_OPTIONS, Method_OPTIONS => true
  | Method_OTHER id1, Method_OTHER id2 => Z.eqb id1 id2
  | _, _ => false
  end.

Lemma http_method_eqb_refl : forall m : HttpMethod,
  http_method_eqb m m = true.
Proof.
  intros m. destruct m; simpl; try reflexivity.
  apply Z.eqb_refl.
Qed.

Lemma http_method_eqb_eq : forall m1 m2 : HttpMethod,
  http_method_eqb m1 m2 = true <-> m1 = m2.
Proof.
  intros m1 m2; split; intros H.
  - destruct m1, m2; simpl in H; try discriminate; try reflexivity.
    apply Z.eqb_eq in H. subst. reflexivity.
  - subst. apply http_method_eqb_refl.
Qed.

(** Canonicalized KURL / WHATWG URL Representation.
    Components are represented using integer identifiers (Z) modeling canonical
    interned byte-sequences, and option Z for nullable components (query, fragment). *)
Record KURL : Type := mkKURL {
  url_scheme   : Z;
  url_host     : Z;
  url_port     : Z;
  url_path     : Z;
  url_query    : option Z;
  url_fragment : option Z
}.

Definition option_Z_eqb (o1 o2 : option Z) : bool :=
  match o1, o2 with
  | None, None => true
  | Some z1, Some z2 => Z.eqb z1 z2
  | _, _ => false
  end.

Lemma option_Z_eqb_refl : forall o : option Z,
  option_Z_eqb o o = true.
Proof.
  intros [z | ]; simpl.
  - apply Z.eqb_refl.
  - reflexivity.
Qed.

Lemma option_Z_eqb_eq : forall o1 o2 : option Z,
  option_Z_eqb o1 o2 = true <-> o1 = o2.
Proof.
  intros [z1 | ] [z2 | ]; simpl; split; intros H; try discriminate; try reflexivity.
  - apply Z.eqb_eq in H. subst. reflexivity.
  - inversion H. subst. apply Z.eqb_refl.
Qed.

(** Decidable exact equality over KURL (models blink::operator==(const KURL&, const KURL&)). *)
Definition kurl_eqb (u1 u2 : KURL) : bool :=
  Z.eqb (url_scheme u1) (url_scheme u2) &&
  Z.eqb (url_host u1) (url_host u2) &&
  Z.eqb (url_port u1) (url_port u2) &&
  Z.eqb (url_path u1) (url_path u2) &&
  option_Z_eqb (url_query u1) (url_query u2) &&
  option_Z_eqb (url_fragment u1) (url_fragment u2).

(** URL Equivalence excluding fragment (WHATWG URL §4.5 with exclude_fragment = true). *)
Definition kurl_eq_exclude_fragment_b (u1 u2 : KURL) : bool :=
  Z.eqb (url_scheme u1) (url_scheme u2) &&
  Z.eqb (url_host u1) (url_host u2) &&
  Z.eqb (url_port u1) (url_port u2) &&
  Z.eqb (url_path u1) (url_path u2) &&
  option_Z_eqb (url_query u1) (url_query u2).

(** Fetch Request representation in Blink Cache Storage. *)
Record FetchRequest : Type := mkRequest {
  req_method : HttpMethod;
  req_url    : KURL
}.

(** CacheQueryOptions dictionary (Service Workers §5.4). *)
Record CacheQueryOptions : Type := mkQueryOptions {
  ignore_search : bool;
  ignore_method : bool;
  ignore_vary   : bool
}.

(** ** 2. URL Transformations & Projections (blink::KURL / GURL Replacements) *)

(** Strip fragment identifier: KURL::RemoveFragmentIdentifier() *)
Definition strip_fragment (u : KURL) : KURL :=
  mkKURL (url_scheme u) (url_host u) (url_port u) (url_path u) (url_query u) None.

(** Strip query string: GURL::Replacements::ClearQuery() *)
Definition strip_query (u : KURL) : KURL :=
  mkKURL (url_scheme u) (url_host u) (url_port u) (url_path u) None (url_fragment u).

(** Normalize URL according to CacheQueryOptions.
    In Blink Cache Storage, fragments are stripped on storage/query, and
    query strings are stripped if options.ignore_search is true. *)
Definition normalize_url_for_query (u : KURL) (opts : CacheQueryOptions) : KURL :=
  let u_no_frag := strip_fragment u in
  if ignore_search opts then strip_query u_no_frag else u_no_frag.

(** ** 3. Request Matching Algorithm (Service Workers §5.5.4 / §5.5.5 & cache.cc) *)

(** Checks if the request method is permitted to match by Cache::MatchImpl.
    In Service Workers §5.5.4 Step 2: If query's method is not 'GET' and
    options.ignoreMethod is false, return empty. *)
Definition method_allows_query (m : HttpMethod) (opts : CacheQueryOptions) : bool :=
  if ignore_method opts then true
  else http_method_eqb m Method_GET.

(** Core Request URL Matching Predicate.
    Models the URL and method matching phase of RequestMatches in Service Workers §5.5.5
    and blink::Cache::MatchImpl + storage::CacheStorageCache::Match. *)
Definition request_matches (query stored : FetchRequest) (opts : CacheQueryOptions) : bool :=
  method_allows_query (req_method query) opts &&
  http_method_eqb (req_method stored) Method_GET &&
  kurl_eqb (normalize_url_for_query (req_url query) opts)
           (normalize_url_for_query (req_url stored) opts).

(** Well-formedness predicate for a stored request in Cache Storage:
    Per Service Workers §5.4 (Cache.put), only GET requests are stored under normal
    cache invariants, and their URLs have fragments stripped. *)
Definition WellFormedStoredRequest (r : FetchRequest) : Prop :=
  req_method r = Method_GET /\ url_fragment (req_url r) = None.
```

---

## 4. Formal Theorems and Admitted-Free Proofs

We now prove the core mathematical properties of the formal specification:
1. `kurl_eqb_refl`, `kurl_eqb_sym`, `kurl_eqb_trans`, and `kurl_eqb_eq`: Exact URL equality forms a sound and complete equivalence relation.
2. `normalize_url_idempotent`: URL query normalization in `cache.cc` is idempotent.
3. `cache_match_url_reflexive`: URL