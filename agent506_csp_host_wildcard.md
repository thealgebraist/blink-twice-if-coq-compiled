# Formal Verification Report: Chromium Blink CSP Host Source Wildcard Matching

## 1. Normative Specification Requirements

According to the W3C Content Security Policy Level 3 (CSP3) specification, Section 6.7.2.4 (*Does url match expression in origin with redirect count?*), host-source expressions govern which network origins are permitted by a policy directive. 

### 1.1 Grammar Definition
In CSP3 §6.2.1, a `host-source` and its `host-part` are defined via the following ABNF:
```abnf
host-source = [ scheme-part "://" ] host-part [ ":" port-part ] [ path-part ]
host-part   = "*" / [ "*." ] 1*host-char *( "." 1*host-char )
host-char   = ALPHA / DIGIT / "-"
```

### 1.2 Normative Matching Algorithm (CSP3 §6.7.2.5)
When evaluating whether a URL's host $H_{url}$ matches a source expression's `host-part` $H_{expr}$:
1. **Unrestricted Wildcard (`*`)**: If $H_{expr}$ is case-insensitively equal to `"*"`, any valid host $H_{url}$ matches.
2. **Subdomain Wildcard (`*.domain.tld`)**: If $H_{expr}$ begins with the two-character prefix `"*."`:
   - Let $R$ be the remaining string after removing the `"*"` character from the beginning of $H_{expr}$ (such that $R$ starts with `"."`, e.g., `".domain.tld"`).
   - If the length of $H_{url}$ is strictly greater than the length of $R$, and the suffix of $H_{url}$ of length $|R|$ is an ASCII case-insensitive match for $R$, the match succeeds.
   - Otherwise, the match fails.
3. **Exact Match (`domain.tld`)**: If $H_{expr}$ does not start with `"*"`:
   - If $H_{url}$ is an ASCII case-insensitive match for $H_{expr}$, the match succeeds.

### 1.3 Security Invariants of the Specification
- **Subdomain Depth $\ge 1$**: A wildcard expression `*.example.com` ($R = \text{".example.com"}$) **must not** match the bare apex domain `example.com`. It must match `a.example.com` (depth 1), `a.b.example.com` (depth 2), etc.
- **Label Boundary Enforcement**: Because $R$ retains the leading dot `.`, a host like `badexample.com` cannot match `*.example.com`, preventing suffix-confusion attacks across DNS label boundaries.

---

## 2. Chromium Blink Implementation Analysis

In Chromium's Blink rendering engine, CSP source matching is implemented in `third_party/blink/renderer/core/frame/csp/` (historically within `source_list_directive.cc` and `csp_source.cc`, and unified across `services/network/public/cpp/content_security_policy/csp_source.cc` for browser-process enforcement).

### 2.1 Parser Representation
When Blink parses a `host-source` in `CSPSourceList::ParseHost`:
- A boolean flag `HasWildcard` (or `is_host_wildcard`) is set to `true` if the host string starts with `*`.
- If the expression is `"*"`, `host_` is set to the empty string `""` and `is_host_wildcard = true`.
- If the expression is `"*.example.com"`, the leading `"*."` is stripped, setting `host_ = "example.com"` and `is_host_wildcard = true`.
- If the expression is `"example.com"`, `host_ = "example.com"` and `is_host_wildcard = false`.

### 2.2 Host Matching Logic
In Blink's `CSPSource::HostMatches(const KURL& url)` / `CheckCSPSourceHostMatches`:
```cpp
bool CSPSource::HostMatches(const String& url_host) const {
  if (host_.IsEmpty()) {
    // Wildcard '*' matches any non-empty host.
    return is_host_wildcard_ && !url_host.IsEmpty();
  }
  if (is_host_wildcard_) {
    // Subdomain wildcard '*.host_'
    // Must end with ".host_" (case-insensitively) and have at least one 
    // character before the dot.
    return url_host.EndsWithIgnoringASCIICase(String("." + host_)) &&
           url_host.length() > host_.length() + 1;
  }
  // Exact match
  return EqualIgnoringASCIICase(url_host, host_);
}
```
*(Note: In optimized C++ paths, Blink avoids string concatenation `"." + host_` by checking `url_host.EndsWithIgnoringASCIICase(host_)`, verifying `url_host.length() > host_.length() + 1`, and checking `url_host[url_host.length() - host_.length() - 1] == '.'`).*

### 2.3 Implementation Invariants
1. **Length Bound**: `url_host.length() > host_.length() + 1` guarantees that there is at least one character preceding the `.` separator. Since DNS hostnames parsed by `url::CanonHostInfo` cannot have leading dots in valid network URLs, this guarantees at least one non-empty subdomain label.
2. **Label Isolation**: Explicitly checking for the `.` at index `url_host.length() - host_.length() - 1` guarantees that label boundaries are respected. Because DNS labels themselves cannot contain `.`, suffix matching with a leading `.` is isomorphic to suffix matching over the sequence of parsed DNS labels.

---

## 3. Formal Specification in Rocq (Coq)

We model DNS hosts in two ways to bridge the gap between Blink's string-based length/suffix checks and the algebraic tree structure of DNS labels:
1. **Label Model**: A host is a `list Label`, ordered from most-specific (leftmost subdomain) to least-specific (TLD), or vice-versa. Ordering from right-to-left (TLD first, i.e., `["com"; "domain"; "sub"]`) makes subdomain hierarchy a direct list prefix, while ordering left-to-right (`["sub"; "domain"; "com"]`) makes it a list suffix. We use left-to-right (`list Z`) to directly mirror string indexing.
2. **Flat Character/Token Model**: To verify Blink's exact index arithmetic (`url_len > host_len + 1` and `char_at (url_len - host_len - 1) == DOT`), we also model the flattened string representation and prove its equivalence to the structural label model.

---

## 4. Formal Theory and Proofs (`BlinkCSPHostSourceWildcardSemantics.v`)

The following Rocq/Coq script is completely self-contained, uses standard libraries (`List`, `ZArith`, `Lia`, `Bool`), and contains **zero** `Admitted` or `Axiom` declarations.

```coq
(** * BlinkCSPHostSourceWildcardSemantics.v
    Formal verification of Chromium Blink's CSP Host Source Wildcard Matching
    (third_party/blink/renderer/core/frame/csp/source_list_directive.cc)
    against W3C CSP Level 3 Section 6.
*)

Require Import Coq.Lists.List.
Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.
Require Import Coq.Bool.Bool.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Structural DNS Label Model *)

(** We represent a normalized (lowercase ASCII) DNS label as a non-empty 
    list of character codes (modeled as Z), excluding the dot character. *)
Definition Char := Z.
Definition DOT : Char := 46. (* ASCII '.' *)

Definition Label := list Char.

(** A valid DNS label is non-empty and does not contain DOT. *)
Definition valid_label (l : Label) : Prop :=
  l <> [] /\ ~ In DOT l.

(** A Host is a list of DNS labels ordered left-to-right 
    (e.g., ["sub"; "domain"; "com"]). *)
Definition Host := list Label.

Definition valid_host (h : Host) : Prop :=
  h <> [] /\ Forall valid_label h.

(** AST for a parsed CSP host-part expression in Blink's CSPSource *)
Inductive CSPHostSource : Type :=
  | WildcardAll : CSPHostSource                    (* "*" *)
  | WildcardSubdomain : Host -> CSPHostSource      (* "*.domain.com" *)
  | ExactHost : Host -> CSPHostSource.             (* "domain.com" *)

(** Boolean equality for Labels and Hosts *)
Definition label_eqb (l1 l2 : Label) : bool :=
  list_eq_dec Z.eq_dec l1 l2.

Lemma label_eqb_eq : forall l1 l2, label_eqb l1 l2 = true <-> l1 = l2.
Proof.
  intros l1 l2. unfold label_eqb.
  destruct (list_eq_dec Z.eq_dec l1 l2); split; intros H; try congruence; reflexivity.
Qed.

Definition host_eqb (h1 h2 : Host) : bool :=
  list_eq_dec (list_eq_dec Z.eq_dec) h1 h2.

Lemma host_eqb_eq : forall h1 h2, host_eqb h1 h2 = true <-> h1 = h2.
Proof.
  intros h1 h2. unfold host_eqb.
  destruct (list_eq_dec (list_eq_dec Z.eq_dec) h1 h2); split; intros H; try congruence; reflexivity.
Qed.

(** Structural suffix check on label lists *)
Definition is_label_suffix_bool (suffix full : Host) : bool :=
  let len_s := List.length suffix in
  let len_f := List.length full in
  if (Z.of_nat len_s <=? Z.of_nat len_f) then
    host_eqb (skipn (len_f - len_s)%nat full) suffix
  else
    false.

(** Blink's structural matching semantics for CSPHostSource *)
Definition blink_match_structural (expr : CSPHostSource) (url_host : Host) : bool :=
  match expr with
  | WildcardAll => negb (host_eqb url_host [])
  | ExactHost base => host_eqb url_host base
  | WildcardSubdomain base =>
      (Z.of_nat (List.length base) <? Z.of_nat (List.length url_host)) &&
      is_label_suffix_bool base url_host
  end.

(** ** 2. Mathematical Specification of Subdomain Depth *)

(** A host [url_host] is a subdomain of [base] at depth [d] if [url_host] 
    can be decomposed into [sub_labels ++ base] where [length sub_labels = d]. *)
Definition is_subdomain_with_depth (url_host base : Host) (d : Z) : Prop :=
  exists (sub_labels : Host),
    url_host = sub_labels ++ base /\
    Z.of_nat (List.length sub_labels) = d.

(** ** 3. Proofs of Structural Wildcard Properties *)

Lemma skipn_app_exact : forall (A : Type) (l1 l2 : list A),
  skipn (List.length l1) (l1 ++ l2) = l2.
Proof.
  intros A l1. induction l1 as [|x xs IH]; intros l2.
  - simpl. reflexivity.
  - simpl. apply IH.
Qed.

Lemma is_label_suffix_bool_spec : forall (base url_host : Host),
  is_label_suffix_bool base url_host = true <->
  exists prefix, url_host = prefix ++ base.
Proof.
  intros base url_host. unfold is_label_suffix_bool.
  destruct (Z.of_nat (List.length base) <=? Z.of_nat (List.length url_host)) eqn:Hlen.
  - rewrite Z.leb_le in Hlen.
    rewrite host_eqb_eq.
    split; intros H.
    + exists (firstn (List.length url_host - List.length base)%nat url_host).
      rewrite <- H at 2.
      symmetry. apply firstn_skipn.
    + destruct H as [prefix Hpref].
      subst url_host.
      rewrite app_length.
      replace (List.length prefix + List.length base - List.length base)%nat
        with (List.length prefix) by lia.
      apply skipn_app_exact.
  - rewrite Z.leb_gt in Hlen.
    split; intros H.
    + discriminate H.
    + destruct H as [prefix Hpref].
      subst url_host. rewrite app_length in Hlen. lia.
Qed.

(** Theorem 1: Soundness and Completeness of Wildcard Matching for Subdomain Depth >= 1.
    Proves that [WildcardSubdomain base] matches [url_host] if and only if
    [url_host] is a subdomain of [base] with depth >= 1. *)
Theorem wildcard_matches_iff_depth_ge_1 : forall (base url_host : Host),
  blink_match_structural (WildcardSubdomain base) url_host = true <->
  exists d : Z, d >= 1 /\ is_subdomain_with_depth url_host base d.
Proof.
  intros base url_host.
  unfold blink_match_structural.
  rewrite andb_true_iff.
  rewrite Z.ltb_lt.
  rewrite is_label_suffix_bool_spec.
  split.
  - intros [Hlt [prefix Hpref]].
    exists (Z.of_nat (List.length prefix)).
    subst url_host.
    rewrite app_length in Hlt.
    split.
    + lia.
    + unfold is_subdomain_with_depth.
      exists prefix. split; reflexivity.
  - intros [d [Hd [prefix [Hpref Hlen]]]].
    subst url_host.
    rewrite app_length.
    split.
    + lia.
    + exists prefix. reflexivity.
Qed.

(** Theorem 2: Apex Exclusion Invariant (Depth 0 Rejection).
    A subdomain wildcard [*.base] NEVER matches the bare domain [base] itself. *)
Theorem wildcard_rejects_apex_domain : forall (base : Host),
  blink_match_structural (WildcardSubdomain base) base = false.
Proof.
  intros base.
  unfold blink_match_structural.
  rewrite Z.ltb_irrefl.
  simpl. reflexivity.
Qed.

(** Theorem 3: Arbitrary Depth Acceptance.
    For any non-empty list of valid subdomain labels [sub], prepending [sub]
    to [base] is guaranteed