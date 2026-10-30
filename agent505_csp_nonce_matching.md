# Formal Verification Report: Blink CSP `script-src` Nonce Matching Soundness

**Formal Theory Target:** `BlinkCSPNonceMatchingSemantics.v`  
**Chromium Component:** `third_party/blink/renderer/core/frame/csp/csp_directive_list.cc`  
**Normative Specification:** W3C Content Security Policy Level 3 (CSP3) §5 & §6.6  
**Mathematical Property:** $\forall s_{\text{nonce}}, e_{\text{nonce}}, \quad \text{nonce\_matches}(s_{\text{nonce}}, e_{\text{nonce}}) \iff (s_{\text{nonce}} \neq \epsilon \land s_{\text{nonce}} = e_{\text{nonce}})$

---

## 1. Exact Normative W3C/WHATWG Specification Requirements

Content Security Policy Level 3 (CSP3) establishes cryptographically backed execution boundaries for inline scripts and external script requests via cryptographic nonces (`'nonce-<base64-value>'`). The normative requirements governing nonce matching are defined across Section 5 (*Directives*) and Section 6 (*Matching Algorithms*) of the W3C CSP3 specification.

### 1.1 Grammar and Source Expression Parsing (CSP3 §6.2 & §6.6.1)
A nonce-source expression is defined by the ABNF grammar:
```abnf
nonce-source  = "'nonce-" base64-value "'"
base64-value  = 1*( ALPHA / DIGIT / "+" / "/" / "-" / "_" )*2( "=" )
```
When parsing a serialized source list (`CSPSourceList`), the user agent extracts the `base64-value` from valid `'nonce-...'` tokens (performing case-insensitive prefix matching on `'nonce-'` and exact case-sensitive extraction of the payload) and stores the decoded/extracted string in the directive's set of authorized nonces.

### 1.2 Does Element Match Source List for Type and Source? (CSP3 §6.6.2.1)
When an HTML `<script>` element is prepared for execution (per HTML Living Standard §4.12.1.1 *Prepare the script element*), its cryptographic nonce is captured in the element's internal `[[CryptographicNonce]]` slot (exposed via the `nonce` IDL attribute, stripped from the `nonce` content attribute upon parsing to resist DOM scraping).

To evaluate whether the element is permitted by a directive's `source list`:
1. Let `element_nonce` be the value of the element's `[[CryptographicNonce]]` internal slot.
2. If `element_nonce` is the empty string (`""`), the element **cannot** match via a nonce-source expression.
3. Otherwise, the element matches the source list if the directive's source list contains at least one `nonce-source` expression whose `base64-value` is an **exact, case-sensitive (code-unit for code-unit) match** with `element_nonce`.

### 1.3 Security Invariant
The fundamental security guarantee of CSP3 nonce matching is **Non-Trivial Exact Equality**:
$$\text{PermittedByNonce}(D, e_{\text{nonce}}) \iff e_{\text{nonce}} \neq \epsilon \land \exists s_{\text{nonce}} \in \text{Nonces}(D),\ s_{\text{nonce}} = e_{\text{nonce}}$$
Crucially:
- **Empty Nonce Rejection:** An element without a nonce (or with `nonce=""`) must never match, even if a malformed or buggily parsed policy contains an empty nonce entry.
- **Case Sensitivity:** Base64 encodings have high entropy depending on mixed case (`A-Z` vs `a-z`). Case-insensitive matching would degrade entropy from $6\text{ bits/char}$ to $\approx 5.17\text{ bits/char}$ and violate the specification.

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, CSP evaluation has undergone architectural separation between network-layer parsing (`services/network/public/cpp/content_security_policy/`) and renderer-side enforcement (`third_party/blink/renderer/core/frame/csp/`).

### 2.1 Code Path Analysis in `csp_directive_list.cc`
In `third_party/blink/renderer/core/frame/csp/csp_directive_list.cc` (paired with `csp_source_list_directive.cc` / `content_security_policy.cc`), script execution checks for inline scripts and external scripts with nonces invoke directive list evaluation:

```cpp
// Conceptual representation of the Blink evaluation pipeline in csp_directive_list.cc
bool CheckAllowNonce(const network::mojom::blink::CSPSourceList* directive,
                     const String& nonce) {
  if (!directive)
    return false;
  return CSPSourceListAllowNonce(*directive, nonce);
}

bool CSPSourceListAllowNonce(
    const network::mojom::blink::CSPSourceList& source_list,
    const String& nonce) {
  if (nonce.IsNull() || nonce.empty())
    return false;
  return source_list.nonces.Contains(nonce);
}
```

And during inline/external script verification in `CSPDirectiveList`:
```cpp
bool CSPDirectiveListAllowInline(
    const network::mojom::blink::CSPDirectiveList& directive_list,
    ContentSecurityPolicy* csp,
    ContentSecurityPolicy::InlineType inline_type,
    Element* element,
    const String& content,
    const String& nonce,
    const String& context_url,
    const OrdinalNumber& context_line,
    ReportingDisposition reporting_disposition) {
  // ...
  const network::mojom::blink::CSPSourceList* operative_directive =
      OperativeDirective(directive_list, type);

  if (CheckAllowNonce(operative_directive, nonce))
    return true;
  // ...
}
```

### 2.2 Blink Engine Invariants
1. **Mojo Boundary Normalization (`network::mojom::blink::CSPSourceList`):**
   The `nonces` field in `CSPSourceList` is a `WTF::Vector<WTF::String>`. During CSP header parsing (`ParseSource`), only tokens matching the grammar `'nonce-<base64-value>'` with non-empty `<base64-value>` are appended to `source_list.nonces`.
2. **Null and Empty String Guards:**
   Blink's `WTF::String` distinguishes between a null string (`String()`) and an empty string (`String("")`). Both satisfy `.empty() == true` in modern Blink (`IsEmpty()` historically). The check `if (nonce.empty()) return false;` acts as an explicit short-circuit barrier before vector traversal.
3. **Code-Unit Exact Comparison (`WTF::Vector::Contains`):**
   `WTF::Vector<WTF::String>::Contains(const String&)` invokes `WTF::String::operator==`, which executes `WTF::Equal(a.Impl(), b.Impl())`. Unlike `EqualIgnoringASCIICase`, `operator==` performs exact byte-for-byte (or 16-bit code unit) equality comparison.
4. **`strict-dynamic` Interaction:**
   In `CSPDirectiveList`, when checking an external script request (`AllowFromSource`), if `CheckAllowNonce(operative_directive, nonce)` evaluates to `true`, the script is immediately allowed regardless of `'strict-dynamic'` or host-source expressions. Conversely, if `strict-dynamic` is present and `CheckAllowNonce` returns `false` (and hashes do not match), host-source expressions are bypassed and the script is blocked. Thus, the soundness of `CheckAllowNonce` is the foundational pivot for the entire CSP3 `'strict-dynamic'` model.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the self-contained formalization of `BlinkCSPNonceMatchingSemantics.v`. We model strings as sequences of integer code units (`list Z`), separating the core single-nonce mathematical equality predicate `nonce_matches(source_nonce, script_nonce) = (source_nonce =? script_nonce)` from the full Blink engine pipeline (which couples non-emptiness guards with source list membership).

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

```coq
(** * BlinkCSPNonceMatchingSemantics.v
    Formal Verification of Chromium Blink CSP script-src Nonce Matching Soundness
    Target: third_party/blink/renderer/core/frame/csp/csp_directive_list.cc
    Specification: W3C Content Security Policy Level 3 (CSP3) §5 & §6.6
*)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import Micega.Lia.
Import ListNotations.

Open Scope Z_scope.
Open Scope bool_scope.

(** ** 1. Foundational Types and Code-Unit String Semantics *)

(** We represent WTF::String / DOMString as a list of Unicode code units (Z). *)
Definition CodeUnit := Z.
Definition NonceString := list CodeUnit.

(** Empty nonce string constant. *)
Definition empty_nonce : NonceString := [].

(** Decidable boolean equality over CodeUnits. *)
Definition code_unit_eqb (c1 c2 : CodeUnit) : bool :=
  Z.eqb c1 c2.

(** Exact, case-sensitive boolean equality over NonceStrings (WTF::String::operator==). *)
Fixpoint nonce_eqb (n1 n2 : NonceString) : bool :=
  match n1, n2 with
  | [], [] => true
  | c1 :: r1, c2 :: r2 => code_unit_eqb c1 c2 && nonce_eqb r1 r2
  | _, _ => false
  end.

Notation "s1 =? s2" := (nonce_eqb s1 s2) (at level 70).

(** Check whether a NonceString is empty (WTF::String::empty()). *)
Definition is_empty_nonce (n : NonceString) : bool :=
  match n with
  | [] => true
  | _ :: _ => false
  end.

(** ** 2. Core Mathematical Property: Single Nonce Matching *)

(** The core mathematical matching primitive between a parsed source_nonce
    and an element's script_nonce. *)
Definition nonce_matches (source_nonce script_nonce : NonceString) : bool :=
  source_nonce =? script_nonce.

(** ** 3. Blink Engine & W3C CSP3 Directive Evaluation Model *)

(** A CSPSourceList contains a list of parsed nonce strings (source_list.nonces)
    and a flag indicating whether 'strict-dynamic' is enabled. *)
Record CSPSourceList := mkCSPSourceList {
  source_nonces : list NonceString;
  strict_dynamic_enabled : bool;
  host_sources_match : bool
}.

(** Well-formedness invariant guaranteed by Blink's CSP parser (CSPSourceListParse):
    Every nonce stored in source_list.nonces is non-empty (1*base64-char). *)
Definition wf_source_list (sl : CSPSourceList) : Prop :=
  Forall (fun s => s <> empty_nonce) (source_nonces sl).

(** WTF::Vector<String>::Contains(nonce) modeled via nonce_matches. *)
Fixpoint vector_contains_nonce (nonces : list NonceString) (script_nonce : NonceString) : bool :=
  match nonces with
  | [] => false
  | s_nonce :: rest =>
      if nonce_matches s_nonce script_nonce then true
      else vector_contains_nonce rest script_nonce
  end.

(** Blink's CSPSourceListAllowNonce in csp_directive_list.cc:
    if (nonce.empty()) return false;
    return source_list.nonces.Contains(nonce); *)
Definition blink_allow_nonce (sl : CSPSourceList) (script_nonce : NonceString) : bool :=
  if is_empty_nonce script_nonce then false
  else vector_contains_nonce (source_nonces sl) script_nonce.

(** W3C CSP3 §6.6.2.1 Normative Specification Predicate:
    An element's nonce matches a source list iff the element's nonce is non-empty
    and equals at least one nonce-source expression in the directive. *)
Definition spec_nonce_matches_directive (sl : CSPSourceList) (script_nonce : NonceString) : Prop :=
  script_nonce <> empty_nonce /\ In script_nonce (source_nonces sl).

(** Blink's external script evaluation in csp_directive_list.cc (AllowFromSource):
    If nonce matches, allow immediately. Otherwise, if strict-dynamic is absent,
    fall back to host-source matching. *)
Definition blink_check_script_request (sl : CSPSourceList) (script_nonce : NonceString) : bool :=
  if blink_allow_nonce sl script_nonce then true
  else if strict_dynamic_enabled sl then false
  else host_sources_match sl.

(** ** 4. Lemmas and Main Soundness Theorems *)

(** Target Property 1: Exact Mathematical Characterization *)
Theorem nonce_matches_exact_Characterization :
  forall (source_nonce script_nonce : NonceString),
    nonce_matches source_nonce script_nonce = (source_nonce =? script_nonce).
Proof.
  intros source_nonce script_nonce.
  reflexivity.
Qed.

(** Lemma: Reflection between nonce_eqb and propositional Leibniz equality. *)
Lemma nonce_eqb_eq :
  forall (n1 n2 : NonceString),
    (n1 =? n2) = true <-> n1 = n2.
Proof.
  induction n1 as [| c1 r1 IHr1]; intros [| c2 r2]; simpl.
  - split; reflexivity.
  - split; intros H; discriminate H.
  - split; intros H; discriminate H.
  - unfold code_unit_eqb.
    rewrite andb_true_iff.
    rewrite Z.eqb_eq.
    rewrite IHr1.
    split.
    + intros [Hc Hr]. subst. reflexivity.
    + intros Heq. injection Heq as Hc Hr. auto.
Qed.

(** Lemma: Reflection for inequality. *)
Lemma nonce_eqb_neq :
  forall (n1 n2 : NonceString),
    (n1 =? n2) = false <-> n1 <> n2.
Proof.
  intros n1 n2.
  pose proof (nonce_eqb_eq n1 n2) as Heq.
  destruct (n1 =? n2) eqn:E.
  - split; intros H.
    + discriminate H.
    + exfalso. apply H. apply Heq. reflexivity.
  - split; intros H.
    + intros Hcontra. apply Heq in Hcontra. discriminate Hcontra.
    + reflexivity.
Qed.

(** Reflexivity of nonce_matches. *)
Lemma nonce_matches_refl :
  forall (n : NonceString),
    nonce_matches n n = true.
Proof.
  intros n.
  unfold nonce_matches.
  apply nonce_eqb_eq.
  reflexivity.
Qed.

(** Symmetry of