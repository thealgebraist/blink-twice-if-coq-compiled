# Formal Verification Report: Web Background Sync Registration Tag Uniqueness Within Scope

**Agent:** 650 (Web Push, Notifications, Badging & Background Sync)  
**Chromium Source Target:** `third_party/blink/renderer/modules/background_sync/sync_manager.cc`  
**Specification Target:** Web Background Sync §5.1 `register(tag)` uniqueness within registration  
**Formal Theory Target:** `BlinkBackgroundSyncRegistrationTagUniquenessSemantics.v`  
**Mathematical Property:** $\text{register\_sync}(\text{tag}, S) = S \cup \{\text{tag}\}$; idempotent set union.

---

## 1. Normative W3C Background Sync Specification Requirements

The Web Background Sync specification (WICG / W3C Draft Community Group Report) defines an API that enables web applications to synchronize data in the background via Service Workers when network connectivity is established.

### §5.1 The `SyncManager` Interface (`register(tag)` method)
The `SyncManager` interface is exposed on `ServiceWorkerRegistration.sync` and provides the primary mechanism for scheduling background synchronization tasks:

```webidl
[Exposed=(Window,Worker)]
interface SyncManager {
  Promise<undefined> register(DOMString tag);
  Promise<sequence<DOMString>> getTags();
};
```

#### Normative Algorithm for `register(tag)`:
When the `register(tag)` method is invoked on a `SyncManager` instance associated with a *service worker registration*, the user agent MUST execute the following steps:

1. Let $p$ be a new Promise.
2. Let *serviceWorkerRegistration* be the `SyncManager`'s associated service worker registration.
3. Run the following steps in parallel:
   a. If *serviceWorkerRegistration*'s active worker is `null`, reject $p$ with an `InvalidStateError` `DOMException` and abort these steps.
   b. If the user has disabled background sync or permission is denied, reject $p$ with a `NotAllowedError` `DOMException` and abort these steps.
   c. Check if the document or worker context is allowed to schedule background sync.
   d. Let *currentRegistrations* be the record of sync registrations associated with *serviceWorkerRegistration* (scoped by its Service Worker registration scope URL).
   e. **Uniqueness & Coalescing Requirement:** If there is an existing sync registration $r \in \text{currentRegistrations}$ whose tag equals `tag`:
      - If $r$'s registration state is ` firing `, set $r$'s registration state to `reregisteredWhileFiring`.
      - Wait for the registration to be stored and resolve $p$ with `undefined` (do **not** create a duplicate entry with the same `tag` in *currentRegistrations*).
   f. Otherwise (no existing registration in *currentRegistrations* matches `tag`):
      - Create a new sync registration $r_{\text{new}}$ with tag set to `tag` and state set to `pending`.
      - Add $r_{\text{new}}$ to *currentRegistrations*.
      - Resolve $p$ with `undefined`.

#### §5.1 `getTags()` Normative Invariant:
When `getTags()` is invoked, it resolves with a `sequence<DOMString>` containing the `tag` values of all currently registered sync registrations associated with *serviceWorkerRegistration*. Because `register(tag)` coalesces registrations by `tag` within a single Service Worker registration scope, the returned sequence represents a mathematical **set** (no duplicate tags exist for a given scope).

---

## 2. Blink Implementation Details & Invariants

In Chromium, the renderer-side entry point for Web Background Sync is implemented in `third_party/blink/renderer/modules/background_sync/sync_manager.cc`, which communicates over Mojo with the browser-side `BackgroundSyncManager` (`content/browser/background_sync/background_sync_manager.cc`).

### 2.1 Renderer Implementation (`sync_manager.cc`)

In `blink::SyncManager`:
- Every `SyncManager` instance holds a `Member<ServiceWorkerRegistration> registration_`, which binds all operations to a specific Service Worker registration ID (`registration_->RegistrationId()`) and scope.
- `SyncManager::registerFunction(ScriptState* script_state, const String& tag, ExceptionState& exception_state)`:
  1. Verifies that `registration_->active()` is non-null (unless relaxed by specific renderer states validated by browser).
  2. Allocates a `mojom::blink::SyncRegistrationOptions` struct with `options->tag = tag`.
  3. Invokes `GetBackgroundSyncServiceRemote()->Register(std::move(options), registration_->RegistrationId(), WTF::BindOnce(&SyncManager::RegisterCallback, ...))`.
- `SyncManager::getTags(ScriptState* script_state)`:
  1. Invokes `GetBackgroundSyncServiceRemote()->GetRegistrations(registration_->RegistrationId(), WTF::BindOnce(&SyncManager::GetRegistrationsCallback, ...))`.
  2. In `SyncManager::GetRegistrationsCallback`, iterates through the returned `WTF::Vector<mojom::blink::SyncRegistrationOptionsPtr>` and extracts each `registration->tag` into a `Vector<String>` used to resolve the JavaScript Promise.

### 2.2 Browser-Renderer Boundary and Storage Invariants

The uniqueness invariant is enforced across the Mojo boundary by the coupling of `(service_worker_registration_id, tag)` as the composite primary key for One-Shot Background Sync registrations:
1. **Scope Isolation Invariant:** Two different `ServiceWorkerRegistration` instances (having distinct `int64_t registration_id`s corresponding to distinct scope URLs) maintain disjoint registration sets. Registering `"sync-messages"` under Scope A does not collide with `"sync-messages"` under Scope B.
2. **Tag Set Idempotence Invariant:** Within a single `registration_id`, calling `Register(options{tag}, registration_id)` when `tag` is already present in the registration table for `registration_id` overwrites/coalesces the existing registration entry rather than appending a second entry with the same `tag`.
3. **No-Duplicate Projection Invariant:** `GetRegistrations(registration_id)` returns a vector of `SyncRegistrationOptionsPtr` whose `.tag` fields are pairwise distinct (`NoDup`).

---

## 3. Formal Specification in Rocq / Coq

We model Service Worker registration scopes (`ScopeId`), sync tags (`Tag`), the registration state machine (`SyncState`), and the canonical tag set semantics in Rocq/Coq. We prove both the abstract set algebra (idempotence, commutativity, monotonicity, scope isolation) and the concrete list-based implementation invariants (`NoDup` preservation and `getTags` equivalence).

### 3.1 Formal Theory: `BlinkBackgroundSyncRegistrationTagUniquenessSemantics.v`

```coq
(** * BlinkBackgroundSyncRegistrationTagUniquenessSemantics.v
    Formal Verification of Web Background Sync §5.1 register(tag) Uniqueness
    Target: third_party/blink/renderer/modules/background_sync/sync_manager.cc
    Agent: 650 *)

From Coq Require Import Bool.Bool.
From Coq Require Import Arith.PeanoNat.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lists.List.
From Coq Require Import micromega.Lia.
Import ListNotations.

Open Scope nat_scope.

(** ** 1. Basic Domains & Identifiers *)

(** Service Worker Registration IDs (representing distinct scopes) and Tags
    are modeled as natural numbers with decidable equality. *)
Definition ScopeId := nat.
Definition Tag := nat.

(** Background Sync §5.1 Registration States *)
Inductive SyncState : Type :=
  | Pending : SyncState
  | Firing : SyncState
  | ReregisteredWhileFiring : SyncState.

Scheme Equality for SyncState.

(** A single sync registration record stored for a given scope. *)
Record SyncRegistration : Type := mkSyncReg {
  reg_tag : Tag;
  reg_state : SyncState
}.

(** ** 2. Abstract Set Model Within a Single Scope *)

(** A canonical TagSet is a list of Tags maintained without duplicates. *)
Definition TagSet := list Tag.

(** Membership predicate in boolean and propositional forms *)
Fixpoint mem_tag (t : Tag) (s : TagSet) : bool :=
  match s with
  | [] => false
  | x :: xs => if Nat.eqb t x then true else mem_tag t xs
  end.

(** Core Mathematical Operation: register_sync(tag, set) = set U {tag} *)
Fixpoint register_sync (t : Tag) (s : TagSet) : TagSet :=
  match s with
  | [] => [t]
  | x :: xs =>
      if Nat.eqb t x then
        x :: xs (* Tag already registered: coalesce/idempotent *)
      else
        x :: register_sync t xs
  end.

(** Extensional set equivalence over TagSets *)
Definition tag_set_eq (s1 s2 : TagSet) : Prop :=
  forall t : Tag, In t s1 <-> In t s2.

Infix "===" := tag_set_eq (at level 70, no associativity).

(** ** 3. Concrete Registration Store With State Transitions & Scopes *)

(** Transition function per Web Background Sync §5.1 step 3.e:
    If existing registration is Firing, transition to ReregisteredWhileFiring;
    otherwise keep Pending (or ReregisteredWhileFiring). *)
Definition coalesce_state (st : SyncState) : SyncState :=
  match st with
  | Pending => Pending
  | Firing => ReregisteredWhileFiring
  | ReregisteredWhileFiring => ReregisteredWhileFiring
  end.

(** Concrete list of SyncRegistration records for a single ServiceWorkerRegistration *)
Definition ScopeRegList := list SyncRegistration.

Fixpoint register_in_scope (t : Tag) (regs : ScopeRegList) : ScopeRegList :=
  match regs with
  | [] => [mkSyncReg t Pending]
  | r :: rs =>
      if Nat.eqb t (reg_tag r) then
        mkSyncReg (reg_tag r) (coalesce_state (reg_state r)) :: rs
      else
        r :: register_in_scope t rs
  end.

(** Extract tags as performed by SyncManager::GetRegistrationsCallback *)
Definition get_tags (regs : ScopeRegList) : list Tag :=
  map reg_tag regs.

(** Multi-scope SyncManager store mapping ScopeId -> ScopeRegList *)
Definition SyncManagerStore := ScopeId -> ScopeRegList.

Definition empty_store : SyncManagerStore :=
  fun _ => [].

Definition sync_manager_register
  (scope : ScopeId) (t : Tag) (store : SyncManagerStore) : SyncManagerStore :=
  fun s =>
    if Nat.eqb s scope then
      register_in_scope t (store scope)
    else
      store s.

Definition sync_manager_get_tags
  (scope : ScopeId) (store : SyncManagerStore) : list Tag :=
  get_tags (store scope).
```

---

## 4. Concrete Theorems and Complete Rocq / Coq Proofs

Below is the complete, self-contained suite of theorems and proofs verifying the set union semantics, idempotence, duplicate-freedom (`NoDup`), state coalescing correctness, and cross-scope isolation.

```coq
(** ** 4. Lemmas & Theorems *)

(** *** 4.1 Equivalence Equivalence Relation Properties *)

Lemma tag_set_eq_refl : forall s : TagSet, s === s.
Proof.
  intros s t. reflexivity.
Qed.

Lemma tag_set_eq_sym : forall s1 s2 : TagSet, s1 === s2 -> s2 === s1.
Proof.
  intros s1 s2 H t. symmetry. apply H.
Qed.

Lemma tag_set_eq_trans : forall s1 s2 s3 : TagSet,
  s1 === s2 -> s2 === s3 -> s1 === s3.
Proof.
  intros s1 s2 s3 H12 H23 t.
  transitivity (In t s2); [apply H12 | apply H23].
Qed.

(** *** 4.2 Exact Set Union Characterization: register_sync(tag, s) = s U {tag} *)

Theorem register_sync_spec : forall (t x : Tag) (s : TagSet),
  In x (register_sync t s) <-> (In x s \/ x = t).
Proof.
  intros t x s.
  induction s as [| y ys IH]; simpl.
  - split; intros H.
    + destruct H as [H | []]. right. symmetry. exact H.
    + destruct H as [[] | H]. left. symmetry. exact H.
  - destruct (Nat.eqb t y) eqn:Heq.
    + apply Nat.eqb_eq in Heq. subst y.
      simpl. split; intros H.
      * destruct H as [H | H].
        -- left. left. exact H.
        -- left. right. exact H.
      * destruct H as [[H | H] | H].
        -- left. exact H.
        -- right. exact H.
        -- left. symmetry. exact H.
    + apply Nat.eqb_neq in Heq.
      simpl. rewrite IH.
      split; intros H.
      * destruct H as [H | [H | H]].
        -- left. left. exact H.
        -- left. right. exact H.
        -- right. exact H.
      * destruct H as [[H | H] | H].
        -- left. exact H.
        -- right. left. exact H.
        -- right. right. exact H.
Qed.

(** Reflection between mem_tag and In *)
Lemma mem_tag_In_iff : forall (t : Tag) (s : TagSet),
  mem_tag t s = true <-> In t s.
Proof.
  intros t s.
  induction s as [| x xs IH]; simpl.
  - split; intros H; [discriminate H | contradiction].
  - destruct (Nat.eqb t x) eqn:Heq.
    + apply Nat.eqb_eq in Heq. subst x.
      split; intros _.
      * left. reflexivity.
      * reflexivity.
    + apply Nat.eqb_neq in Heq.
      rewrite IH. split; intros H.
      * right. exact H.
      * destruct H as [H | H].
        -- symmetry in H. contradiction.
        -- exact H.
Qed.

(** *** 4.3 Structural & Algebraic Idempotence of register_sync *)

(** Theorem: If tag t is already in s, register_sync returns s literally unchanged. *)
Theorem register_sync_already_in : forall (t : Tag) (s : TagSet),
  In t s -> register_sync t s = s.
Proof.
  intros t s HIn.
  induction s as [| x xs IH]; simpl in *.
  - contradiction.
  - destruct (Nat.eqb t x) eqn:Heq.
    + reflexivity.
    + apply Nat.eqb_neq in Heq.
      destruct HIn as [HIn | HIn].
      * symmetry in HIn. contradiction.
      *