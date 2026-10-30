# Formal Verification of Chromium Blink ResourceLoadPriority Total Ordering

**Target File:** `third_party/blink/renderer/platform/loader/fetch/resource_load_priority.h`  
**Formal Theory Module:** `BlinkResourceLoadPriorityOrderSemantics.v`  
**Specification Domain:** Blink Resource Loading §2 / WHATWG Fetch / IETF RFC 9218  

---

## 1. Normative Specification Requirements

Resource prioritization in web browser networking engines sits at the intersection of the WHATWG Fetch Standard, the W3C Priority Hints specification, and the IETF HTTP Extensible Prioritization Scheme (RFC 9218). While user-facing specifications define high-level hints and wire-level protocols define transport frames, the browser engine must bridge these layers using an internal, strictly ordered priority lattice.

### 1.1 WHATWG Fetch Standard
In the WHATWG Fetch Standard (§ 2.2.5 *Requests*), every request has an associated **priority** (defaulting to `"auto"`, or explicitly set to `"high"` or `"low"` via the `fetchpriority` attribute or `RequestInit` dictionary) and an **internal priority** (null or an implementation-defined object). 
* **Normative Requirement (Fetch § 4.4 *HTTP-network-or-cache fetch*):** The user agent must use the request's destination, initiator, and explicit priority hint to compute an internal priority value before handing the request off to the network or HTTP cache layer.
* **Monotonicity:** Promotion of a resource's priority (e.g., when an initially off-screen `<img>` enters the viewport or when a preloaded resource is requested by a synchronous parser blocking script) requires the internal representation to support a decidable total ordering so that priority upgrades (`new_priority > current_priority`) are strictly monotonic.

### 1.2 IETF RFC 9218 (Extensible Prioritization Scheme for HTTP)
RFC 9218 defines HTTP/2 and HTTP/3 priority parameters using **Urgency** ($u \in \{0, 1, \dots, 7\}$, where $0$ is highest urgency and $7$ is lowest) and **Incremental** ($i \in \{\text{true}, \text{false}\}$).
* **Normative Mapping:** Chromium's network service (`net::RequestPriority`) and Blink's loader (`blink::ResourceLoadPriority`) must maintain an order-isomorphic mapping to RFC 9218 urgency levels. Specifically, a strict total order in Blink ($P_1 < P_2$) must guarantee that when serialized to the wire via `net::ConvertRequestPriorityToHttpPriority`, $P_2$ maps to an urgency value less than or equal to $P_1$'s urgency value ($u(P_2) \le u(P_1)$).

### 1.3 Blink Resource Loading Architecture (§2)
Within Chromium's Blink rendering engine, `ResourceLoadPriority` serves as the canonical domain for scheduling resource requests inside `ResourceLoadScheduler`, throttling low-priority requests during critical rendering phases, and deduplicating in-flight requests in the `MemoryCache`. The specification of `ResourceLoadPriority` mandates:
1. A finite, bounded discrete lattice of 5 concrete priority levels (`kVeryLow` to `kVeryHigh`) plus an uninitialized sentinel state (`kUnresolved`).
2. Strict total ordering over resolved priorities: $\text{VeryLow}(0) < \text{Low}(1) < \text{Medium}(2) < \text{High}(3) < \text{VeryHigh}(4)$.
3. Exact boundary invariants (`kLowest = kVeryLow`, `kHighest = kVeryHigh`) utilized by priority clamping and histogram bucket sizing.

---

## 2. Blink Implementation Details and Invariants

In Chromium's source tree (`third_party/blink/renderer/platform/loader/fetch/resource_load_priority.h`), the priority domain is defined as a scoped C++ enumeration:

```cpp
namespace blink {

enum class ResourceLoadPriority : int {
  kUnresolved = -1,
  kVeryLow = 0,
  kLow = 1,
  kMedium = 2,
  kHigh = 3,
  kVeryHigh = 4,
  kLowest = kVeryLow,
  kHighest = kVeryHigh,
  kMaxValue = kHighest,
};

}  // namespace blink
```

### 2.1 Core Engine Invariants
1. **Integer Rank Representation:** The underlying type is explicitly `: int`. The enumerators from `kVeryLow` to `kVeryHigh` occupy contiguous non-negative integers $[0, 4]$. `kUnresolved` occupies $-1$ to ensure that any resolved priority is strictly greater than `kUnresolved` under standard C++ signed integer comparison (`operator<`).
2. **MemoryCache Priority Promotion (`ResourceFetcher` & `MemoryCache`):** When a resource request hits an existing, in-flight `Resource` in Blink's `MemoryCache` (`ResourceFetcher::RevalidateResource` or `UpdateMemoryCache`), Blink invokes `Resource::DidChangePriority(new_priority, intra_priority_value)`. To prevent priority inversion where a low-priority prefetch downgrades a high-priority render-blocking fetch, the update is guarded by the lattice join operation ($\sqcup$):
   $$\text{effective\_priority} = \max(\text{current\_priority}, \text{new\_priority})$$
3. **Priority Clamping and Boosts (`ResourceFetcher::ComputeLoadPriority`):** Heuristics such as image visibility boosting, late-body script demotion, and `fetchpriority="high"` apply signed integer deltas to the base priority of a `ResourceType`. Because C++ arithmetic on cast enums can overflow the $[0, 4]$ bounds, clamping to $[\text{kLowest}, \text{kHighest}]$ must be idempotent and order-preserving.
4. **Mojo IPC and `net::RequestPriority` Bijection:** In `third_party/blink/public/platform/web_url_request_util.cc`, `ResourceLoadPriority` is translated across the Mojo boundary to `net::RequestPriority` (`THROTTLED = 0`, `IDLE = 1`, `LOWEST = 2`, `LOW = 3`, `MEDIUM = 4`, `HIGHEST = 5`, where `THROTTLED` is reserved for internal net-layer throttling and `IDLE` maps to `kVeryLow`). The strict total order of `ResourceLoadPriority` is relied upon by `ResourceLoadScheduler` to maintain a priority queue (`base::IntrusiveHeap`) of pending requests.

---

## 3. Formal Specification in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkResourceLoadPriorityOrderSemantics.v`. It models the resolved priority lattice, the extended enum (including `kUnresolved`), rank conversion, comparison predicates, lattice operations (join/meet for cache coalescing), priority clamping for heuristic adjustments, and the translation to `net::RequestPriority` and RFC 9218 Urgency.

```coq
(** * BlinkResourceLoadPriorityOrderSemantics.v
    Formal verification of Chromium Blink's ResourceLoadPriority total ordering,
    lattice algebra, clamping invariants, and network layer order-isomorphism.
    Source: third_party/blink/renderer/platform/loader/fetch/resource_load_priority.h *)

From Coq Require Import Bool.Bool.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micromega.Lia.
From Coq Require Import Lists.List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Data Types and Rank Encoding *)

(** Resolved priorities represent valid scheduling states in ResourceLoadScheduler.
    Mathematical Property: VeryLow(0) < Low(1) < Medium(2) < High(3) < VeryHigh(4). *)
Inductive ResourceLoadPriority : Type :=
  | kVeryLow  : ResourceLoadPriority
  | kLow      : ResourceLoadPriority
  | kMedium   : ResourceLoadPriority
  | kHigh     : ResourceLoadPriority
  | kVeryHigh : ResourceLoadPriority.

(** Raw C++ enum representation including the kUnresolved (-1) sentinel. *)
Inductive RawResourceLoadPriority : Type :=
  | RawUnresolved : RawResourceLoadPriority
  | RawResolved   : ResourceLoadPriority -> RawResourceLoadPriority.

(** C++ enumeration aliases defined in resource_load_priority.h *)
Definition kLowest   : ResourceLoadPriority := kVeryLow.
Definition kHighest  : ResourceLoadPriority := kVeryHigh.
Definition kMaxValue : ResourceLoadPriority := kHighest.

(** Exact integer rank mapping for resolved priorities: [0, 4]. *)
Definition priority_rank (p : ResourceLoadPriority) : Z :=
  match p with
  | kVeryLow  => 0
  | kLow      => 1
  | kMedium   => 2
  | kHigh     => 3
  | kVeryHigh => 4
  end.

(** Exact integer rank mapping for raw C++ enum values: [-1, 4]. *)
Definition raw_priority_rank (rp : RawResourceLoadPriority) : Z :=
  match rp with
  | RawUnresolved  => -1
  | RawResolved p  => priority_rank p
  end.

(** Inverse mapping from integer rank with clamping to [kLowest, kHighest].
    Models C++ static_cast<ResourceLoadPriority>( base::clamp(val, 0, 4) ). *)
Definition rank_to_priority_clamped (z : Z) : ResourceLoadPriority :=
  if z <=? 0 then kVeryLow
  else if z =? 1 then kLow
  else if z =? 2 then kMedium
  else if z =? 3 then kHigh
  else kVeryHigh.

(** Exact partial inverse for valid ranks in [-1, 4]. *)
Definition z_to_raw_priority (z : Z) : option RawResourceLoadPriority :=
  if z =? -1 then Some RawUnresolved
  else if z =? 0 then Some (RawResolved kVeryLow)
  else if z =? 1 then Some (RawResolved kLow)
  else if z =? 2 then Some (RawResolved kMedium)
  else if z =? 3 then Some (RawResolved kHigh)
  else if z =? 4 then Some (RawResolved kVeryHigh)
  else None.

(** ** 2. Ordering Predicates and Decidable Comparisons *)

(** Strict inequality (p1 < p2) *)
Definition priority_lt (p1 p2 : ResourceLoadPriority) : Prop :=
  priority_rank p1 < priority_rank p2.

(** Non-strict inequality (p1 <= p2) *)
Definition priority_le (p1 p2 : ResourceLoadPriority) : Prop :=
  priority_rank p1 <= priority_rank p2.

(** Boolean decidable equality and comparisons *)
Definition priority_eqb (p1 p2 : ResourceLoadPriority) : bool :=
  priority_rank p1 =? priority_rank p2.

Definition priority_ltb (p1 p2 : ResourceLoadPriority) : bool :=
  priority_rank p1 <? priority_rank p2.

Definition priority_leb (p1 p2 : ResourceLoadPriority) : bool :=
  priority_rank p1 <=? priority_rank p2.

(** Lattice Join (max) used by Blink MemoryCache for priority promotion *)
Definition priority_join (p1 p2 : ResourceLoadPriority) : ResourceLoadPriority :=
  if priority_leb p1 p2 then p2 else p1.

(** Lattice Meet (min) used by Blink ResourceLoadScheduler for throttling caps *)
Definition priority_meet (p1 p2 : ResourceLoadPriority) : ResourceLoadPriority :=
  if priority_leb p1 p2 then p1 else p2.

(** Priority adjustment by a signed delta (e.g., visibility or fetchpriority boost) *)
Definition adjust_priority (p : ResourceLoadPriority) (delta : Z) : ResourceLoadPriority :=
  rank_to_priority_clamped (priority_rank p + delta).

(** Resolution of a raw priority with a fallback default (used in ResourceRequest) *)
Definition resolve_priority (rp : RawResourceLoadPriority) (default_p : ResourceLoadPriority)
  : ResourceLoadPriority :=
  match rp with
  | RawUnresolved => default_p
  | RawResolved p => p
  end.

(** ** 3. Network Layer & RFC 9218 Mappings *)

(** Chromium net::RequestPriority (net/base/request_priority.h):
    THROTTLED = 0, IDLE = 1, LOWEST = 2, LOW = 3, MEDIUM = 4, HIGHEST = 5.
    Blink maps kVeryLow..kVeryHigh directly to IDLE(1)..HIGHEST(5). *)
Definition blink_to_net_priority_rank (p : ResourceLoadPriority) : Z :=
  priority_rank p + 1.

(** IETF RFC 9218 HTTP Extensible Prioritization Urgency [0..7].
    In RFC 9218, 0 is highest urgency and 7 is lowest urgency.
    Mapping: VeryHigh -> 1, High -> 2, Medium -> 3, Low -> 4, VeryLow -> 5. *)
Definition blink_to_rfc9218_urgency (p : ResourceLoadPriority) : Z :=
  5 - priority_rank p.
```

---

## 4. Concrete Theorems and Complete Proofs

All proofs below are mechanized using `ZArith`, `Bool`, and `Lia` with zero `Admitted` statements or axioms.

```coq
(** ** 4. Formal Verification of Ordering, Lattice, and Engine Invariants *)

(** Theorem 1: Explicit verification of the specification's fundamental chain:
    VeryLow(0) < Low(1) < Medium(2) < High(3) < VeryHigh(4). *)
Theorem priority_fundamental_chain :
  priority_rank kVeryLow = 0 /\
  priority_rank kLow = 1 /\
  priority_rank kMedium = 2 /\
  priority_rank kHigh = 3 /\
  priority_rank kVeryHigh = 4 /\
  priority_lt kVeryLow kLow /\
  priority_lt kLow kMedium /\
  priority_lt kMedium kHigh /\
  priority_lt kHigh kVeryHigh.
Proof.
  unfold priority_lt, priority_rank.
  repeat split; lia.
Qed.

(** Theorem 2: Tight boundary invariants for kLowest, kHighest, and kMaxValue. *)
Theorem priority_rank_bounds :
  forall p : ResourceLoadPriority,
    priority_rank kLowest <= priority_rank p <= priority_rank kHighest /\
    0 <= priority_rank p <= 4 /\
    priority_rank kHighest = priority_rank kMaxValue.
Proof.
  intros p.
  destruct p; unfold kLowest, kHighest, kMaxValue, priority_rank; lia.
Qed.

(** Theorem 3: Injectivity of priority_rank (Rank uniquely identifies priority). *)
Theorem priority_rank_injective :
  forall p1 p2 : ResourceLoadPriority,
    priority_rank p1 = priority_rank p2 <-> p1 = p2.
Proof.
  intros p1 p2; split; intros H.
  - destruct p1, p2; simpl in H; try reflexivity; discriminate H.
  - subst; reflexivity.
Qed.

(** Theorem 4: Reflection equivalence between boolean comparisons and Prop relations. *)
Theorem priority_eqb_spec :
