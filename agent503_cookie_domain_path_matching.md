# Formal Verification of Chromium Cookie Domain and Path Prefix Matching

**Author:** Formal Methods & Web Platform Security Research  
**Target Component:** Chromium Network Stack / Blink Storage Boundary (`net/cookies/cookie_monster.cc`, `net/cookies/cookie_util.cc`, `net/cookies/canonical_cookie.cc`)  
**Normative Specification:** IETF RFC 6265bis (draft-ietf-httpbis-rfc6265bis) §5.1.3, §5.1.4, §5.4  
**Formal Theory Target:** `BlinkCookieDomainPathMatchingSemantics.v`  

---

## 1. Normative IETF Specification Requirements

In the Web Platform security model, cookies do not adhere to the standard Same-Origin Policy (SOP) defined by the tuple `(scheme, host, port)`. Instead, their scope and isolation boundaries are governed by domain-matching and path-matching algorithms specified in **RFC 6265bis**. When a user agent generates an HTTP request, §5.4 ("The Cookie Header") dictates the exact inclusion criteria for stored cookies based on the request's URI.

### 1.1 Domain Matching (RFC 6265bis §5.1.3)
A string `string` (the canonicalized request host) *domain-matches* a given `domain-string` (the cookie's domain attribute) if at least one of the following conditions holds:
1. **Exact Match:** The `string` and the `domain-string` are identical (after canonicalization to lowercase punycode/ASCII).
2. **Suffix Match on Label Boundary:** All of the following conditions hold:
   * The `domain-string` is a suffix of the `string`.
   * The last character of the `string` that is not included in the `domain-string` is a `%x2E` (`.`) character.
   * The `string` is a host name (i.e., not an IPv4 or IPv6 address literal).

Furthermore, under §5.4 Step 1, a cookie is either a *host-only* cookie (`host-only-flag == true`) or a *domain* cookie (`host-only-flag == false`). 
* If `host-only-flag` is `true`, the request's host must be **identical** to the cookie's domain.
* If `host-only-flag` is `false`, the request's host must **domain-match** the cookie's domain.

### 1.2 Path Matching (RFC 6265bis §5.1.4)
A request-path `request-path` *path-matches* a given `cookie-path` if at least one of the following conditions holds:
1. **Exact Match:** The `cookie-path` and the `request-path` are identical.
2. **Prefix Match with Trailing Slash:** The `cookie-path` is a prefix of the `request-path`, and the last character of the `cookie-path` is `%x2F` (`/`).
3. **Prefix Match on Directory Boundary:** The `cookie-path` is a prefix of the `request-path`, and the first character of the `request-path` that is not included in the `cookie-path` is a `%x2F` (`/`) character.

**Security Invariant:** Naive string prefix matching on paths is a critical vulnerability. If `/foo` matched `/foobar`, a web application isolating tenants by path (e.g., `example.com/foo` vs `example.com/foobar`) would suffer from cross-path cookie injection and session fixation. The specification strictly enforces directory boundary isolation.

---

## 2. Chromium Implementation Details and Invariants

In Chromium, the storage, retrieval, and garbage collection of cookies are managed by `net::CookieMonster` (`net/cookies/cookie_monster.cc`), while the core boundary predicates reside in `net::CanonicalCookie` (`net/cookies/canonical_cookie.cc`) and `net::cookie_util` (`net/cookies/cookie_util.cc`).

### 2.1 Storage Indexing and Domain Retrieval in `CookieMonster`
`CookieMonster` stores cookies in an internal multimap indexed by the **Effective Domain plus One (eTLD+1)** (computed via `registry_controlled_domains::GetDomainAndRegistry`).

When `CookieMonster::FindCookiesForKey` is invoked during network request generation:
1. It extracts the eTLD+1 key for the request URL.
2. It iterates over all `CanonicalCookie` instances stored in that eTLD+1 bucket.
3. For each candidate cookie, it calls `CanonicalCookie::IncludeForRequestURL`, which evaluates domain and path boundaries via `CanonicalCookie::IsDomainMatch` and `CanonicalCookie::IsOnPath`.

### 2.2 Domain Matching Invariants (`net/cookies/cookie_util.cc`)
In Chromium, `CanonicalCookie::Domain()` stores the distinction between host-only cookies and domain cookies structurally within the domain string itself:
* **Host-Only Cookie:** Stored *without* a leading dot (e.g., `"example.com"`). `IsHostCookie()` returns `true` iff `!domain_.starts_with(".")`.
* **Domain Cookie:** Stored *with* a leading dot (e.g., `".example.com"`). `IsDomainCookie()` returns `true` iff `domain_.starts_with(".")`.

`cookie_util::IsDomainMatch(const std::string& domain, const std::string& host)` enforces the following C++ invariants:
```cpp
// Conceptual structure of Chromium's IsDomainMatch:
if (domain.empty() || host.empty()) return false;

// Host-only cookie: requires exact string equality.
if (domain[0] != '.') {
  return domain == host;
}

// Domain cookie: `domain` starts with '.'
// 1. Check if `host` equals `domain` without the leading '.' (e.g., ".example.com" matches "example.com")
if (host.length() + 1 == domain.length()) {
  return domain.compare(1, std::string::npos, host) == 0;
}

// 2. Check if `domain` (including leading '.') is a strict suffix of `host`.
// Because `domain` begins with '.', a suffix match inherently guarantees that the character
// in `host` at the boundary is '.', satisfying RFC 6265bis §5.1.3 Condition 2.
if (host.length() >= domain.length()) {
  return host.compare(host.length() - domain.length(), domain.length(), domain) == 0;
}

return false;
```
*(Note: Chromium prevents IP literals from becoming domain cookies during cookie construction in `cookie_util::GetCookieDomainWithString`, ensuring IP hosts only ever take the host-only exact match branch).*

### 2.3 Path Matching Invariants (`net/cookies/cookie_util.cc`)
Path matching is implemented in `cookie_util::IsOnPath(const std::string& cookie_path, const std::string& url_path)`:
```cpp
// Conceptual structure of Chromium's IsOnPath:
if (cookie_path.empty()) return false;

// Check if cookie_path is a prefix of url_path
if (!url_path.starts_with(cookie_path)) {
  return false;
}

// 1. Exact match: lengths are equal
if (url_path.length() == cookie_path.length()) {
  return true;
}

// 2. Prefix match with trailing slash in cookie_path
if (cookie_path.back() == '/') {
  return true;
}

// 3. Prefix match on directory boundary: first unmatched char in url_path is '/'
return url_path[cookie_path.length()] == '/';
```
This implementation achieves $O(|cookie\_path|)$ time complexity and zero heap allocations while directly mirroring the three disjunctive branches of RFC 6265bis §5.1.4.

---

## 3. Formal Specification & Verification in Rocq (Coq)

Below is the complete, self-contained formalization of `BlinkCookieDomainPathMatchingSemantics.v`. We represent characters as `Z` (integers) using `ZArith` to leverage `lia` for fast arithmetic and character inequality reasoning.

```coq
(** * BlinkCookieDomainPathMatchingSemantics.v
    Formal Verification of Chromium Cookie Domain and Path Prefix Matching
    Source: net/cookies/cookie_monster.cc, net/cookies/cookie_util.cc
    Specification: RFC 6265bis §5.1.3, §5.1.4, §5.4 *)

Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Foundational Types and Character Constants *)

(** We represent ASCII characters as integer code points in Z. *)
Definition char := Z.
Definition string_t := list char.

(** Key ASCII delimiters *)
Definition CHAR_SLASH : char := 47. (* '/' = 0x2F *)
Definition CHAR_DOT   : char := 46. (* '.' = 0x2E *)
Definition CHAR_F     : char := 102. (* 'f' *)
Definition CHAR_O     : char := 111. (* 'o' *)
Definition CHAR_B     : char := 98.  (* 'b' *)
Definition CHAR_A     : char := 97.  (* 'a' *)
Definition CHAR_R     : char := 114. (* 'r' *)
Definition CHAR_E     : char := 101. (* 'e' *)
Definition CHAR_X     : char := 120. (* 'x' *)

(** ** 2. String List Operations and Decidable Equality *)

Fixpoint list_eqb (l1 l2 : string_t) : bool :=
  match l1, l2 with
  | [], [] => true
  | x :: xs, y :: ys => Z.eqb x y && list_eqb xs ys
  | _, _ => false
  end.

Lemma list_eqb_spec : forall l1 l2,
  list_eqb l1 l2 = true <-> l1 = l2.
Proof.
  induction l1 as [|x xs IH]; intros [|y ys]; simpl; split; intros H; try discriminate; auto.
  - apply andb_true_iff in H. destruct H as [H1 H2].
    apply Z.eqb_eq in H1. apply IH in H2. subst. reflexivity.
  - injection H as H1 H2. subst.
    apply andb_true_iff. split.
    + apply Z.eqb_refl.
    + apply IH. reflexivity.
Qed.

Lemma list_eqb_refl : forall l, list_eqb l l = true.
Proof.
  intros l. apply list_eqb_spec. reflexivity.
Qed.

Lemma list_eqb_neq : forall l1 l2,
  list_eqb l1 l2 = false <-> l1 <> l2.
Proof.
  intros l1 l2. split; intros H.
  - intros Heq. apply list_eqb_spec in Heq. congruence.
  - destruct (list_eqb l1 l2) eqn:E; auto.
    apply list_eqb_spec in E. contradiction.
Qed.

(** Executable prefix check: [is_prefix p s] returns true iff [p] is a prefix of [s]. *)
Fixpoint is_prefix (p s : string_t) : bool :=
  match p, s with
  | [], _ => true
  | px :: pxs, sx :: sxs => Z.eqb px sx && is_prefix pxs sxs
  | _ :: _, [] => false
  end.

(** Prefix witness extraction: if [p] is a prefix of [s], returns [Some rem] where [s = p ++ rem]. *)
Fixpoint strip_prefix (p s : string_t) : option string_t :=
  match p, s with
  | [], _ => Some s
  | px :: pxs, sx :: sxs =>
      if Z.eqb px sx then strip_prefix pxs sxs else None
  | _ :: _, [] => None
  end.

Lemma strip_prefix_sound : forall p s rem,
  strip_prefix p s = Some rem -> s = p ++ rem.
Proof.
  induction p as [|px pxs IH]; intros [|sx sxs] rem H; simpl in *; try discriminate.
  - injection H as H; subst; reflexivity.
  - injection H as H; subst; reflexivity.
  - destruct (Z.eqb px sx) eqn:Heq; try discriminate.
    apply Z.eqb_eq in Heq; subst.
    f_equal. apply IH. exact H.
Qed.

Lemma strip_prefix_complete : forall p rem,
  strip_prefix p (p ++ rem) = Some rem.
Proof.
  induction p as [|px pxs IH]; intros rem; simpl.
  - reflexivity.
  - rewrite Z.eqb_refl. apply IH.
Qed.

Lemma strip_prefix_none : forall p s,
  strip_prefix p s = None <-> (forall rem, s <> p ++ rem).
Proof.
  induction p as [|px pxs IH]; intros [|sx sxs]; simpl; split; intros H.
  - discriminate.
  - exfalso. apply (H []). reflexivity.
  - discriminate.
  - exfalso. apply (H (sx :: sxs)). reflexivity.
  - intros rem Heq. discriminate.
  - reflexivity.
  - destruct (Z.eqb px sx) eqn:Heq.
    + apply Z.eqb_eq in Heq; subst.
      intros rem Hcon. injection Hcon as Hcon.
      eapply IH; eauto.
    + apply Z.eqb_neq in Heq.
      intros rem Hcon. injection Hcon as H1 H2. contradiction.
  - destruct (Z.eqb px sx) eqn:Heq; auto.
    apply Z.eqb_eq in Heq; subst.
    apply IH. intros rem Hcon. apply (H rem). f_equal. exact Hcon.
Qed.

(** Optional last element of a list *)
Fixpoint last_opt (l : string_t) : option char :=
  match l with
  | [] => None
  | [x] => Some x
  | _ :: xs => last_opt xs
  end.

Lemma last_opt_app_singleton : forall l c,
  last_opt (l ++ [c]) = Some c.
Proof.
  induction l as [|x xs IH]; intros c; simpl.
  - reflexivity.
  - destruct (xs ++ [c]) eqn:E.
    + destruct xs; simpl in E; discriminate.
    + rewrite <- E. apply IH.
Qed.

(** Suffix relation via list reversal *)
Definition is_suffix (suf s : string_t) : bool :=
  is_prefix (rev suf) (rev s).

Definition strip_suffix (suf s : string_t) : option string_t