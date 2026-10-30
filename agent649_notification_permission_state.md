# Formal Verification Report: Notifications API Permission State Progression
**Agent:** 649 (Web Push, Notifications, Badging & Background Sync)  
**Target Source:** `third_party/blink/renderer/modules/notifications/notification.cc`  
**Specification:** WHATWG Notifications API §4.3 `NotificationPermission`  
**Formal Theory Target:** `BlinkNotificationPermissionStateSemantics.v`  
**Mathematical Property:** Absorbing / Terminal nature of the `denied` state under programmatic Web API invocation.

---

## 1. Normative Specification Requirements

### 1.1 WHATWG Notifications API (§4.3 Permission Model)
According to the WHATWG Notifications API Living Standard (§4.3 *Permission model* and §5 *API*), the permission state for a given origin is represented by the `NotificationPermission` enumeration:

```webidl
enum NotificationPermission {
  "default",
  "denied",
  "granted"
};
```

The specification mandates the following state semantics during the execution of `Notification.requestPermission(deprecatedCallback)`:

1. **Initial State (`"default"`):** Equivalent to `prompt` in the W3C Permissions API. The user has not yet made an explicit trust decision for the origin, or has reset their decision.
2. **Granted State (`"granted"`):** The origin is authorized to display system notifications and bind push notifications via `ServiceWorkerRegistration.showNotification()`.
3. **Denied State (`"denied"`):** The origin is explicitly forbidden from displaying notifications.
4. **Programmatic Transition Rules (§5.2 `requestPermission()`):**
   - When `Notification.requestPermission()` is invoked, the user agent runs the *permission request algorithm* in parallel.
   - If the current permission state is `"granted"` or `"denied"`, the user agent **must not** prompt the user and **must** resolve the returned Promise immediately with the existing permission state.
   - Specifically, a script cannot programmatically force a transition out of `"denied"` (nor `"granted"`) via `requestPermission()`. Only out-of-band user intervention via browser UI / site settings can reset or alter a `"denied"` state, which lies outside the script-accessible transition system.

### 1.2 Interoperability with W3C Push API, Badging API, and Background Sync
- **W3C Push API (§6.1 `PushManager.subscribe()`):** When subscribing with `userVisibleOnly: true` (mandatory in Blink), the user agent checks the Notifications permission state. If the permission state is `"denied"`, the subscription request rejects immediately with a `NotAllowedError` `DOMException` without displaying a prompt.
- **W3C Badging API (`Navigator.setAppBadge()`):** In Chromium's origin permission broker, application badging shares or queries notification permission state on specific desktop platforms; if notifications are `"denied"`, badge updates are silently suppressed or rejected depending on platform policy.
- **W3C Background Sync API:** Periodic Background Sync and one-shot Background Sync registration execution limits are gated by origin engagement and permission states; an explicit `"denied"` state prevents silent background wake-ups from escalating into user-visible spam.

---

## 2. Blink Implementation Details & Invariants

In Chromium's Blink rendering engine, the WebIDL `Notification` interface is implemented in `third_party/blink/renderer/modules/notifications/notification.cc` and `notification_manager.cc`.

### 2.1 Permission Mapping (`notification.cc` & `notification_manager.cc`)
Blink bridges the Mojo IPC permission service (`mojom::blink::PermissionStatus`) to the DOM string representation (`V8NotificationPermission::Enum`):

```cpp
// third_party/blink/renderer/modules/notifications/notification.cc
V8NotificationPermission::Enum Notification::PermissionToV8Enum(
    mojom::blink::PermissionStatus permission) {
  switch (permission) {
    case mojom::blink::PermissionStatus::GRANTED:
      return V8NotificationPermission::Enum::kGranted;
    case mojom::blink::PermissionStatus::DENIED:
      return V8NotificationPermission::Enum::kDenied;
    case mojom::blink::PermissionStatus::ASK:
      return V8NotificationPermission::Enum::kDefault;
  }
  NOTREACHED();
}
```

### 2.2 `Notification::requestPermission` Implementation Invariants
When `Notification::requestPermission(ScriptState* script_state, V8NotificationPermissionCallback* deprecated_callback)` is called:

1. **Execution Context Validation:** Blink verifies that the `ExecutionContext` is valid and checks for transient user activation (`LocalFrame::HasTransientUserActivation`).
2. **Mojo IPC Dispatch:** `NotificationManager::From(context)->RequestPermission(...)` sends an asynchronous request to the browser process (`PermissionService`).
3. **Browser-Side Enforcement & Renderer Cache:**
   - The renderer queries or caches the `mojom::blink::PermissionStatus`.
   - If the current state is `mojom::blink::PermissionStatus::DENIED` (`kDenied`), the permission service immediately short-circuits and returns `PermissionStatus::DENIED` without invoking a UI prompt.
   - In `Notification:: Notification(...)` constructor and `ServiceWorkerRegistrationNotifications::showNotification()`, Blink synchronously checks `GetPermissionStatus()`:
     ```cpp
     if (NotificationManager::From(context)->GetPermissionStatus(context) !=
         mojom::blink::PermissionStatus::GRANTED) {
       // Rejects promise with TypeError (SW) or fires 'error' event (DOM Notification)
       return;
     }
     ```

### 2.3 Core System Invariant
Within the transition system induced by DOM/ServiceWorker script actions (`RequestPermission`, `ShowNotification`, `PushSubscribe`), **`kDenied` is a strict absorbing (terminal) state**. No sequence of programmatic API requests from an origin can transition its state from `kDenied` to `kDefault` or `kGranted`.

---

## 3. Formal Specification in Rocq / Coq

Below is the self-contained formalization of `BlinkNotificationPermissionStateSemantics.v`. It models the Mojo `PermissionStatus` enum, the WebIDL `NotificationPermission` enum, the bijection between them, the script-accessible transition semantics, and the background execution safety guards.

```coq
(** * BlinkNotificationPermissionStateSemantics.v
    Formal verification of Chromium Blink's Notification Permission State Machine
    Source: third_party/blink/renderer/modules/notifications/notification.cc
    Specification: WHATWG Notifications API §4.3
*)

From Coq Require Import Bool.Bool.
From Coq Require Import Lists.List.
From Coq Require Import ZArith.ZArith.
From Coq Require Import Micega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Data Types and Enumerations *)

(** Mojo IPC PermissionStatus: mojom::blink::PermissionStatus *)
Inductive MojoPermissionStatus : Type :=
  | Mojo_ASK
  | Mojo_GRANTED
  | Mojo_DENIED.

(** WebIDL V8NotificationPermission::Enum (§4.3 NotificationPermission) *)
Inductive NotificationPermission : Type :=
  | Perm_Default
  | Perm_Granted
  | Perm_Denied.

(** User / Browser Prompt Resolution Outcome when in 'default' (ASK) state *)
Inductive PromptOutcome : Type :=
  | User_Dismissed
  | User_Accepted
  | User_Blocked
  | No_User_Activation_Auto_Deny
  | Insecure_Origin_Auto_Deny.

(** Script-accessible Web API actions across Notifications, Push, and Background Sync *)
Inductive ScriptAction : Type :=
  | Act_RequestPermission (outcome : PromptOutcome) (has_user_gesture : bool) (is_secure_context : bool)
  | Act_ConstructNotification
  | Act_ServiceWorkerShowNotification
  | Act_PushSubscribe (user_visible_only : bool)
  | Act_BadgingSet
  | Act_BackgroundSyncRegister.

(** Execution Outcome of a ScriptAction *)
Inductive ActionResult : Type :=
  | Res_PermissionResolved (p : NotificationPermission)
  | Res_NotificationDispatched
  | Res_NotificationBlockedError
  | Res_PushSubscribed
  | Res_PushNotAllowedError
  | Res_BadgeUpdated
  | Res_BadgeSuppressed
  | Res_SyncRegistered
  | Res_SyncDeniedError.

(** ** 2. Blink Mapping Functions (notification.cc) *)

(** Models Notification::PermissionToV8Enum *)
Definition permission_to_v8_enum (m : MojoPermissionStatus) : NotificationPermission :=
  match m with
  | Mojo_ASK => Perm_Default
  | Mojo_GRANTED => Perm_Granted
  | Mojo_DENIED => Perm_Denied
  end.

(** Inverse mapping used internally by PermissionService bridge *)
Definition v8_enum_to_mojo (p : NotificationPermission) : MojoPermissionStatus :=
  match p with
  | Perm_Default => Mojo_ASK
  | Perm_Granted => Mojo_GRANTED
  | Perm_Denied => Mojo_DENIED
  end.

(** Decidable equality for NotificationPermission *)
Definition perm_eqb (p1 p2 : NotificationPermission) : bool :=
  match p1, p2 with
  | Perm_Default, Perm_Default => true
  | Perm_Granted, Perm_Granted => true
  | Perm_Denied, Perm_Denied => true
  | _, _ => false
  end.

(** Numeric security clearance level for metric / lattice ordering:
    Denied (0) < Default (1) < Granted (2) *)
Definition perm_rank (p : NotificationPermission) : Z :=
  match p with
  | Perm_Denied => 0
  | Perm_Default => 1
  | Perm_Granted => 2
  end.

(** ** 3. Operational Semantics of Permission Transitions *)

(** Models the transition logic of NotificationManager::RequestPermission
    in notification_manager.cc & browser PermissionControllerImpl.
    Crucial Spec & Blink Invariant:
    - If insecure context: immediately resolves/transitions to Denied (or blocks).
    - If currently Perm_Denied: short-circuits, returns Perm_Denied.
    - If currently Perm_Granted: short-circuits, returns Perm_Granted.
    - If currently Perm_Default: evaluates prompt only if secure and user gesture present. *)
Definition step_request_permission
  (current : NotificationPermission)
  (outcome : PromptOutcome)
  (has_gesture : bool)
  (is_secure : bool) : NotificationPermission :=
  match current with
  | Perm_Denied => Perm_Denied
  | Perm_Granted =>
      if is_secure then Perm_Granted else Perm_Denied
  | Perm_Default =>
      if negb is_secure then Perm_Denied
      else if negb has_gesture then Perm_Default
      else match outcome with
           | User_Dismissed => Perm_Default
           | User_Accepted => Perm_Granted
           | User_Blocked => Perm_Denied
           | No_User_Activation_Auto_Deny => Perm_Denied
           | Insecure_Origin_Auto_Deny => Perm_Denied
           end
  end.

(** State transition function for arbitrary ScriptAction *)
Definition step_state (s : NotificationPermission) (a : ScriptAction) : NotificationPermission :=
  match a with
  | Act_RequestPermission outcome gesture secure =>
      step_request_permission s outcome gesture secure
  | Act_ConstructNotification => s
  | Act_ServiceWorkerShowNotification => s
  | Act_PushSubscribe _ => s
  | Act_BadgingSet => s
  | Act_BackgroundSyncRegister => s
  end.

(** Output evaluation function for arbitrary ScriptAction *)
Definition eval_action (s : NotificationPermission) (a : ScriptAction) : ActionResult :=
  match a with
  | Act_RequestPermission outcome gesture secure =>
      Res_PermissionResolved (step_request_permission s outcome gesture secure)
  | Act_ConstructNotification =>
      match s with
      | Perm_Granted => Res_NotificationDispatched
      | _ => Res_NotificationBlockedError
      end
  | Act_ServiceWorkerShowNotification =>
      match s with
      | Perm_Granted => Res_NotificationDispatched
      | _ => Res_NotificationBlockedError
      end
  | Act_PushSubscribe user_visible =>
      if negb user_visible then Res_PushNotAllowedError
      else match s with
           | Perm_Granted => Res_PushSubscribed
           | _ => Res_PushNotAllowedError
           end
  | Act_BadgingSet =>
      match s with
      | Perm_Denied => Res_BadgeSuppressed
      | _ => Res_BadgeUpdated
      end
  | Act_BackgroundSyncRegister =>
      match s with
      | Perm_Granted => Res_SyncRegistered
      | _ => Res_SyncDeniedError
      end
  end.

(** Multi-step execution over a trace of script actions *)
Fixpoint run_trace (s : NotificationPermission) (trace : list ScriptAction) : NotificationPermission :=
  match trace with
  | [] => s
  | a :: rest => run_trace (step_state s a) rest
  end.

(** Collect all action results emitted during a trace *)
Fixpoint trace_results (s : NotificationPermission) (trace : list ScriptAction) : list ActionResult :=
  match trace with
  | [] => []
  | a :: rest => eval_action s a :: trace_results (step_state s a) rest
  end.

(** Predicate asserting that an ActionResult causes no background or UI notification side-effects *)
Definition is_side_effect_blocked (r : ActionResult) : bool :=
  match r with
  | Res_PermissionResolved Perm_Denied => true
  | Res_NotificationBlockedError => true
  | Res_PushNotAllowedError => true
  | Res_BadgeSuppressed => true
  | Res_SyncDeniedError => true
  | _ => false
  end.
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

All theorems below are proven without `Admitted` or axioms, using standard `Bool`, `List`, `ZArith`, and `Lia` tactics.

```coq
(** ** 4. Formal Theorems and Proofs *)

(** Theorem 1: Bijection between MojoPermissionStatus and V8NotificationPermission *)
Theorem mojo_v8_enum_bijection :
  forall (m : MojoPermissionStatus),
    v8_enum_to_mojo (permission_to_v8_enum m) = m.
Proof.
  intros m.
  destruct m; reflexivity.
Qed.

Theorem v8_mojo_enum_bijection :
  forall (p : NotificationPermission),
    permission_to_v8_enum (v8_enum_to_mojo p) = p.
Proof.
  intros p.
  destruct p; reflexivity.
Qed.

(** Theorem 2: Boolean equality reflection for NotificationPermission *)
Theorem perm_eqb_eq :
  forall (p1 p2 : NotificationPermission),
    perm_eqb p1 p2 = true <-> p1 = p2.
Proof.
  intros p1 p2.
  split; intros H.
  - destruct p1, p2; simpl in H; try reflexivity; discriminate H.
  - subst p2. destruct p1; reflexivity.
Qed.

(** Theorem 3: Single-step Absorbing Property of Perm_Denied
    Regardless of user prompt outcome, gesture status, or context security,
    a single step from Perm_Denied always remains in Perm_Denied. *)
Theorem denied_is_absorbing_one_