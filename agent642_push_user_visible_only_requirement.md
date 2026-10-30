# Formal Verification Report: Push API `userVisibleOnly` Mandatory Boolean Requirement

**Agent Identifier:** Agent 642 (Web Push, Notifications, Badging & Background Sync)  
**Target Module:** `third_party/blink/renderer/modules/push_messaging/push_subscription_options.cc`  
**Formal Theory Target:** `BlinkPushUserVisibleOnlyRequirementSemantics.v`  
**Mathematical Property:** $\text{options\_valid}(\text{opts}) \iff (\text{opts.userVisibleOnly} = \text{true})$

---

## 1. Normative W3C Push API Specification Requirements

In the W3C Push API specification (§6 `PushSubscriptionOptions` Interface and §5.1 `PushManager.subscribe()` method), the `userVisibleOnly` attribute dictates whether the push subscription will only be used for push messages whose effect is made visible to the user (typically via the Notifications API).

### 1.1 WebIDL Definition (§6.1)
```webidl
[Exposed=(Window,Worker), SecureContext]
interface PushSubscriptionOptions {
  readonly attribute boolean userVisibleOnly;
  [SameObject] readonly attribute ArrayBuffer? applicationServerKey;
};

dictionary PushSubscriptionOptionsInit {
  boolean userVisibleOnly = false;
  (BufferSource or DOMString)? applicationServerKey = null;
};
```

### 1.2 Normative Algorithm Steps (§5.1 `subscribe()`)
When `PushManager.subscribe(optional PushSubscriptionOptionsInit options)` is invoked, the user agent executes the following normative validation step:

> **Step 4:** If the `options` argument does not include a non-null value for the `applicationServerKey` member, and the push service requires one, queue a task to reject `promise` with a `NotSupportedError` `DOMException`.  
> **Step 5:** If the `options` argument has a `userVisibleOnly` value set to `false` and the push service requires it to be `true`, queue a task to reject `promise` with a `NotAllowedError` `DOMException` and terminate these steps.

While the WebIDL defaults `userVisibleOnly` to `false` inside `PushSubscriptionOptionsInit`, Chromium's Push Service implementation enforces the condition in Step 5 unconditionally in standard Web Push contexts: silent background push without user-visible effects is prohibited to preserve user privacy and prevent covert background tracking/computation. Note that while Chromium's C++ implementation layer (`PushManager::subscribe` / `PushMessagingClient`) handles the asynchronous rejection with `NotAllowedError` (or `NotSupportedError` during options conversion in older revisions), the structural invariant at the `PushSubscriptionOptions` boundary requires `userVisibleOnly == true` for a valid subscription trajectory.

---

## 2. Blink Implementation Details and Invariants

In Chromium Blink, the conversion from the Blink WebIDL dictionary (`PushSubscriptionOptionsInit`) to the internal Blink representation (`PushSubscriptionOptions`) occurs in `third_party/blink/renderer/modules/push_messaging/push_subscription_options.cc` and is subsequently enforced prior to Mojo IPC transmission in `push_messaging_client.cc` / `push_manager.cc`.

### 2.1 Source Analysis: `push_subscription_options.cc`
```cpp
// third_party/blink/renderer/modules/push_messaging/push_subscription_options.cc

PushSubscriptionOptions* PushSubscriptionOptions::FromOptionsInit(
    const PushSubscriptionOptionsInit* options_init,
    ExceptionState& exception_state) {
  Vector<uint8_t> application_server_key;
  if (options_init->hasApplicationServerKey() &&
      options_init->applicationServerKey()) {
    application_server_key = BufferSourceToVector(
        options_init->applicationServerKey(), exception_state);
    if (exception_state.HadException())
      return nullptr;
  }

  return MakeGarbageCollected<PushSubscriptionOptions>(
      options_init->userVisibleOnly(), application_server_key);
}
```

### 2.2 Downstream Enforcement Invariant
In `PushSubscriptionOptions::FromOptionsInit`, the boolean `options_init->userVisibleOnly()` is extracted directly (defaulting to `false` per `push_subscription_options_init.idl` if omitted by the caller). When `PushManager::subscribe()` processes the constructed `PushSubscriptionOptions`, or within the browser/renderer validation boundary:

1. **Default Omission State:** If a developer calls `pushManager.subscribe({})` or `pushManager.subscribe()`, Blink's generated bindings initialize `options_init->userVisibleOnly()` to `false`.
2. **Explicit False State:** If a developer calls `pushManager.subscribe({ userVisibleOnly: false })`, `options_init->userVisibleOnly()` evaluates to `false`.
3. **Explicit True State:** Only when `pushManager.subscribe({ userVisibleOnly: true })` is passed does `options->userVisibleOnly()` evaluate to `true`.
4. **Validation Gate:** Chromium enforces that any subscription request reaching the active subscription registration phase satisfies `options->userVisibleOnly() == true`. If `false`, the request fails without registering a background worker push route.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the complete, self-contained formalization of `BlinkPushUserVisibleOnlyRequirementSemantics.v`. It models the WebIDL dictionary initialization defaults, the `FromOptionsInit` conversion in `push_subscription_options.cc`, and the mandatory `userVisibleOnly` validation predicate.

```coq
(** * BlinkPushUserVisibleOnlyRequirementSemantics.v
    Formal Verification of Chromium Blink Push API userVisibleOnly Requirement
    Source: third_party/blink/renderer/modules/push_messaging/push_subscription_options.cc
    Specification: W3C Push API §5.1, §6
*)

From Coq Require Import Bool.Bool.
From Coq Require Import Lists.List.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Lia.
Import ListNotations.

Open Scope bool_scope.
Open Scope Z_scope.

(** ** 1. WebIDL & Blink Data Structures *)

(** Representation of DOMException error codes relevant to PushSubscriptionOptions *)
Inductive DOMException : Type :=
  | InvalidAccessError : DOMException
  | NotAllowedError    : DOMException
  | NotSupportedError  : DOMException.

(** WebIDL BufferSource / DOMString representation for applicationServerKey *)
Inductive ApplicationServerKeyInit : Type :=
  | KeyNone   : ApplicationServerKeyInit
  | KeyValid  : list Z -> ApplicationServerKeyInit
  | KeyInvalid: ApplicationServerKeyInit.

(** WebIDL PushSubscriptionOptionsInit dictionary *)
Record PushSubscriptionOptionsInit : Type := mkOptionsInit {
  init_userVisibleOnly      : option bool;
  init_applicationServerKey : ApplicationServerKeyInit
}.

(** Blink C++ PushSubscriptionOptions class (GarbageCollected) *)
Record PushSubscriptionOptions : Type := mkOptions {
  opts_userVisibleOnly      : bool;
  opts_applicationServerKey : list Z
}.

(** Result monad modeling Blink ExceptionState + Return Value *)
Inductive BlinkResult (A : Type) : Type :=
  | BlinkOk  : A -> BlinkResult A
  | BlinkErr : DOMException -> BlinkResult A.

Arguments BlinkOk {A} _.
Arguments BlinkErr {A} _.

(** ** 2. Blink Implementation Semantics (push_subscription_options.cc) *)

(** WebIDL default resolution: boolean userVisibleOnly = false; *)
Definition resolve_user_visible_only (opt_flag : option bool) : bool :=
  match opt_flag with
  | Some b => b
  | None   => false
  end.

(** Constants for applicationServerKey length bounds in Blink *)
Definition MAX_KEY_LENGTH : Z := 255.

(** Models BufferSourceToVector in push_subscription_options.cc *)
Definition buffer_source_to_vector (k : ApplicationServerKeyInit) : BlinkResult (list Z) :=
  match k with
  | KeyNone => BlinkOk []
  | KeyValid bytes =>
      if (Z.of_nat (List.length bytes) <=? MAX_KEY_LENGTH)
      then BlinkOk bytes
      else BlinkErr InvalidAccessError
  | KeyInvalid => BlinkErr InvalidAccessError
  end.

(** Models PushSubscriptionOptions::FromOptionsInit *)
Definition from_options_init (init : PushSubscriptionOptionsInit)
  : BlinkResult PushSubscriptionOptions :=
  match buffer_source_to_vector (init_applicationServerKey init) with
  | BlinkErr e => BlinkErr e
  | BlinkOk key_vec =>
      BlinkOk (mkOptions (resolve_user_visible_only (init_userVisibleOnly init)) key_vec)
  end.

(** ** 3. Mathematical Property & Chromium Validation Semantics *)

(** Executable boolean validation check *)
Definition options_valid_b (opts : PushSubscriptionOptions) : bool :=
  opts_userVisibleOnly opts.

(** Propositional validity predicate: options_valid(opts) = (opts.userVisibleOnly == true) *)
Definition options_valid (opts : PushSubscriptionOptions) : Prop :=
  opts_userVisibleOnly opts = true.

(** Chromium PushManager::subscribe validation gate *)
Definition validate_chromium_push_options (opts : PushSubscriptionOptions)
  : BlinkResult PushSubscriptionOptions :=
  if options_valid_b opts then
    BlinkOk opts
  else
    BlinkErr NotAllowedError.

(** Full pipeline from WebIDL dictionary to validated Blink options *)
Definition subscribe_options_pipeline (init : PushSubscriptionOptionsInit)
  : BlinkResult PushSubscriptionOptions :=
  match from_options_init init with
  | BlinkErr e => BlinkErr e
  | BlinkOk opts => validate_chromium_push_options opts
  end.

(** Background Processing Invariant:
    A push subscription state is authorized for background worker activation
    if and only if it was produced by a valid options configuration where
    every incoming push message must trigger a user-visible notification. *)
Record ActivePushSubscription : Type := mkSubscription {
  sub_options : PushSubscriptionOptions;
  sub_invariant : options_valid sub_options
}.
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

The following theorems establish the exact correspondence between the boolean checker and propositional specification, the rejection of default/omitted and explicit `false` configurations, and the preservation of background processing invariants.

```coq
(** ** 4. Formal Verification Theorems *)

(** Theorem 1: Decidability and equivalence of options_valid and options_valid_b *)
Theorem options_valid_iff_true :
  forall (opts : PushSubscriptionOptions),
    options_valid opts <-> options_valid_b opts = true.
Proof.
  intros opts.
  unfold options_valid, options_valid_b.
  split; intros H; exact H.
Qed.

(** Theorem 2: Validation gate succeeds if and only if userVisibleOnly is true *)
Theorem validate_chromium_push_options_correct :
  forall (opts : PushSubscriptionOptions),
    validate_chromium_push_options opts = BlinkOk opts <->
    options_valid opts.
Proof.
  intros [uvo key].
  unfold validate_chromium_push_options, options_valid, options_valid_b.
  simpl.
  destruct uvo.
  - split; intros _; reflexivity.
  - split; intros H.
    + discriminate H.
    + discriminate H.
Qed.

(** Theorem 3: Validation gate rejects with NotAllowedError iff userVisibleOnly is false *)
Theorem validate_chromium_push_options_rejects_false :
  forall (opts : PushSubscriptionOptions),
    validate_chromium_push_options opts = BlinkErr NotAllowedError <->
    opts_userVisibleOnly opts = false.
Proof.
  intros [uvo key].
  unfold validate_chromium_push_options, options_valid_b.
  simpl.
  destruct uvo.
  - split; intros H; discriminate H.
  - split; intros _; reflexivity.
Qed.

(** Theorem 4: Default WebIDL initialization (userVisibleOnly omitted) is always rejected *)
Theorem omitted_user_visible_only_never_succeeds :
  forall (k : ApplicationServerKeyInit) (opts : PushSubscriptionOptions),
    subscribe_options_pipeline (mkOptionsInit None k) <> BlinkOk opts.
Proof.
  intros k opts Hpipe.
  unfold subscribe_options_pipeline, from_options_init in Hpipe.
  simpl in Hpipe.
  destruct (buffer_source_to_vector k) as [vec | err].
  - unfold validate_chromium_push_options, options_valid_b in Hpipe.
    simpl in Hpipe.
    discriminate Hpipe.
  - discriminate Hpipe.
Qed.

(** Theorem 5: Explicit false userVisibleOnly is always rejected *)
Theorem explicit_false_user_visible_only_never_succeeds :
  forall (k : ApplicationServerKeyInit) (opts : PushSubscriptionOptions),
    subscribe_options_pipeline (mkOptionsInit (Some false) k) <> BlinkOk opts.
Proof.
  intros k opts Hpipe.
  unfold subscribe_options_pipeline, from_options_init in Hpipe.
  simpl in Hpipe.
  destruct (buffer_source_to_vector k) as [vec | err].
  - unfold validate_chromium_push_options, options_valid_b in Hpipe.
    simpl in Hpipe.
    discriminate Hpipe.
  - discriminate Hpipe.
Qed.

(** Theorem 6: Pipeline soundness - any successful pipeline execution guarantees options_valid
    and enforces non-negative bounded key length *)
Theorem subscribe_pipeline_soundness :
  forall (init : PushSubscriptionOptionsInit) (opts : PushSubscriptionOptions),
    subscribe_options_pipeline init = BlinkOk opts ->
    options_valid opts /\
    init_userVisibleOnly init = Some true /\
    0 <= Z.of_nat (List.length (opts_applicationServerKey opts)) <= MAX_KEY_LENGTH.
Proof.
  intros [uvo_init key_init] [uvo_opts key_opts] Hpipe.
  unfold subscribe_options_pipeline, from_options_init in Hpipe.
  simpl in Hpipe.
  destruct (buffer_source_to_vector key_init) as [vec | err] eqn:Hbuf; [| discriminate Hpipe].
  unfold validate_chromium_push_options, options_valid_b in Hpipe.
  simpl in Hpipe.
  destruct (resolve_user_visible_only uvo_init) eqn:Hres; [| discriminate Hpipe].
  inversion Hpipe; subst uvo_opts key_opts; clear Hpipe.
  repeat split.
  - unfold options_valid. simpl. reflexivity.
  - destruct uvo_init as [b |]; simpl in Hres.
    + subst b. reflexivity.
    + discriminate Hres.
  - Lia.lia.
  - unfold buffer_source_to_vector in Hbuf.
    destruct key_init as [| bytes |].
    + inversion Hbuf; subst vec. simpl. unfold MAX_KEY_LENGTH. Lia.lia.
    + destruct (Z.of_nat (Datatypes.length bytes) <=? MAX_KEY_LENGTH) eqn:Hlen; [| discriminate Hbuf].
      inversion Hbuf; subst vec.
      apply Z.leb_le in