# Formal Verification Research Report: Reporting API URL Credential Sanitization

**Agent ID:** 671  
**Specialization:** Web Platform File System, Streams, Shape Detection, and Platform Totality in Chromium Blink  
**Target Artifact:** `BlinkReportingAPICredentialFilterSemantics.v`  
**Chromium Source:** `third_party/blink/renderer/core/frame/reporting_context.cc`  
**Normative Specification:** W3C Reporting API § 3 (Strip URL for use in reports)

---

## 1. Normative W3C / WHATWG Specification Requirements

The W3C Reporting API specification defines a generic reporting framework for out-of-band browser notifications (e.g., Content Security Policy violations, Deprecation reports, Intervention reports, and Crash reports). Because reports are serialized and potentially transmitted to third-party collector endpoints or inspected via `ReportingObserver` callbacks, embedded URL credentials and fragments pose a severe cross-origin data leak hazard.

### 1.1 W3C Reporting API § 3: "Strip URL for use in reports"
The normative algorithm **strip URL for use in reports** takes a [URL record](https://url.spec.whatwg.org/#concept-url) $url$ and executes the following deterministic steps:

1. If $url$'s `scheme` is not an [HTTP(S) scheme](https://fetch.spec.whatwg.org/#ok-status) (or more generally in Blink's general URL sanitizer for reporting contexts, if the URL is invalid/non-hierarchical), return the empty string or scheme-specific stripped representation.
2. Set $url$'s `fragment` to `null`.
3. Set $url$'s `username` to the empty string `""`.
4. Set $url$'s `password` to `null` (represented in Blink `KURL` as empty string `""`).
5. Return the [serialization](https://url.spec.whatwg.org/#concept-url-serializer) of $url$.

### 1.2 Security & Privacy Invariant
For any URL $U$ processed by the Reporting Context pipeline, the resulting reported URL $U'$ must satisfy:
$$\text{username}(U') = \emptyset \land \text{password}(U') = \emptyset \land \text{fragment}(U') = \bot$$
while strictly preserving the authority host, port, path, and query components:
$$\pi_{\{\text{scheme, host, port, path, query}\}}(U') = \pi_{\{\text{scheme, host, port, path, query}\}}(U)$$

---

## 2. Blink Implementation Details and Invariants

In Chromium Blink, `ReportingContext` (`third_party/blink/renderer/core/frame/reporting_context.cc`) acts as the central broker between ExecutionContext-level report generators and both the internal `ReportingObserver` queues and the Mojo `ReportingServiceProxy` (which forwards reports to the browser/network process).

### 2.1 Source Analysis: `reporting_context.cc`
When a report is queued via `ReportingContext::QueueReport(Report* report, const Vector<String>& endpoints)`, or when constructing the report metadata from the `ExecutionContext` URL (e.g., `Document::Url()` or `WorkerGlobalScope::Url()`), Blink sanitizes the URL using `KURL` mutation primitives:

```cpp
// Conceptual / Direct KURL sanitization pattern in Blink Reporting pipeline:
KURL SanitizeURLForReport(const KURL& url) {
  if (!url.IsValid())
    return KURL();
  KURL copy = url;
  copy.SetUser(String());
  copy.SetPass(String());
  copy.RemoveFragmentIdentifier();
  return copy;
}
```

### 2.2 Blink `KURL` State Transition Invariants
In `third_party/blink/renderer/platform/weborigin/kurl.cc`, `KURL` wraps `url::Parsed` and an underlying string buffer:
1. **`KURL::SetUser(const String&)`**: Invokes `url::Replacements<char>::SetUsername` or `ClearUsername()` when passed an empty string. It recalculates character offsets in `url::Parsed` without mutating `scheme`, `host`, `port`, `path`, or `query`.
2. **`KURL::SetPass(const String&)`**: Invokes `ClearPassword()` when passed an empty string.
3. **`KURL::RemoveFragmentIdentifier()`**: Invokes `url::Replacements<char>::ClearRef()`, stripping the `#` delimiter and subsequent octets.
4. **Totality Invariant**: Unlike network-layer URL parsing which can fail on malformed input, `SanitizeURLForReport` is a total function over the `KURL` domain. Invalid URLs map to empty `KURL` instances (which naturally lack credentials and fragments), and valid URLs undergo orthogonal component projection.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization in `BlinkReportingAPICredentialFilterSemantics.v`. We model URLs with explicit component records, string buffers as `list Z` (representing Unicode code points / UTF-8 octets), and prove algebraic properties of the sanitization operator.

## 4. Concrete Theorems and Complete Proofs (`BlinkReportingAPICredentialFilterSemantics.v`)

```coq
(** * BlinkReportingAPICredentialFilterSemantics.v
    Formal Verification of Chromium Blink Reporting API URL Credential Sanitization
    Source: third_party/blink/renderer/core/frame/reporting_context.cc
    Specification: W3C Reporting API § 3 (Strip URL for use in reports)
    Agent 671 - Web Platform Totality & Security Semantics
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

Section ReportingAPICredentialFilter.

  (** ** 1. Foundational Types and Web Platform Primitives *)

  (** Code points / Byte representation for Blink String *)
  Definition BlinkString := list Z.

  Definition empty_string : BlinkString := [].

  (** Structural equality decision procedure for BlinkString *)
  Lemma blink_string_eq_dec : forall (s1 s2 : BlinkString), {s1 = s2} + {s1 <> s2}.
  Proof.
    apply list_eq_dec.
    exact Z.eq_dec.
  Defined.

  Definition blink_string_is_empty (s : BlinkString) : bool :=
    match s with
    | [] => true
    | _ :: _ => false
    end.

  (** Representation of Blink's KURL (platform/weborigin/kurl.h).
      Tracks validity, scheme, userinfo (username, password), host,
      optional port, path, optional query, and optional fragment. *)
  Record KURL : Type := mkKURL {
    kurl_is_valid : bool;
    kurl_scheme   : BlinkString;
    kurl_user     : BlinkString;
    kurl_pass     : BlinkString;
    kurl_host     : BlinkString;
    kurl_port     : option Z;
    kurl_path     : BlinkString;
    kurl_query    : option BlinkString;
    kurl_fragment : option BlinkString
  }.

  (** Canonical empty/invalid KURL returned by KURL() default constructor *)
  Definition empty_kurl : KURL := {|
    kurl_is_valid := false;
    kurl_scheme   := [];
    kurl_user     := [];
    kurl_pass     := [];
    kurl_host     := [];
    kurl_port     := None;
    kurl_path     := [];
    kurl_query    := None;
    kurl_fragment := None
  |}.

  (** ** 2. KURL Mutation Primitives (kurl.cc) *)

  (** KURL::SetUser(String()) *)
  Definition kurl_clear_user (u : KURL) : KURL :=
    if u.(kurl_is_valid) then
      {| kurl_is_valid := u.(kurl_is_valid);
         kurl_scheme   := u.(kurl_scheme);
         kurl_user     := [];
         kurl_pass     := u.(kurl_pass);
         kurl_host     := u.(kurl_host);
         kurl_port     := u.(kurl_port);
         kurl_path     := u.(kurl_path);
         kurl_query    := u.(kurl_query);
         kurl_fragment := u.(kurl_fragment) |}
    else empty_kurl.

  (** KURL::SetPass(String()) *)
  Definition kurl_clear_pass (u : KURL) : KURL :=
    if u.(kurl_is_valid) then
      {| kurl_is_valid := u.(kurl_is_valid);
         kurl_scheme   := u.(kurl_scheme);
         kurl_user     := u.(kurl_user);
         kurl_pass     := [];
         kurl_host     := u.(kurl_host);
         kurl_port     := u.(kurl_port);
         kurl_path     := u.(kurl_path);
         kurl_query    := u.(kurl_query);
         kurl_fragment := u.(kurl_fragment) |}
    else empty_kurl.

  (** KURL::RemoveFragmentIdentifier() *)
  Definition kurl_remove_fragment (u : KURL) : KURL :=
    if u.(kurl_is_valid) then
      {| kurl_is_valid := u.(kurl_is_valid);
         kurl_scheme   := u.(kurl_scheme);
         kurl_user     := u.(kurl_user);
         kurl_pass     := u.(kurl_pass);
         kurl_host     := u.(kurl_host);
         kurl_port     := u.(kurl_port);
         kurl_path     := u.(kurl_path);
         kurl_query    := u.(kurl_query);
         kurl_fragment := None |}
    else empty_kurl.

  (** ** 3. Reporting Context Sanitization Operator *)

  (** Models the URL sanitization logic in reporting_context.cc *)
  Definition sanitize_url (u : KURL) : KURL :=
    if u.(kurl_is_valid) then
      kurl_remove_fragment (kurl_clear_pass (kurl_clear_user u))
    else
      empty_kurl.

  (** ** 4. Security and Structural Predicates *)

  (** A KURL is free of userinfo credentials if both user and pass are empty *)
  Definition has_no_credentials (u : KURL) : Prop :=
    u.(kurl_user) = [] /\ u.(kurl_pass) = [].

  (** A KURL is free of a fragment identifier *)
  Definition has_no_fragment (u : KURL) : Prop :=
    u.(kurl_fragment) = None.

  (** Combined W3C Reporting API § 3 compliance predicate *)
  Definition is_sanitized_for_report (u : KURL) : Prop :=
    has_no_credentials u /\ has_no_fragment u.

  (** Boolean decision procedure for sanitization check *)
  Definition is_sanitized_for_report_b (u : KURL) : bool :=
    blink_string_is_empty u.(kurl_user) &&
    blink_string_is_empty u.(kurl_pass) &&
    match u.(kurl_fragment) with
    | None => true
    | Some _ => false
    end.

  (** Non-sensitive origin and resource locator components *)
  Definition preserves_safe_components (u1 u2 : KURL) : Prop :=
    u1.(kurl_is_valid) = true ->
    u2.(kurl_is_valid) = true /\
    u2.(kurl_scheme)   = u1.(kurl_scheme) /\
    u2.(kurl_host)     = u1.(kurl_host) /\
    u2.(kurl_port)     = u1.(kurl_port) /\
    u2.(kurl_path)     = u1.(kurl_path) /\
    u2.(kurl_query)    = u1.(kurl_query).

  (** Information-theoretic length measure of sensitive components *)
  Definition sensitive_payload_length (u : KURL) : Z :=
    Z.of_nat (length u.(kurl_user)) +
    Z.of_nat (length u.(kurl_pass)) +
    match u.(kurl_fragment) with
    | None => 0
    | Some f => Z.of_nat (length f)
    end.

  (** ** 5. Formal Verification Theorems and Proofs *)

  (** Theorem 1: Reflection equivalence between boolean check and Prop spec *)
  Theorem is_sanitized_reflect : forall (u : KURL),
    is_sanitized_for_report_b u = true <-> is_sanitized_for_report u.
  Proof.
    intros u.
    unfold is_sanitized_for_report_b, is_sanitized_for_report,
           has_no_credentials, has_no_fragment.
    split; intros H.
    - apply andb_prop in H. destruct H as [H1 Hfrag].
      apply andb_prop in H1. destruct H1 as [Huser Hpass].
      destruct (kurl_user u) eqn:Eu; [| discriminate Huser].
      destruct (kurl_pass u) eqn:Ep; [| discriminate Hpass].
      destruct (kurl_fragment u) eqn:Ef; [discriminate Hfrag |].
      repeat split; reflexivity.
    - destruct H as [[Huser Hpass] Hfrag].
      rewrite Huser, Hpass, Hfrag.
      simpl. reflexivity.
  Qed.

  (** Theorem 2: Core Soundness — sanitize_url always strips userinfo and fragment *)
  Theorem sanitize_url_strips_credentials_and_fragment : forall (u : KURL),
    is_sanitized_for_report (sanitize_url u).
  Proof.
    intros u.
    unfold sanitize_url, is_sanitized_for_report, has_no_credentials, has_no_fragment.
    destruct (kurl_is_valid u) eqn:Hval.
    - unfold kurl_clear_user, kurl_clear_pass, kurl_remove_fragment.
      rewrite Hval. simpl.
      rewrite Hval. simpl.
      repeat split; reflexivity.
    - unfold empty_kurl. simpl.
      repeat split; reflexivity.
  Qed.

  (** Theorem 3: Non-Interference / Zero Sensitive Payload Leakage *)
  Theorem sanitize_url_zero_sensitive_length : forall (u : KURL),
    sensitive_payload_length (sanitize_url u) = 0.
  Proof.
    intros u.
    pose proof (sanitize_url_strips_credentials_and_fragment u) as Hsan.
    destruct H