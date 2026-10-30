# Formal Verification Report: Service Worker Scope Prefix Matching in Chromium Blink

**Formal Theory Target**: `BlinkServiceWorkerScopePrefixMatchSemantics.v`  
**Chromium Source Component**: `third_party/blink/renderer/modules/service_worker/service_worker_container.cc` (interacting with `content/common/service_worker/service_worker_utils.cc` and `blink::WebServiceWorkerProvider`)  
**W3C Specification**: Service Workers Nightly / W3C Recommendation §3.1 (Service Worker Registration) & §4.2.5 (Match Service Worker Registration)  
**Mathematical Property**: A client or network request URL is matched by a Service Worker registration scope if and only if the origins are identical and the serialized request path-query string is a prefix of (starts with) the serialized scope path-query string, selecting the longest matching prefix among active registrations.

---

## 1. Exact Normative W3C/WHATWG/IETF Specification Requirements

Service Worker scope matching governs whether an incoming navigation or subresource fetch (`FetchEvent`), or a document client (`ServiceWorkerContainer`), falls under the authority of a given `ServiceWorkerRegistration`. The normative requirements span the W3C Service Workers Specification and the WHATWG URL Standard.

### 1.1 W3C Service Workers §3.1 & §4.2.5 (Match Service Worker Registration)
To **Match Service Worker Registration** given a `clientURL` (a parsed WHATWG URL record):

1. Let `matchingScope` be null.
2. Let ` clientURLString` be the result of running the URL serializer (WHATWG URL §4.5) on `clientURL` with the *exclude fragment flag* set.
3. Let `scopeList` be an empty list of URLs, populated by the `scopeURL` of all stored registrations where `registration's scopeURL's origin` is **same origin** (HTML §7.5) with `clientURL's origin`.
4. For each `scopeURL` in `scopeList`:
   * Let `scopeString` be the result of running the URL serializer on `scopeURL` with the *exclude fragment flag* set.
   * If `clientURLString` **starts with** `scopeString` (Infra Standard §4.6 code unit prefix match), append `scopeString` to a list of matching scopes.
5. Set `matchingScope` to the longest string in the matching scopes list (if any).
6. Return the registration whose serialized `scopeURL` equals `matchingScope`, or null if none exists.

### 1.2 Registration Validation Invariants (Register Algorithm §4.2.3)
Before a scope is added to the registration map via `ServiceWorkerContainer::registerServiceWorker`:
1. **Scheme Restriction**: Both `scriptURL` and `scopeURL` schemes must be an HTTP(S) scheme (`http` or `https`).
2. **Origin Restriction**: `scriptURL`'s origin and `scopeURL`'s origin must be *same origin* with the registering client's origin.
3. **Path Escape Prevention**: The ASCII-case-insensitive percent-encoded path of neither `scriptURL` nor `scopeURL` may contain `%2f` (`/`) or `%5c` (`\`).
4. **Max Scope Prefix**: Unless overridden by the `Service-Worker-Allowed` HTTP response header, `scopeURL`'s path must start with the directory path of `scriptURL`.

---

## 2. Blink Implementation Details and Invariants

In Chromium, the renderer-side entry point for registration and client matching resides in `third_party/blink/renderer/modules/service_worker/service_worker_container.cc`.

### 2.1 Renderer Validation in `service_worker_container.cc`
When `ServiceWorkerContainer::registerServiceWorkerImpl` is invoked:
1. **URL Resolution**: The candidate `script_url` and `scope_url` are resolved against the `ExecutionContext`'s base URL via `ExecutionContext::CompleteURL()`. If `options->scope()` is omitted, the default scope is computed by resolving `"./"` against `script_url`, stripping the filename and query while preserving the directory path (ending in `/`).
2. **Fragment Stripping**: Before IPC transmission across `mojom::blink::ServiceWorkerContainerHost`, Blink invokes `KURL::RemoveFragmentIdentifier()` on both `script_url` and `scope_url`. This establishes the WHATWG *exclude fragment flag* invariant directly on the `blink::KURL` representation.
3. **Origin & Security Checks**:
   * `ExecutionContext`'s `SecurityOrigin::CanAccess(scope_origin)` and `SecurityOrigin::IsSameOriginWith()` verify exact scheme, host, and port equality.
   * `ServiceWorkerUseCounter` and `WebServiceWorkerProvider::ValidateScopeAndScriptURL` enforce that neither URL contains `%2f` or `%5c` and that schemes belong to `SchemeRegistry::ShouldTreatURLSchemeAsAllowingServiceWorkers`.

### 2.2 Prefix Matching Engine Invariants
When evaluating scope matches (executed synchronously in the browser/storage registry and mirrored in renderer controller selection via `ServiceWorkerScopeMatches` in `third_party/blink/common/service_worker/service_worker_scope_match.cc` invoked by container host plumbing):
* **Canonical Serialization**: `KURL::GetString()` (or `GURL::spec()`) produces a canonical ASCII string where the scheme and host are normalized, default ports are omitted, and the path always starts with `/`.
* **Decomposition**: Because the origin (`scheme://host:port`) is verified to be identical prior to or simultaneously with prefix evaluation, string prefix matching on `spec()` without fragments is mathematically isomorphic to verifying origin equality followed by string prefix matching on the concatenated `path + "?" + query` component.
* **Longest Prefix Tie-Breaking**: Because no two registrations in the same storage key can share the exact same `scopeURL`, the maximum length among matching prefixes is strictly unique.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkServiceWorkerScopePrefixMatchSemantics.v`. We model origins, normalized URLs, Blink's fragment-stripping normalization, prefix predicates, and the longest-prefix registration matcher.

```coq
(** * BlinkServiceWorkerScopePrefixMatchSemantics.v
    Formal verification of Service Worker Scope Prefix Matching (W3C Service Workers §3.1)
    corresponding to third_party/blink/renderer/modules/service_worker/service_worker_container.cc
    and blink::ServiceWorkerScopeMatches. *)

From Coq Require Import Bool.Bool.
From Coq Require Import Lists.List.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Fundamental Domains: Characters, Strings, and Origins *)

(** We represent ASCII code units / path tokens as integers (Z) to leverage ZArith/Lia. *)
Definition Char := Z.
Definition PathString := list Char.

(** Origin tuple: (scheme_id, host_id, port).
    HTTP = 1, HTTPS = 2, Other = 0. *)
Record Origin := mkOrigin {
  orig_scheme : Z;
  orig_host   : Z;
  orig_port   : Z
}.

Definition origin_eqb (o1 o2 : Origin) : bool :=
  (Z.eqb (orig_scheme o1) (orig_scheme o2)) &&
  (Z.eqb (orig_host o1) (orig_host o2)) &&
  (Z.eqb (orig_port o1) (orig_port o2)).

Lemma origin_eqb_eq : forall o1 o2,
  origin_eqb o1 o2 = true <-> o1 = o2.
Proof.
  intros [s1 h1 p1] [s2 h2 p2].
  unfold origin_eqb; simpl.
  rewrite !andb_true_iff, !Z.eqb_eq.
  split; intros H.
  - destruct H as [[Hs Hh] Hp]. subst. reflexivity.
  - inversion H; subst. auto.
Qed.

Lemma origin_eqb_refl : forall o, origin_eqb o o = true.
Proof.
  intros o. apply origin_eqb_eq. reflexivity.
Qed.

(** HTTP(S) Scheme check (Service Workers §4.2.3 step 4). *)
Definition is_http_or_https (o : Origin) : bool :=
  (Z.eqb (orig_scheme o) 1) || (Z.eqb (orig_scheme o) 2).

(** ** 2. URL Representation and Blink KURL Normalization *)

(** A Blink KURL in service_worker_container.cc consists of an Origin,
    a serialized path_and_query sequence, and an optional fragment. *)
Record BlinkKURL := mkKURL {
  kurl_origin     : Origin;
  kurl_path_query : PathString;
  kurl_has_frag   : bool;
  kurl_fragment   : PathString
}.

(** Corresponds to KURL::RemoveFragmentIdentifier() in service_worker_container.cc *)
Definition remove_fragment (u : BlinkKURL) : BlinkKURL :=
  mkKURL (kurl_origin u) (kurl_path_query u) false [].

(** ** 3. Prefix Matching Semantics (Infra Standard §4.6 & SW §3.1) *)

Fixpoint list_prefix_eqb (p s : PathString) : bool :=
  match p, s with
  | [], _ => true
  | x :: xs, y :: ys => if Z.eqb x y then list_prefix_eqb xs ys else false
  | _ :: _, [] => false
  end.

(** Mathematical specification of prefix: s starts with p iff exists rest, s = p ++ rest. *)
Definition is_prefix (p s : PathString) : Prop :=
  exists rest : PathString, s = p ++ rest.

(** Core Blink Scope Match implementation:
    Checks HTTP/HTTPS scheme, exact origin match, and path_query code-unit prefix. *)
Definition blink_scope_matches (scope_url request_url : BlinkKURL) : bool :=
  let s_clean := remove_fragment scope_url in
  let r_clean := remove_fragment request_url in
  is_http_or_https (kurl_origin s_clean) &&
  origin_eqb (kurl_origin s_clean) (kurl_origin r_clean) &&
  list_prefix_eqb (kurl_path_query s_clean) (kurl_path_query r_clean).

(** W3C Specification Predicate for Scope Match (§3.1 / §4.2.5) *)
Definition spec_scope_matches (scope_url request_url : BlinkKURL) : Prop :=
  is_http_or_https (kurl_origin scope_url) = true /\
  kurl_origin scope_url = kurl_origin request_url /\
  is_prefix (kurl_path_query scope_url) (kurl_path_query request_url).

(** ** 4. Service Worker Registration Map & Longest Prefix Selection *)

Record SWRegistration := mkReg {
  reg_id    : Z;
  reg_scope : BlinkKURL
}.

Definition path_len (p : PathString) : Z :=
  Z.of_nat (List.length p).

(** Selects between two matching registrations: prefers strictly longer scope path,
    preserving accumulator on ties (registrations in storage have unique scopes). *)
Definition select_longer_reg (best candidate : SWRegistration) : SWRegistration :=
  if Z.ltb (path_len (kurl_path_query (reg_scope best)))
           (path_len (kurl_path_query (reg_scope candidate)))
  then candidate
  else best.

(** Match Service Worker Registration algorithm (§4.2.5) *)
Fixpoint match_registration (regs : list SWRegistration) (req : BlinkKURL)
  : option SWRegistration :=
  match regs with
  | [] => None
  | r :: rs =>
      let rest_match := match_registration rs req in
      if blink_scope_matches (reg_scope r) req then
        match rest_match with
        | None => Some r
        | Some best_rest => Some (select_longer_reg r best_rest)
        end
      else
        rest_match
  end.
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

We now prove the soundness, completeness, structural properties (reflexivity, transitivity, anti-symmetry), fragment invariance, and optimality (longest-prefix guarantee) of the Blink implementation with zero admitted lemmas.

```coq
(** ** 5. Formal Verification Proofs *)

(** *** Theorem 1: Equivalence of executable prefix check and existential concatenation *)
Theorem list_prefix_eqb_spec : forall (p s : PathString),
  list_prefix_eqb p s = true <-> is_prefix p s.
Proof.
  induction p as [|x xs IH]; intros s.
  - simpl. split; intros _.
    + exists s. reflexivity.
    + reflexivity.
  - destruct s as [|y ys]; simpl.
    + split; intros H.
      * discriminate H.
      * destruct H as [rest H]. discriminate H.
    + destruct (Z.eqb x y) eqn:Heq.
      * apply Z.eqb_eq in Heq; subst y.
        rewrite IH. split; intros [rest Hrest].
        -- exists rest. simpl. f_equal. exact Hrest.
        -- inversion Hrest; subst. exists rest. reflexivity.
      * apply Z.eqb_neq in Heq. split; intros H.
        -- discriminate H.
        -- destruct H as [rest Hrest]. inversion Hrest; subst.
           contradiction.
Qed.

(** *** Theorem 2: Prefix Length Monotonicity *)
Theorem prefix_length_le : forall (p s : PathString),
  list_prefix_eqb p s = true ->
  path_len p <= path_len s.
Proof.
  intros p s H.
  apply list_prefix_eqb_spec in H.
  destruct H as [rest Hrest].
  subst s. unfold path_len.
  rewrite app_length.
  lia.
Qed.

(** *** Theorem 3: Prefix Partial Order Properties (Reflexivity, Transitivity, Antisymmetry) *)
Lemma list_prefix_refl : forall (p : PathString),
  list_prefix_eqb p p = true.
Proof.
  intros p. apply list_prefix_eqb_spec.
  exists []. rewrite app_nil_r. reflexivity.
Qed.

Lemma list_prefix_trans : forall (p1 p2 p3 : PathString),
  list_prefix_eqb p1 p2 = true ->
  list_prefix_eqb p2 p3 = true ->
  list_prefix_eqb p1 p3 = true.
Proof.
  intros p1 p2 p3 H12 H23.
  apply list_prefix_eqb_spec in H12.
  apply list_prefix_eqb_spec in H23.
  apply list_prefix_eqb_spec.
  destruct H12