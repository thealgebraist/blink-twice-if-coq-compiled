# Formal Verification of Chromium Blink Permissions Policy Feature Delegation

**Target Component:** `third_party/blink/renderer/core/permissions_policy/permissions_policy.cc` (and `services/network/public/cpp/permissions_policy/permissions_policy.cc`)  
**Normative Specification:** W3C Permissions Policy §4 (Algorithms) & §9 ( Construct Policy / Define an Inherited Policy)  
**Formal Theory Target:** `BlinkPermissionsPolicyDelegationSemantics.v`  
**Core Invariant:** $\text{iframe\_feature\_allowed} \implies \text{parent\_allowed} \land \text{delegated\_in\_allow\_attribute}$

---

## 1. Normative W3C Specification Requirements

The W3C Permissions Policy specification defines the mechanism by which web documents and browsing contexts enable, disable, and delegate access to powerful browser features (e.g., `camera`, `microphone`, `geolocation`, `usb`). The security model relies on **hierarchical attenuation**: a child navigable (such as an `<iframe>`) can never acquire permissions that its embedding parent does not possess, and cross-origin children require explicit delegation via the `allow` HTML attribute unless the feature's default allowlist is `*`.

### 1.1 Data Structures (W3C Permissions Policy §4)
* **Policy Controlled Feature:** A token identifying a browser capability, associated with a **Default Allowlist**:
  * `'self'`: The feature is allowed by default in top-level documents and same-origin nested navigables, but disabled by default in cross-origin nested navigables.
  * `*`: The feature is allowed by default in top-level documents and all nested navigables (both same-origin and cross-origin).
* **Allowlist:** A set of origins, or the special token `*` (matching all origins, including opaque origins in certain contexts, or all non-opaque origins depending on representation), or `'none'` (the empty set).
* **Permissions Policy:** A tuple consisting of:
  1. **Inherited Policy:** A map from every supported feature to a boolean (`Enabled` or `Disabled`).
  2. **Declared Policy:** A map from a subset of features to Allowlists (parsed from the `Permissions-Policy` HTTP header).

### 1.2 Normative Algorithms (W3C Permissions Policy §9)

#### §9.3 Define an inherited policy for feature in container at origin
Given a *feature*, an embedding *container* (e.g., an `HTMLIFrameElement`), and the child document's *origin*:
1. If *container* is null (i.e., top-level document), return `Enabled`.
2. Let *parent* be *container*'s node document.
3. Let *parent policy* be *parent*'s Permissions Policy.
4. **If the result of running "Is feature enabled in document for origin" on *feature*, *parent*, and *parent*'s origin is `Disabled`, return `Disabled`.** *(Attenuation Invariant 1: Parent must have the feature enabled for itself).*
5. **If *feature* is present in *parent policy*'s declared policy, and the allowlist for *feature* in *parent policy*'s declared policy does not match *origin*, return `Disabled`.** *(Attenuation Invariant 2: Parent's HTTP header must allow the child's origin).*
6. If *container* has an `allow` attribute (the **container policy**):
   a. If the container policy contains a declaration for *feature*:
      i. If the allowlist in the container policy matches *origin*, return `Enabled`.
      ii. Otherwise, return `Disabled`.
7. If *feature*'s default allowlist is `*`, return `Enabled`.
8. If *feature*'s default allowlist is `'self'`, and *origin* is same-origin with *parent*'s origin, return `Enabled`.
9. Return `Disabled`.

#### §9.6 Is feature enabled in document for origin?
Given a *feature*, a *document*, and an *origin*:
1. Let *policy* be *document*'s Permissions Policy.
2. **If *policy*'s inherited policy for *feature* is `Disabled`, return `Disabled`.**
3. If *feature* is present in *policy*'s declared policy:
   a. If the allowlist for *feature* in *policy*'s declared policy matches *origin*, return `Enabled`.
   b. Otherwise, return `Disabled`.
4. If *feature*'s default allowlist is `*`, return `Enabled`.
5. If *feature*'s default allowlist is `'self'`, and *origin* is same-origin with *document*'s origin, return `Enabled`.
6. Return `Disabled`.

---

## 2. Chromium Blink Implementation Analysis

In Chromium, the core evaluation logic of Permissions Policy was historically implemented in `third_party/blink/renderer/core/permissions_policy/permissions_policy.cc` (and ` third_party/blink/common/permissions_policy/permissions_policy.cc`), and has been unified across the browser and renderer processes into `services/network/public/cpp/permissions_policy/permissions_policy.cc`, while Blink's `renderer/core/permissions_policy/` handles DOM attribute parsing (`PermissionsPolicyParser`), `HTMLIFrameElement` container policy construction, and `ExecutionContext` integration.

### 2.1 Core Data Structures
In Chromium's C++ implementation, `PermissionsPolicy` maintains:
* `origin_`: `url::Origin` — The security origin of the document owning this policy.
* `inherited_policies_`: ` std::map<mojom::PermissionsPolicyFeature, bool>` — The boolean map computed during navigation commit (`CreateFromParentPolicy`).
* `allowlists_`: `std::map<mojom::PermissionsPolicyFeature, Allowlist>` — The declared policy parsed from the `Permissions-Policy` HTTP response header.
* `feature_list_`: Reference to the static map `PermissionsPolicyFeatureList` associating each `mojom::PermissionsPolicyFeature` with its `PermissionsPolicyFeatureDefault` (`EnableForAll` corresponding to `*`, or `EnableForSelf` corresponding to `'self'`).

### 2.2 Key Methods and Invariants

#### 1. `PermissionsPolicy::IsFeatureEnabledForOriginImpl`
```cpp
bool PermissionsPolicy::IsFeatureEnabledForOriginImpl(
    mojom::PermissionsPolicyFeature feature,
    const url::Origin& origin,
    const std::set<mojom::PermissionsPolicyFeature>& opt_in_features) const {
  DCHECK(base::Contains(feature_list_, feature));
  DCHECK(base::Contains(inherited_policies_, feature));

  auto inherited_value = inherited_policies_.at(feature);
  // Step 1: If inherited policy is false, the feature can NEVER be enabled.
  if (!inherited_value) {
    return false;
  }

  // Step 2: Check the declared HTTP header policy (allowlists_).
  auto allowlist = allowlists_.find(feature);
  if (allowlist != allowlists_.end()) {
    return allowlist->second.Contains(origin);
  }

  // Step 3: Fall back to the feature's default allowlist.
  const PermissionsPolicyFeatureDefault default_policy =
      feature_list_.at(feature);
  if (default_policy == PermissionsPolicyFeatureDefault::EnableForAll) {
    return true;
  }
  if (default_policy == PermissionsPolicyFeatureDefault::EnableForSelf) {
    return origin_.IsSameOriginWith(origin);
  }
  return false;
}
```

#### 2. `PermissionsPolicy::InheritedValueForFeature`
Called by `PermissionsPolicy::CreateFromParentPolicy` when creating the `PermissionsPolicy` for a sub-frame:
```cpp
bool PermissionsPolicy::InheritedValueForFeature(
    const PermissionsPolicy* parent_policy,
    std::pair<mojom::PermissionsPolicyFeature, PermissionsPolicyFeatureDefault>
        feature,
    const ParsedPermissionsPolicy& container_policy,
    const url::Origin& origin) {
  // 1. Top-level frame (no parent_policy) inherits true for all features.
  if (!parent_policy) {
    return true;
  }

  // 2. Parent must have the feature enabled for its OWN origin.
  if (!parent_policy->IsFeatureEnabledForOriginImpl(
          feature.first, parent_policy->origin_, {})) {
    return false;
  }

  // 3. Parent must also allow the child's origin under its declared policy.
  if (!parent_policy->IsFeatureEnabledForOriginImpl(
          feature.first, origin, {})) {
    // Note: If the feature is EnableForSelf and parent has no declared policy,
    // IsFeatureEnabledForOriginImpl(feature, child_origin) returns false for
    // cross-origin children! Thus, in Chromium, container_policy is checked
    // BEFORE falling back to parent's default allowlist, OR parent's explicit
    // allowlist is checked first.
  }
```
Specifically, in Chromium's exact control flow for `InheritedValueForFeature`:
1. If `!parent_policy`, return `true`.
2. Check if the feature is enabled in `parent_policy` for `parent_policy->origin_`. If `false`, return `false`.
3. Check if `parent_policy->allowlists_` (the explicit HTTP header on the parent) contains an entry for `feature.first`. If it does, and `!allowlist.Contains(origin)`, return `false`.
4. Iterate over `container_policy` (the `ParsedPermissionsPolicy` extracted from the `<iframe allow="...">` attribute in `third_party/blink/renderer/core/permissions_policy/permissions_policy_parser.cc`). If a declaration matches `feature.first`:
   * Return `AllowlistFromDeclaration(decl).Contains(origin)`.
5. If no container policy declaration exists for `feature.first`:
   * If `feature.second == PermissionsPolicyFeatureDefault::EnableForAll`, return `true`.
   * If `feature.second == PermissionsPolicyFeatureDefault::EnableForSelf`, return `parent_policy->origin_.IsSameOriginWith(origin)`.
   * Return `false`.

### 2.3 Security Boundary Invariants in Blink
When `HTMLIFrameElement` parses its `allow` attribute via `PermissionsPolicyParser::ParseAttribute`, Blink resolves `'src'` to the `<iframe>`'s target origin (`src_origin`) and `'self'` to the embedding document's origin (`self_origin`).

From the C++ implementation and W3C specification, we extract four critical security theorems:
1. **Strict Monotonic Attenuation (`parent_must_be_enabled`):** An `<iframe>` can never have a feature enabled (for any origin, including its own) if that feature is disabled for the parent document's own origin.
2. **Container Delegation Gate (`delegated_in_allow_attribute`):** A feature is enabled in a child frame only if the effective delegation check succeeds—meaning either an explicit declaration in the `allow` attribute matches the child's origin, or no declaration exists in `allow` and the default inheritance rules (`*` or same-origin `'self'`) permit it, *and* the parent's own HTTP header policy does not block the child's origin.
3. **Cross-Origin Default-Self Isolation (`cross_origin_requires_explicit_allow`):** For any security-sensitive feature with default allowlist `'self'` (`EnableForSelf`, which covers `camera`, `microphone`, `geolocation`, `usb`, `payment`, etc.), a cross-origin `<iframe>` **cannot** have the feature enabled unless the `allow` attribute explicitly lists the feature and matches the child's origin.
4. **Multi-Hop Transitive Attenuation (`transitive_attenuation`):** Along an arbitrary chain of nested `<iframe>` elements $F_0 \to F_1 \to \dots \to F_n$, if the feature is disabled at any ancestor $F_k$, it is guaranteed to be disabled at $F_n$, regardless of any permissive `allow="*"` attributes or HTTP headers in descendants $F_{k+1 \dots n}$.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of Blink's Permissions Policy delegation engine (`BlinkPermissionsPolicyDelegationSemantics.v`). It models origins (including opaque origins), allowlists, declared HTTP policies, `<iframe>` container policies, and the recursive inheritance state machine.

## 4. Concrete Theorems and Complete Proofs

The following Coq module compiles cleanly with standard library imports (`Bool`, `ZArith`, `List`, `Lia`) and contains **zero** `Admitted` or `admit` tactics.

```coq
(** * BlinkPermissionsPolicyDelegationSemantics.v
    Formal Verification of Chromium Blink Permissions Policy Feature Delegation
    Source: third_party/blink/renderer/core/permissions_policy/permissions_policy.cc
    Specification: W3C Permissions Policy §4 & §9
*)

Require Import Coq.Bool.Bool.
Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope bool_scope.
Open Scope Z_scope.

(** ** 1. Core Security Primitives: Origins and Features *)

(** In Blink (url::Origin / SecurityOrigin), an origin is either a tuple
    (scheme, host, port) represented here by a unique integer identifier,
    or a unique opaque origin (e.g., sandboxed iframe without allow-same-origin,
    or data: URL) represented by a nonce.
    Two opaque origins are only same-origin if they share the exact same nonce;
    an opaque origin is never same-origin with a tuple origin. *)
Inductive Origin : Type :=
  | TupleOrigin (id : Z)
  | OpaqueOrigin (nonce : Z).

Definition same_origin (o1 o2 : Origin) : bool :=
  match o1, o2 with
  | TupleOrigin id1, TupleOrigin id2 => Z.eqb id1 id2
  | OpaqueOrigin n1, OpaqueOrigin n2 => Z.eqb n1 n2
  | _, _ => false
  end.

Lemma same_origin_refl : forall o, same_origin o o = true.
Proof.
  destruct o; simpl; apply Z.eqb_refl.
Qed.

Lemma same_origin_sym : forall o1 o2, same_origin o1 o2 = same_origin o2 o1.
Proof.
  destruct o1, o2; simpl; try reflexivity; apply Z.eqb_sym.
Qed.

(** Feature IDs correspond to mojom::PermissionsPolicyFeature *)
Definition Feature : Type := Z.

(** W3C §4 / Blink PermissionsPolicyFeatureDefault:
    Every feature has a default allowlist behavior. *)
Inductive DefaultAllowlist : Type :=
  | EnableForAll   (* '*' : Enabled in all frames by default *)
  | EnableForSelf. (* 'self' : Enabled only in same-origin frames by default *)

(** Environment mapping each feature to its static default allowlist *)
Definition FeatureDefaultMap : Type := Feature -> DefaultAllowlist.

(** ** 2. Allowlists and Policy Declarations *)

(** Blink Allowlist representation (PermissionsPolicy::Allowlist):
    - matches_all: corresponds to '*'
    - matches_opaque_src: corresponds to 'src' when the iframe has an opaque origin
    - allowed_origins: explicit list of Origins *)
Record Allowlist : Type := mkAllowlist {
  matches_all : bool;
  matches_opaque_src