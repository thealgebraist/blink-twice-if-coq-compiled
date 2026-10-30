# Formal Verification of Chromium Blink Content Security Policy Directive List Intersection

**Target Implementation:** `third_party/blink/renderer/core/frame/csp/content_security_policy.cc`  
**Normative Specification:** W3C Content Security Policy Level 3 (CSP3), §4 & §6  
**Formal Theory Target:** `BlinkCSPDirectiveIntersectionSemantics.v`  
**Core Property:** Monotonicity and Conjunctive Soundness of Effective Policy Evaluation ($\text{effective\_csp}(p_1, p_2)$ allows an action iff both $p_1$ and $p_2$ allow it).

---

## 1. Normative W3C Specification Requirements

In the W3C Content Security Policy Level 3 (CSP3) specification, a protected resource (Document, Worker, or Worklet) is governed by a **CSP list**—an ordered list of individual policy objects delivered via HTTP response headers (`Content-Security-Policy`, `Content-Security-Policy-Report-Only`) or HTML `<meta>` elements.

### 1.1 Policy Structure and Disposition
Per **CSP3 §2.2.1 (Policy)**, each policy $p$ in a CSP list has:
* **Directive Set**: A set of directives (e.g., `script-src`, `default-src`, `connect-src`), each containing a directive name and a value (source list).
* **Disposition**: Either `enforce` or `report`.
* **Source**: `header` or `meta`.

### 1.2 Multi-Policy Evaluation Semantics (CSP3 §4 & §6)
Per **CSP3 §4 (Framework)** and **§6.1 (Does request violate policy?)**, when a user agent evaluates whether a given action or resource request $r$ is permitted by a CSP list $L = [p_1, p_2, \dots, p_n]$, the policies are not merged syntactically prior to evaluation. Instead, each policy is evaluated independently, and their enforcement results are combined conjunctively:

1. **Pre-request check (CSP3 §6.1.1):** Iterate over every policy $p \in L$:
   * Evaluate the operative directive for the request context in $p$ (falling back to `default-src` if applicable per §6.4.1).
   * If the operative directive in $p$ returns `Does Not Match`:
     * A violation is generated and reported for $p$.
     * If $p$'s disposition is `enforce`, the overall check returns `Blocked`.
2. **Conjunctive Invariant:** A request is `Allowed` by a CSP list $L$ if and only if **every** policy $p \in L$ with disposition `enforce` evaluates to `Matches` (or has no applicable operative directive for that request type).
3. **Monotonicity of Policy Addition:** Adding a new `enforce` policy $p_{new}$ to an existing CSP list $L$ can only restrict or maintain the set of permitted actions; it can never expand the privileges of the execution context:
   $$\text{Allowed}(L \cup \{p_{new}\}, a) \implies \text{Allowed}(L, a) \land \text{Allowed}(\{p_{new}\}, a)$$

---

## 2. Chromium Blink Implementation Analysis

In Chromium's Blink rendering engine, Content Security Policy enforcement is implemented in `third_party/blink/renderer/core/frame/csp/content_security_policy.cc` (alongside Mojo structural representations in `services/network/public/cpp/content_security_policy/`).

### 2.1 Architectural Representation
Blink's `ContentSecurityPolicy` class maintains a vector of parsed policy structures:
```cpp
Vector<network::mojom::blink::ContentSecurityPolicyPtr> policies_;
```
Each `ContentSecurityPolicyPtr` (formerly managed via `CSPDirectiveList` in Blink before network-service CSP unification, with directive evaluation helpers in `csp_directive_list.cc`) represents a single HTTP header or `<meta>` policy instance.

### 2.2 Evaluation Loop & Bitwise Intersection Invariant
When Blink checks whether an action (such as loading an external script, executing inline script, or connecting via `fetch`) is permitted, `ContentSecurityPolicy` iterates over `policies_` and accumulates the boolean result using the **bitwise AND assignment operator (`&=`)** rather than short-circuit logical AND (`&&`).

For example, in `ContentSecurityPolicy::AllowFromSource` and `ContentSecurityPolicy::AllowInline`:

```cpp
bool ContentSecurityPolicy::AllowInline(
    InlineType inline_type,
    Element* element,
    const String& content,
    const String& nonce,
    const String& context_url,
    const OrdinalNumber& context_line,
    ReportingDisposition reporting_disposition) {
  bool is_allowed = true;
  for (const auto& policy : policies_) {
    is_allowed &=
        CSPDirectiveListAllowInline(*policy, this, inline_type, element,
                                    content, nonce, context_url, context_line,
                                    reporting_disposition);
  }
  return is_allowed;
}
```
And similarly for URL-based resource requests:
```cpp
bool is_allowed = true;
for (const auto& policy : policies_) {
  is_allowed &= CSPDirectiveListAllowFromSource(
      *policy, this, type, url, url_before_redirects, redirect_status,
      reporting_disposition, nonce, hashes, parser_disposition);
}
return is_allowed;
```

### 2.3 Critical Implementation Invariants
1. **Non-Short-Circuiting Conjunction (`&=`):** Blink uses `is_allowed &= ...` instead of `is_allowed = is_allowed && ...`. This is a vital specification compliance requirement: even if $p_1$ blocks the action (`is_allowed` becomes `false`), $p_2$ must still be evaluated so that violation reports (`report-uri` / `report-to` and `SecurityPolicyViolationEvent` dispatches) are generated for **all** violated policies in `policies_`. Semantically, on C++ `bool` values (`0` or `1`), `a &= b` computes exact logical conjunction $a \land b$.
2. **Report-Only Disposition Isolation:** Inside `CSPDirectiveListAllow*` (e.g., `CheckSourceAndReportViolation`), if a directive check fails, the violation is reported, but the function returns `!CSPDirectiveListIsReportOnly(policy)`:
   * If `header_type == kEnforce`: returns `false` on mismatch, `true` on match.
   * If `header_type == kReport`: returns `true` on both mismatch and match.
3. **Operative Directive Fallback (`OperativeDirective`):** Within a single `CSPDirectiveList`, `OperativeDirective(policy, type)` looks up `type` (e.g., `kScriptSrcAttr` $\to$ `kScriptSrc` $\to$ `kDefaultSrc`). Notice that fallback occurs **strictly within** a single `policy` struct before intersecting across `policies_`. If $p_1$ defines `default-src 'none'` and $p_2$ defines `script-src https://example.com`, for a script request to `https://example.com`:
   * $p_1$'s operative directive is `default-src 'none'` $\implies$ `false`.
   * $p_2$'s operative directive is `script-src https://example.com` $\implies$ `true`.
   * The intersection `false & true` yields `false`. A naive syntactic merge of directive maps prior to fallback would overwrite `default-src` or `script-src` and erroneously allow the load.

---

## 3. Formal Specification in Rocq/Coq

Below is the complete, self-contained formalization of Blink's CSP directive list intersection semantics in Rocq/Coq (`BlinkCSPDirectiveIntersectionSemantics.v`). It models actions, directive types, fallback chains, enforce vs. report-only dispositions, single-policy evaluation, multi-policy fold evaluation, and syntactic policy intersection.

```coq
(** * BlinkCSPDirectiveIntersectionSemantics.v
    Formal verification of Content Security Policy (CSP) directive list
    intersection semantics in Chromium Blink:
    third_party/blink/renderer/core/frame/csp/content_security_policy.cc
    Specification: W3C Content Security Policy Level 3, Section 4 & 6. *)

From Coq Require Import Bool.Bool.
From Coq Require Import Lists.List.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micega.Lia.
Import ListNotations.

Open Scope bool_scope.
Open Scope Z_scope.

(** ** 1. Core Domain Types *)

(** Resource / execution request contexts governed by CSP *)
Inductive DirectiveType : Type :=
  | DT_DefaultSrc
  | DT_ScriptSrc
  | DT_StyleSrc
  | DT_ImgSrc
  | DT_ConnectSrc
  | DT_FrameAncestors.

Scheme Equality for DirectiveType.

(** Abstract representation of a DOM/Network action (e.g. URL + Nonce + Hash + Context) *)
Record Action : Type := mkAction {
  act_context : DirectiveType;
  act_origin_id : Z;
  act_is_inline : bool;
  act_has_valid_nonce : bool
}.

(** Policy Disposition: Enforce vs Report-Only (network::mojom::ContentSecurityPolicyType) *)
Inductive Disposition : Type :=
  | Enforce
  | ReportOnly.

(** Source Expression Predicate: models a parsed CSPSourceList for a single directive.
    A CSPSourceList evaluates an Action to a boolean (Match / Does Not Match). *)
Definition SourceListMatcher := Action -> bool.

(** A single Policy (CSPDirectiveList) maps directive types to optional SourceListMatchers,
    coupled with its enforcement disposition. *)
Record CSPDirectiveList : Type := mkPolicy {
  policy_disposition : Disposition;
  policy_directives  : DirectiveType -> option SourceListMatcher
}.

(** ** 2. Blink Operative Directive Fallback Semantics *)

(** Models blink::CSPDirectiveListOperativeDirective:
    Fetch directives fall back to default-src if not explicitly specified.
    Non-fetch directives (like frame-ancestors) do not fall back to default-src. *)
Definition fallback_type (dt : DirectiveType) : option DirectiveType :=
  match dt with
  | DT_DefaultSrc     => None
  | DT_ScriptSrc      => Some DT_DefaultSrc
  | DT_StyleSrc       => Some DT_DefaultSrc
  | DT_ImgSrc         => Some DT_DefaultSrc
  | DT_ConnectSrc     => Some DT_DefaultSrc
  | DT_FrameAncestors => None
  end.

Definition operative_directive (p : CSPDirectiveList) (dt : DirectiveType)
  : option SourceListMatcher :=
  match p.(policy_directives) dt with
  | Some matcher => Some matcher
  | None =>
      match fallback_type dt with
      | Some fb_dt => p.(policy_directives) fb_dt
      | None => None
      end
  end.

(** ** 3. Single Policy Evaluation Semantics *)

(** Raw directive matching (ignoring disposition).
    If no operative directive exists for the action's context, CSP allows the action by default. *)
Definition raw_policy_matches (p : CSPDirectiveList) (a : Action) : bool :=
  match operative_directive p a.(act_context) with
  | Some matcher => matcher a
  | None => true
  end.

(** Effective enforcement decision of a single CSPDirectiveList in Blink:
     corresponds to CSPDirectiveListAllow* in csp_directive_list.cc.
    If the policy is ReportOnly, it always returns true for enforcement purposes
    (while emitting a report side-effect on raw mismatch). *)
Definition policy_allows (p : CSPDirectiveList) (a : Action) : bool :=
  match p.(policy_disposition) with
  | Enforce => raw_policy_matches p a
  | ReportOnly => true
  end.

(** ** 4. Multi-Policy Evaluation in ContentSecurityPolicy *)

(** Models the C++ loop in ContentSecurityPolicy::Allow*:
      bool is_allowed = true;
      for (const auto& policy : policies_) {
        is_allowed &= CSPDirectiveListAllow*(policy, ...);
      }
      return is_allowed;
*)
Fixpoint blink_eval_policies (policies : list CSPDirectiveList) (a : Action) : bool :=
  match policies with
  | [] => true
  | p :: rest => andb (policy_allows p a) (blink_eval_policies rest a)
  end.

(** Exact accumulator-based loop matching the C++ stateful `is_allowed &= ...` implementation *)
Fixpoint blink_loop_acc (acc : bool) (policies : list CSPDirectiveList) (a : Action) : bool :=
  match policies with
  | [] => acc
  | p :: rest => blink_loop_acc (andb acc (policy_allows p a)) rest a
  end.

Definition blink_allow_loop (policies : list CSPDirectiveList) (a : Action) : bool :=
  blink_loop_acc true policies a.

(** ** 5. Effective Policy Intersection Construction *)

(** Constructs a single synthetic effective policy from two policies p1 and p2
    that resolves operative directives prior to intersecting matchers.
    This captures the exact algebraic representation of `effective_csp(p1, p2)`. *)
Definition effective_matcher_for (p1 p2 : CSPDirectiveList) (dt : DirectiveType)
  : SourceListMatcher :=
  fun (a : Action) =>
    let allow1 :=
      match p1.(policy_disposition) with
      | Enforce =>
          match operative_directive p1 dt with
          | Some m1 => m1 a
          | None => true
          end
      | ReportOnly => true
      end in
    let allow2 :=
      match p2.(policy_disposition) with
      | Enforce =>
          match operative_directive p2 dt with
          | Some m2 => m2 a
          | None => true
          end
      | ReportOnly => true
      end in
    andb allow1 allow2.

Definition effective_csp (p1 p2 : CSPDirectiveList) : CSPDirectiveList :=
  mkPolicy
    Enforce
    (fun dt => Some (effective_matcher_for p1 p2 dt)).
```

---

## 4. Concrete Theorems and Complete Proofs in Rocq/Coq

We now state and prove the core security theorems without any admitted lemmas. We also include an integer-bounded security metric using `ZArith` and `Lia` to formally quantify privilege reduction across policy intersections.

```coq
(** * Formal Proofs of CSP Intersection Soundness and Monotonicity *)

(** ** Theorem 1: Equivalence of Accumulator Loop (`&=`) and Functional Specification *)
Lemma blink_loop_acc_equiv : forall (policies : list CSPDirectiveList) (a : Action) (acc : bool),
  blink_loop_acc acc policies a = andb acc (blink_eval_policies policies a).
Proof.
  induction policies as [| p rest IH]; intros a acc.
  - simpl. rewrite andb_true_r. reflexivity.
  - simpl. rewrite IH. rewrite andb_assoc. reflexivity.
Qed.

Theorem blink_allow_loop_correct : forall (policies : list CSPDirectiveList) (a : Action),
  blink_allow_loop policies a = blink_eval_policies policies a.
Proof.
  int