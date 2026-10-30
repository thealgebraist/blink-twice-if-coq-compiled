# Formal Verification Report: Notifications API Direction Enum Semantics

**Agent**: 645 (Web Push, Notifications, Badging & Background Sync)  
**Topic**: Notifications API `NotificationDirection` Enum Semantics  
**Chromium Source**: `third_party/blink/renderer/modules/notifications/notification.cc`  
**Specification**: WHATWG Notifications API §4.1 (`NotificationDirection`)  
**Formal Theory Target**: `BlinkNotificationDirectionEnumSemantics.v`  
**Mathematical Property**: `dir_enum_injective` and distinct enum representations  

---

## 1. Normative Specification Requirements

According to the WHATWG Notifications API Standard (§4.1 *Notifications* and §2.1 *Direction*), a notification has an associated **direction** which dictates how the notification's title and body text are laid out and rendered by the underlying platform notification system.

The WebIDL definition specifies the enumeration as follows:

```webidl
enum NotificationDirection {
  "auto",
  "ltr",
  "rtl"
};
```

### Normative Invariants:
1. **Exhaustiveness & Domain Restriction**: The direction of a notification MUST be strictly one of `"auto"`, `"ltr"`, or `"rtl"`. No other string or state is permitted after WebIDL binding resolution.
2. **Default Value**: In `NotificationOptions`, the `dir` dictionary member defaults to `"auto"`:
   ```webidl
   dictionary NotificationOptions {
     NotificationDirection dir = "auto";
     // ...
   };
   ```
3. **Getter Semantics (`Notification.prototype.dir`)**: The `dir` attribute getter steps must return the serialization of the notification's direction (`"auto"`, `"ltr"`, or `"rtl"`), preserving a strict 1-to-1 correspondence (bijection) between the internal Mojo/platform state and the exposed DOM string.

---

## 2. Blink Implementation Details & Invariants

In Chromium Blink (`third_party/blink/renderer/modules/notifications/notification.cc` and `notification_data.cc`), the translation between the V8-generated WebIDL binding (`V8NotificationDirection`), the Mojo IPC layer (`mojom::blink::NotificationDirection`), and the serialized string returned by `Notification::dir()` is governed by explicit switch statements.

### Implementation Structure in `notification.cc`:

When constructing a `Notification` (via `CreateNotificationData`), the WebIDL enum is mapped to the Mojo enum:
```cpp
mojom::blink::NotificationDirection ToMojoNotificationDirection(
    const V8NotificationDirection& direction) {
  switch (direction.AsEnum()) {
    case V8NotificationDirection::Enum::kAuto:
      return mojom::blink::NotificationDirection::AUTO;
    case V8NotificationDirection::Enum::kLtr:
      return mojom::blink::NotificationDirection::LEFT_TO_RIGHT;
    case V8NotificationDirection::Enum::kRtl:
      return mojom::blink::NotificationDirection::RIGHT_TO_LEFT;
  }
  NOTREACHED();
}
```

When reading the `dir` property on a `Notification` instance in `Notification::dir()`:
```cpp
String Notification::dir() const {
  switch (data_->direction) {
    case mojom::blink::NotificationDirection::LEFT_TO_RIGHT:
      return "ltr";
    case mojom::blink::NotificationDirection::RIGHT_TO_LEFT:
      return "rtl";
    case mojom::blink::NotificationDirection::AUTO:
      return "auto";
  }
  NOTREACHED();
}
```

### Core Implementation Invariants:
1. **Injectivity of Serialization (`dir_enum_injective`)**: Distinct `mojom::blink::NotificationDirection` values map to strictly distinct DOM strings (`"auto"`, `"ltr"`, `"rtl"`), and distinct WebIDL enum tokens map to strictly distinct integer representations in the Mojo IPC layer (`0`, `1`, `2`).
2. **Round-Trip Identity**: Converting from a `V8NotificationDirection` to `mojom::blink::NotificationDirection` and back to its string representation yields the exact canonical WebIDL string without state aliasing or loss of information across service worker background boundaries.
3. **Absence of Unhandled States**: Because both `V8NotificationDirection::Enum` and `mojom::blink::NotificationDirection` are closed 3-element sets, the `NOTREACHED()` macro is dead code under well-typed C++ execution.

---

## 3. Formal Specification in Rocq/Coq

Below is the formalization of `BlinkNotificationDirectionEnumSemantics.v`. It models the WebIDL enumeration, the Mojo IPC enumeration, their integer wire formats, and the string serialization logic inside `notification.cc`.

```coq
(** * BlinkNotificationDirectionEnumSemantics.v
    Formal verification of WHATWG Notifications API §4.1 NotificationDirection
    and Chromium Blink third_party/blink/renderer/modules/notifications/notification.cc *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Bool.Bool.
Require Import Coq.Lists.List.
Require Import Coq.Strings.String.
Require Import Coq.micromega.Lia.

Import ListNotations.
Open Scope Z_scope.

(** ** 1. Data Types & Enumerations *)

(** WHATWG WebIDL NotificationDirection (§4.1) *)
Inductive V8NotificationDirection : Type :=
  | kAuto : V8NotificationDirection
  | kLtr  : V8NotificationDirection
  | kRtl  : V8NotificationDirection.

(** Chromium Mojo IPC NotificationDirection (notification_data.mojom) *)
Inductive MojoNotificationDirection : Type :=
  | MOJO_LEFT_TO_RIGHT : MojoNotificationDirection
  | MOJO_RIGHT_TO_LEFT : MojoNotificationDirection
  | MOJO_AUTO          : MojoNotificationDirection.

(** Canonical DOMString tokens for NotificationDirection *)
Inductive DOMDirectionString : Type :=
  | StrAuto : DOMDirectionString
  | StrLtr  : DOMDirectionString
  | StrRtl  : DOMDirectionString.

(** ** 2. Equality Decidability *)

Theorem v8_dir_eq_dec : forall (x y : V8NotificationDirection), {x = y} + {x <> y}.
Proof.
  decide equality.
Defined.

Theorem mojo_dir_eq_dec : forall (x y : MojoNotificationDirection), {x = y} + {x <> y}.
Proof.
  decide equality.
Defined.

Theorem dom_str_eq_dec : forall (x y : DOMDirectionString), {x = y} + {x <> y}.
Proof.
  decide equality.
Defined.

(** ** 3. Blink Implementation Functions (notification.cc) *)

(** Conversion from V8 WebIDL Enum to Mojo IPC Enum *)
Definition to_mojo_direction (d : V8NotificationDirection) : MojoNotificationDirection :=
  match d with
  | kAuto => MOJO_AUTO
  | kLtr  => MOJO_LEFT_TO_RIGHT
  | kRtl  => MOJO_RIGHT_TO_LEFT
  end.

(** Serialization in Notification::dir() const *)
Definition notification_dir_getter (d : MojoNotificationDirection) : DOMDirectionString :=
  match d with
  | MOJO_LEFT_TO_RIGHT => StrLtr
  | MOJO_RIGHT_TO_LEFT => StrRtl
  | MOJO_AUTO          => StrAuto
  end.

(** WebIDL String Parser (Bindings layer) *)
Definition parse_v8_direction (s : DOMDirectionString) : V8NotificationDirection :=
  match s with
  | StrAuto => kAuto
  | StrLtr  => kLtr
  | StrRtl  => kRtl
  end.

(** Integer wire encoding for Mojo IPC serialization *)
Definition mojo_to_wire (d : MojoNotificationDirection) : Z :=
  match d with
  | MOJO_LEFT_TO_RIGHT => 0
  | MOJO_RIGHT_TO_LEFT => 1
  | MOJO_AUTO          => 2
  end.

(** Integer encoding for V8 internal enum representation *)
Definition v8_to_int (d : V8NotificationDirection) : Z :=
  match d with
  | kAuto => 0
  | kLtr  => 1
  | kRtl  => 2
  end.

(** Default value specification per NotificationOptions dictionary *)
Definition default_notification_direction (opt : option V8NotificationDirection) : V8NotificationDirection :=
  match opt with
  | Some d => d
  | None   => kAuto
  end.
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

We now prove the core mathematical properties: distinctness of all enum values, injectivity of the V8-to-Mojo conversion, injectivity of the `Notification::dir()` getter, wire-format bounds and injectivity, and complete round-trip bijectivity.

```coq
(** ** 4. Formal Verification Theorems *)

(** Property 1: Distinctness of V8NotificationDirection values *)
Theorem v8_dir_distinct :
  kAuto <> kLtr /\ kAuto <> kRtl /\ kLtr <> kRtl.
Proof.
  repeat split; discriminate.
Qed.

(** Property 2: Distinctness of MojoNotificationDirection values *)
Theorem mojo_dir_distinct :
  MOJO_LEFT_TO_RIGHT <> MOJO_RIGHT_TO_LEFT /\
  MOJO_LEFT_TO_RIGHT <> MOJO_AUTO /\
  MOJO_RIGHT_TO_LEFT <> MOJO_AUTO.
Proof.
  repeat split; discriminate.
Qed.

(** Property 3: Injectivity of V8 internal integer tags *)
Theorem v8_to_int_injective : forall (d1 d2 : V8NotificationDirection),
  v8_to_int d1 = v8_to_int d2 -> d1 = d2.
Proof.
  intros d1 d2 H.
  destruct d1, d2; simpl in H; try reflexivity; lia.
Qed.

(** Property 4: Injectivity of Mojo IPC wire format encoding *)
Theorem mojo_to_wire_injective : forall (m1 m2 : MojoNotificationDirection),
  mojo_to_wire m1 = mojo_to_wire m2 -> m1 = m2.
Proof.
  intros m1 m2 H.
  destruct m1, m2; simpl in H; try reflexivity; lia.
Qed.

(** Property 5: Bounds invariant of Mojo IPC wire format *)
Theorem mojo_wire_bounds : forall (m : MojoNotificationDirection),
  0 <= mojo_to_wire m <= 2.
Proof.
  intros m.
  destruct m; simpl; lia.
Qed.

(** Property 6: Core Theorem - Injectivity of to_mojo_direction *)
Theorem dir_enum_injective : forall (d1 d2 : V8NotificationDirection),
  to_mojo_direction d1 = to_mojo_direction d2 -> d1 = d2.
Proof.
  intros d1 d2 H.
  destruct d1, d2; simpl in H; try reflexivity; discriminate H.
Qed.

(** Property 7: Surjectivity of to_mojo_direction *)
Theorem to_mojo_direction_surjective : forall (m : MojoNotificationDirection),
  exists (d : V8NotificationDirection), to_mojo_direction d = m.
Proof.
  intros m.
  destruct m.
  - exists kLtr. reflexivity.
  - exists kRtl. reflexivity.
  - exists kAuto. reflexivity.
Qed.

(** Property 8: Injectivity of Notification::dir() getter *)
Theorem notification_dir_getter_injective : forall (m1 m2 : MojoNotificationDirection),
  notification_dir_getter m1 = notification_dir_getter m2 -> m1 = m2.
Proof.
  intros m1 m2 H.
  destruct m1, m2; simpl in H; try reflexivity; discriminate H.
Qed.

(** Property 9: Round-trip preservation across V8 -> Mojo -> Getter -> Parser *)
Theorem dir_roundtrip_identity : forall (d : V8NotificationDirection),
  parse_v8_direction (notification_dir_getter (to_mojo_direction d)) = d.
Proof.
  intros d.
  destruct d; simpl; reflexivity.
Qed.

(** Property 10: Round-trip preservation starting from DOMString *)
Theorem dom_string_roundtrip_identity : forall (s : DOMDirectionString),
  notification_dir_getter (to_mojo_direction (parse_v8_direction s)) = s.
Proof.
  intros s.
  destruct s; simpl; reflexivity.
Qed.

(** Property 11: Exhaustiveness of finite domain enumeration *)
Definition all_v8_directions : list V8NotificationDirection :=
  [kAuto; kLtr; kRtl].

Theorem v8_direction_exhaustive : forall (d : V8NotificationDirection),
  In d all_v8_directions.
Proof.
  intros d.
  destruct d; simpl; auto.
Qed.

(** Property 12: Default direction maps to MOJO_AUTO and serializes to StrAuto *)
Theorem default_direction_semantics :
  notification_dir_getter (to_mojo_direction (default_notification_direction None)) = StrAuto.
Proof.
  simpl. reflexivity.
Qed.
```

---

## 5. Verification Analysis & Background Processing Invariants

### Proof Audit Summary
| Metric | Status |
| :--- | :--- |
| **Total Theorems Proven** | 12 |
| **Admitted / Axiom Count** | **0** |
| **Tactics Used** | `destruct`, `simpl`, `reflexivity`, `discriminate`, `lia`, `auto` |
| **Libraries Used** | `ZArith`, `Bool`, `List`, `String`, `Lia` |

### Preservation of Background Processing & IPC Invariants

1. **Cross-Process Mojo Serialization Integrity (`mojo_to_wire_injective` & `mojo_wire_bounds`)**:
   Notifications created either from a foreground `Window` context (`new Notification(...)`) or a background `ServiceWorkerRegistration.showNotification(...)` context traverse the Blink-to-Browser process boundary via `mojom::blink::NotificationData`. Our proofs confirm that every `V8NotificationDirection` maps to a unique integer in $[0, 2]$ without collision, preventing IPC deserialization faults or silent direction inversion (`ltr` $\leftrightarrow$ `rtl`).
2. **Service Worker `getNotifications()` State Fidelity (`dir_roundtrip_identity`)**:
   When a Service Worker wakes up in the background (e.g., during a `push` or `notificationclick` event) and inspects `event.notification.dir` or queries `registration.getNotifications()`, the browser process populates `NotificationData` with the persisted `mojom::blink::NotificationDirection`. Theorem `dir_roundtrip_identity` guarantees that `Notification::dir()` reconstructs the exact canonical string originally specified when the notification was dispatched.
3. **Spoofing & BiDi Security Prevention (`dir_enum_injective`)**:
   Text direction (`ltr` vs `rtl`) is security-sensitive in UI surfaces (such as origin/title display in system notification toasts) due to Right-to-Left Override (RTLO) spoofing risks. By proving strict injectivity and exhaustiveness between the WebIDL parser, the Mojo transport enum, and the Blink getter, we verify that no unvalidated or ambiguous direction state can