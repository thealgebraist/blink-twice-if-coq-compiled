# Formal Verification of Chromium's Cross-Origin-Opener-Policy (COOP) Browsing Context Group Switch Engine

**Subject**: Cross-Origin-Opener-Policy (COOP) Browsing Context Group Switch Semantics  
**Chromium Subsystem**: `content/browser/renderer_host/cross_origin_opener_policy_status.cc`  
**Normative Specification**: WHATWG HTML Standard §7.4 ("Cross-Origin-Opener-Policy")  
**Formal Verification Target**: `BlinkCOOPBrowsingContextGroupSwitchSemantics.v`  
**Core Invariant**: `coop_swap = (coop_same_origin && !same_origin_opener)`  

---

## 1. Normative Specification Requirements (WHATWG HTML Standard §7.4)

In the Web Platform security model, Browsing Context Groups (BCGs) define the fundamental unit of synchronous script access and shared process space in user agents. Top-level browsing contexts belonging to the same BCG can hold JavaScript references (`window.opener`, `window.open()` return values) to one another, compelling browsers without strict Cross-Origin Isolation to place mutually reachable documents into a shared or coupled scheduling group, exposing them to Spectre-class side-channel attacks.

### 1.1 Policy Values and Cross-Origin-Isolation
According to WHATWG HTML Standard §7.4.1 (*Cross-Origin-Opener-Policy headers*), a document's opener policy consists of a `value` and a `report-only-value` taken from the following enumeration:

1. `"unsafe-none"`: The default value. The document remains in its current Browsing Context Group unless forced out by the *other* document's policy during navigation.
2. `"same-origin-allow-popups"`: The document forces a BCG switch on navigation unless the navigation is between two `"same-origin-allow-popups"` documents that are same-origin, or if the document is opening an `"unsafe-none"` popup via `window.open()`.
3. `"same-origin"`: The document strictly isolates its BCG to same-origin documents that also assert `"same-origin"`.
4. `"same-origin-plus-COEP"`: An internal augmented value resulting from combining `Cross-Origin-Opener-Policy: same-origin` with a compatible `Cross-Origin-Embedder-Policy` (`require-corp` or `credentialless`). This state is a prerequisite for setting `window.crossOriginIsolated = true` and unlocking `SharedArrayBuffer` and high-resolution timers.

### 1.2 Normative BCG Switch Algorithm (§7.4.3)
When navigating a top-level browsing context from an active document with origin $O_{\text{active}}$ and opener policy $P_{\text{active}}$ to a new response with origin $O_{\text{response}}$ and opener policy $P_{\text{response}}$, the HTML Standard (§7.4.3, *"Check if a browsing context group switch is needed"*) mandates the evaluation of the predicate $\text{ MatchOpenerPolicy}(P_{\text{active}}, O_{\text{active}}, P_{\text{response}}, O_{\text{response}})$:

$$\text{MatchOpenerPolicy}(P_A, O_A, P_B, O_B) \iff \begin{cases} 
\text{true} & \text{if } P_A = \text{unsafe-none} \land P_B = \text{unsafe-none} \\
\text{true} & \text{if } P_A = P_B \land P_A \neq \text{unsafe-none} \land \text{SameOrigin}(O_A, O_B) \\
\text{false} & \text{otherwise}
\end{cases}$$

A Browsing Context Group switch (`coop_swap = true`) is required if and only if:
1. $\neg \text{MatchOpenerPolicy}(P_{\text{active}}, O_{\text{active}}, P_{\text{response}}, O_{\text{response}})$ holds, OR
2. The browsing context has an existing opener relationship, $P_{\text{response}} = \text{same-origin-allow-popups}$, and the opener policy transitions from an incompatible state.

When restricting to the core `same-origin` policy boundary against a baseline opener context (where the active context is evaluated against a candidate asserting `same-origin` or vice-versa), the fundamental isolation requirement reduces to the core mathematical property:

$$\text{coop\_swap} \iff (\text{coop\_same\_origin} \land \neg \text{same\_origin\_opener})$$

When `coop_swap` evaluates to `true`, the browser must sever all `window.opener` links, allocate a new `BrowsingInstance` (BCG), and disallow synchronous cross-window DOM access across the navigation boundary.

---

## 2. Chromium Blink / Content Implementation Analysis

In Chromium's `content/browser/` architecture, top-level navigation policy enforcement is decoupled from Blink's renderer process and executed strictly within the trustworthy Browser Process inside `content/browser/renderer_host/`.

### 2.1 Architecture of `cross_origin_opener_policy_status.cc`
The state machine governing COOP transitions during a navigation is implemented in `content::CrossOriginOpenerPolicyStatus`. It attaches to a `NavigationRequest` and intercepts every redirect (`EnforceCOOP` called from `NavigationRequest::OnRedirectChecksComplete`) and the final response (`NavigationRequest::OnResponseStarted`).

Key structural components in `cross_origin_opener_policy_status.cc`:
* **`BrowsingInstance` (`SiteInstanceImpl`)**: Chromium's internal representation of the HTML Browsing Context Group. A BCG switch manifests in Chromium as forcing a swap to a new `SiteInstance` belonging to a freshly minted `BrowsingInstanceId`.
* **`CoopSwapResult`**: An enumeration tracking the strength of the required swap:
  * `kNoSwap`: Keep the existing `BrowsingInstance`.
  * `kSwapRelated`: Sever `window.opener` and DOM references, creating a new `BrowsingInstance`, but preserve certain meta-relations for Coop-Report-Only metrics (`VirtualBrowsingContextGroup`).
  * `kSwap`: Complete, irrevocable `BrowsingInstance` replacement and process boundary isolation.

### 2.2 Implementation Invariants in `MatchCOOP` and `ShouldSwapBrowsingInstanceForCrossOriginOpenerPolicy`
In `content/browser/renderer_host/cross_origin_opener_policy_status.cc` (in conjunction with `network::mojom::CrossOriginOpenerPolicyValue` helpers), Chromium evaluates BCG swaps using the following logic:

```cpp
// Conceptual distillation of Chromium's COOP matching in cross_origin_opener_policy_status.cc
bool MatchCOOP(network::mojom::CrossOriginOpenerPolicyValue initiator_coop,
               const url::Origin& initiator_origin,
               network::mojom::CrossOriginOpenerPolicyValue destination_coop,
               const url::Origin& destination_origin) {
  if (initiator_coop != destination_coop)
    return false;
  if (initiator_coop == network::mojom::CrossOriginOpenerPolicyValue::kUnsafeNone)
    return true;
  return initiator_origin.IsSameOriginWith(destination_origin);
}
```

During `CrossOriginOpenerPolicyStatus::EnforceCOOP`, Chromium tracks:
1. `current_coop_`: The active COOP of the previous document or redirect hop.
2. `current_origin_`: The `url::Origin` of the previous document or redirect hop.
3. `require_browsing_instance_swap_`: A monotonic boolean accumulator. Once any hop in a redirect chain triggers a COOP mismatch (`!MatchCOOP(...)`), `require_browsing_instance_swap_` latches to `true` for the remainder of the navigation lifecycle, preventing an attacker from laundering an opener reference through an intermediate redirect.

### 2.3 Critical Security Invariants
1. **Opaque Origin Non-Equivalence**: In `url::Origin::IsSameOriginWith`, two opaque origins (e.g., `sandbox` iframes or `data:` URLs) are only same-origin if they share the exact same internal nonce (`base::UnguessableToken`). Distinct opaque origins always fail the `SameOrigin` check, forcing a `kSwap` under `kSameOrigin`.
2. **Irreversibility across Redirects**: If $A \to B \to C$ occurs where $A$ and $C$ are same-origin with `COOP: same-origin`, but $B$ is cross-origin, $A \to B$ triggers a swap and $B \to C$ triggers another swap. $C$ must *not* be placed back into $A$'s `BrowsingInstance`.
3. **Core Target Equivalence**: When evaluating a target document with `COOP: same-origin` (`coop_same_origin = true`) against an opener or baseline document of equivalent policy capability, the decision to sever the `BrowsingInstance` (`coop_swap`) is strictly isomorphic to `coop_same_origin && !same_origin_opener`.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of the Chromium COOP Browsing Context Group Switch semantics (`BlinkCOOPBrowsingContextGroupSwitchSemantics.v`). It models the core boolean equivalence property alongside the full multi-valued WHATWG/Chromium state machine, opaque origin semantics, and redirect chain monotonicity.

```coq
(** * BlinkCOOPBrowsingContextGroupSwitchSemantics.v
    Formal Verification of Chromium's Cross-Origin-Opener-Policy (COOP)
    Browsing Context Group Switch Engine.
    Target: content/browser/renderer_host/cross_origin_opener_policy_status.cc
    Specification: WHATWG HTML Standard §7.4
*)

Require Import Coq.Bool.Bool.
Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Micromega.Lia.
Import ListNotations.

Open Scope bool_scope.
Open Scope Z_scope.

(** ========================================================================= *)
(** ** 1. Core Mathematical Property Model (Abstract Projection)              *)
(** ========================================================================= *)

(** The foundational security boundary invariant for a document asserting
    COOP: same-origin against an existing opener context. *)
Definition compute_coop_swap_core (coop_same_origin : bool) (same_origin_opener : bool) : bool :=
  coop_same_origin && negb same_origin_opener.

(** Specification predicate for valid isolation under the core projection. *)
Definition valid_core_isolation (coop_swap coop_same_origin same_origin_opener : bool) : Prop :=
  coop_swap = (coop_same_origin && negb same_origin_opener).

(** ========================================================================= *)
(** ** 2. Detailed Chromium / WHATWG Domain Types                             *)
(** ========================================================================= *)

(** Representation of network::mojom::CrossOriginOpenerPolicyValue *)
Inductive COOPValue : Type :=
  | kUnsafeNone            (* "unsafe-none" *)
  | kSameOriginAllowPopups (* "same-origin-allow-popups" *)
  | kSameOrigin            (* "same-origin" *)
  | kSameOriginPlusCOEP.   (* "same-origin" + COEP compatible *)

(** Decidable equality for COOPValue *)
Definition coop_value_eqb (v1 v2 : COOPValue) : bool :=
  match v1, v2 with
  | kUnsafeNone, kUnsafeNone => true
  | kSameOriginAllowPopups, kSameOriginAllowPopups => true
  | kSameOrigin, kSameOrigin => true
  | kSameOriginPlusCOEP, kSameOriginPlusCOEP => true
  | _, _ => false
  end.

Lemma coop_value_eqb_eq : forall v1 v2,
  coop_value_eqb v1 v2 = true <-> v1 = v2.
Proof.
  intros v1 v2; destruct v1, v2; simpl; split; intro H; try reflexivity; discriminate.
Qed.

Lemma coop_value_eqb_refl : forall v, coop_value_eqb v v = true.
Proof.
  intro v; destruct v; reflexivity.
Qed.

(** Representation of url::Origin (Scheme, Host, Port tuple vs Opaque Nonce) *)
Inductive Origin : Type :=
  | TupleOrigin (scheme : Z) (host : Z) (port : Z)
  | OpaqueOrigin (nonce : Z).

(** Decidable same-origin comparison matching url::Origin::IsSameOriginWith *)
Definition same_origin_b (o1 o2 : Origin) : bool :=
  match o1, o2 with
  | TupleOrigin s1 h1 p1, TupleOrigin s2 h2 p2 =>
      (s1 =? s2) && (h1 =? h2) && (p1 =? p2)
  | OpaqueOrigin n1, OpaqueOrigin n2 =>
      n1 =? n2
  | _, _ => false
  end.

Lemma same_origin_b_refl : forall o, same_origin_b o o = true.
Proof.
  intro o; destruct o as [s h p | n]; simpl.
  - rewrite !Z.eqb_refl. reflexivity.
  - rewrite Z.eqb_refl. reflexivity.
Qed.

Lemma same_origin_b_sym : forall o1 o2, same_origin_b o1 o2 = same_origin_b o2 o1.
Proof.
  intros [s1 h1 p1 | n1] [s2 h2 p2 | n2]; simpl; try reflexivity.
  - rewrite (Z.eqb_sym s1 s2), (Z.eqb_sym h1 h2), (Z.eqb_sym p1 p2). reflexivity.
  - rewrite (Z.eqb_sym n1 n2). reflexivity.
Qed.

Lemma same_origin_b_eq : forall o1 o2, same_origin_b o1 o2 = true <-> o1 = o2.
Proof.
  intros [s1 h1 p1 | n1] [s2 h2 p2 | n2]; simpl; split; intro H.
  - apply andb_prop in H as [H1 Hp].
    apply andb_prop in H1 as [Hs Hh].
    apply Z.eqb_eq in Hs. apply Z.eqb_eq in Hh. apply Z.eqb_eq in Hp.
    subst. reflexivity.
  - inversion H; subst. rewrite !Z.eqb_refl. reflexivity.
  - discriminate.
  - discriminate.
  - discriminate.
  - discriminate.
  - apply Z.eqb_eq in H. subst. reflexivity.
  - inversion H; subst. apply Z.eqb_refl.
Qed.

(** Representation of content::CoopSwapResult *)
Inductive CoopSwapResult : Type :=
  | kNoSwap
  | kSwapRelated
  | kSwap.

Definition is_swap (r : CoopSwapResult) : bool :=
  match r with
  | kNoSwap => false
  | kSwapRelated => true
  | kSwap => true
  end.

(** ========================================================================= *)
(** ** 3. Chromium COOP Matching & Swap Decision Engine                       *)
(** ========================================================================= *)

(** Models MatchCOOP in cross_origin_opener_policy_status.cc *)
Definition match