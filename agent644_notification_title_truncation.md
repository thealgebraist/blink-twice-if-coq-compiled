# Formal Verification Report: Notifications API Title Non-Empty and Length Bounding

**Agent**: 644 (Web Push, Notifications, Badging & Background Sync)  
**Chromium Source**: `third_party/blink/renderer/modules/notifications/notification.cc`  
**Specification**: WHATWG Notifications API §4.1 (Notification Concept & Title Normalization)  
**Formal Theory Target**: `BlinkNotificationTitleTruncationSemantics.v`  
**Mathematical Property**: $\text{norm\_title\_len}(\text{raw}) = \min(\text{raw}, \text{MAX\_TITLE\_LEN}) \land (\text{raw} > 0 \implies \text{norm\_title\_len}(\text{raw}) > 0)$

---

## 1. Normative Specification Requirements

According to the WHATWG Notifications API Standard (§2 *Notifications* and §4.1 *Create a notification*):

1. **Title Presence**: A notification has an associated *title* (a `DOMString`). When constructing a `Notification(title, options)` or invoking `ServiceWorkerRegistration.showNotification(title, options)`, the `title` argument is required by the WebIDL interface:
   ```webidl
   [Exposed=(Window,Worker)]
   interface Notification : EventTarget {
     constructor(DOMString title, optional NotificationOptions options = {});
     readonly attribute DOMString title;
     ...
   };
   ```
2. **Directionality and Normalization**: In §4.1 step 4, the notification's *title* is set to the raw `title` string passed to the algorithm. While the abstract specification treats `DOMString` length as unbounded, §2.1 (*Platform integration and resource constraints*) and Mojo IPC security guidelines permit user agents to bound string payloads sent to the browser process and underlying OS notification daemons (e.g., Windows Action Center, macOS Notification Center, freedesktop.org D-Bus `org.freedesktop.Notifications`, Android `NotificationManager`) to prevent out-of-memory (OOM) denial-of-service attacks across process boundaries.
3. **Non-Empty Invariant**: If the web developer supplies a non-empty title string ($\text{length}(\text{raw}) > 0$), platform truncation must preserve at least a non-empty prefix ($0 < \text{length}(\text{normalized}) \le \text{MAX\_TITLE\_LEN}$), ensuring the user agent never degrades a valid title into an empty notification header due to bounding logic.

---

## 2. Blink Implementation Details & Invariants

In Chromium's Blink rendering engine, `third_party/blink/renderer/modules/notifications/notification.cc` and `notification_data.cc` prepare `mojom::blink::NotificationData` before transmitting it over Mojo IPC to `content::PlatformNotificationService` in the browser process.

### Architectural Execution Flow
1. **Entry Points**:
   - `Notification::Create(ExecutionContext*, const String& title, const NotificationOptions*, ExceptionState&)`
   - `ServiceWorkerRegistrationNotifications::showNotification(...)`
2. **Data Packaging**:
   Both paths invoke `CreateNotificationData(...)`, which populates a `mojom::blink::NotificationDataPtr`.
3. **Length Bounding & IPC Safety**:
   To prevent renderer-to-browser IPC flooding and OS notification subsystem hangs (such as Android `TransactionTooLargeException` in Binder IPC when passing `Notification` parcels), Blink/Content enforces maximum character limits on notification fields (`kMaximumNotificationTitleLength`, standardized in Chromium platform limits or truncation helpers via `String::Left(max_len)` / ` base::TruncateUTF8ToByteSize`).
4. **Key C++ Invariants**:
   - **Monotonicity & Idempotence**: Truncating an already bounded title yields the exact same title string.
   - **Strict Positivity Preservation**: Given `MAX_TITLE_LEN > 0`, any `title` with `title.length() > 0` retains `normalized_title.length() > 0` after `title.Substring(0, std::min(title.length(), kMaxTitleLength))`.
   - **Upper Bound Guarantee**: For all input strings `raw`, `normalized_title.length() <= kMaxTitleLength`.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the self-contained, complete formalization of `BlinkNotificationTitleTruncationSemantics.v` modeling both the integer length arithmetic (`Z`) and the exact character sequence manipulation (`list ascii` / polymorphic `list A`).

```coq
(** * BlinkNotificationTitleTruncationSemantics.v
    Formal verification of Chromium Blink Notification Title Normalization
    and Length Bounding (third_party/blink/renderer/modules/notifications/notification.cc).
*)

From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
From Coq Require Import List.
Import ListNotations.

Open Scope Z_scope.

Section NotificationTitleBounding.

  (** Maximum permitted title length in UTF-16 code units / characters.
      In Chromium, this constant is strictly positive (e.g., 1024 or 4096). *)
  Variable MAX_TITLE_LEN : Z.
  Hypothesis H_MAX_POS : 0 < MAX_TITLE_LEN.

  (** ** 1. Length-Level Specification *)

  (** Mathematical normalization function for raw string length.
      Clamps negative values to 0 (defensive unsigned conversion) and caps at MAX_TITLE_LEN. *)
  Definition norm_title_len (raw : Z) : Z :=
    Z.min (Z.max 0 raw) MAX_TITLE_LEN.

  (** Simplified length specification when raw length is known to be non-negative. *)
  Definition norm_title_len_nonneg (raw : Z) : Z :=
    Z.min raw MAX_TITLE_LEN.

  (** Predicate stating that a normalized title length satisfies all IPC invariants. *)
  Definition valid_normalized_len (raw norm : Z) : Prop :=
    0 <= norm /\
    norm <= MAX_TITLE_LEN /\
    norm <= Z.max 0 raw /\
    (0 < raw -> 0 < norm).

  (** ** 2. Sequence-Level (UTF-16 Code Unit List) Specification *)

  Context {Char : Type}.

  (** Safe prefix extraction corresponding to WTF::String::Left / Substring(0, n) *)
  Definition truncate_string (max_len : nat) (s : list Char) : list Char :=
    firstn max_len s.

  (** Non-empty validation predicate used before displaying/dispatching notifications *)
  Definition is_non_empty_title (s : list Char) : bool :=
    match s with
    | [] => false
    | _ :: _ => true
    end.

  (** Mojo NotificationData record abstraction *)
  Record NotificationData : Type := mkNotificationData {
    nd_title : list Char;
    nd_silent : bool;
    nd_require_interaction : bool
  }.

  (** Blink CreateNotificationData normalization step *)
  Definition create_notification_data
    (max_len : nat) (raw_title : list Char) (silent req_int : bool) : NotificationData :=
    mkNotificationData
      (truncate_string max_len raw_title)
      silent
      req_int.

```

---

## 4. Concrete Theorems and Complete Proofs

```coq
  (** ** 3. Formal Theorems & Proofs *)

  (** Theorem 1: For non-negative raw lengths, norm_title_len equals Z.min raw MAX_TITLE_LEN. *)
  Theorem norm_title_len_eq_min :
    forall (raw : Z),
      0 <= raw ->
      norm_title_len raw = Z.min raw MAX_TITLE_LEN.
  Proof.
    intros raw H_nonneg.
    unfold norm_title_len.
    replace (Z.max 0 raw) with raw by lia.
    reflexivity.
  Qed.

  (** Theorem 2: Strict positivity preservation (0 < raw -> 0 < norm_title_len raw). *)
  Theorem norm_title_len_strictly_positive :
    forall (raw : Z),
      0 < raw ->
      0 < norm_title_len raw.
  Proof.
    intros raw H_pos.
    unfold norm_title_len.
    pose proof H_MAX_POS as H_max.
    lia.
  Qed.

  (** Theorem 3: Upper and lower bounding invariant holds for all Z inputs. *)
  Theorem norm_title_len_bounds :
    forall (raw : Z),
      valid_normalized_len raw (norm_title_len raw).
  Proof.
    intros raw.
    unfold valid_normalized_len, norm_title_len.
    pose proof H_MAX_POS as H_max.
    split; [lia | split; [lia | split; [lia | lia]]].
  Qed.

  (** Theorem 4: Idempotence of title length normalization.
      Normalizing an already normalized title length does not alter it. *)
  Theorem norm_title_len_idempotent :
    forall (raw : Z),
      norm_title_len (norm_title_len raw) = norm_title_len raw.
  Proof.
    intros raw.
    unfold norm_title_len.
    pose proof H_MAX_POS as H_max.
    lia.
  Qed.

  (** Theorem 5: Monotonicity of title length normalization. *)
  Theorem norm_title_len_monotonic :
    forall (r1 r2 : Z),
      r1 <= r2 ->
      norm_title_len r1 <= norm_title_len r2.
  Proof.
    intros r1 r2 H_le.
    unfold norm_title_len.
    lia.
  Qed.

  (** Theorem 6: Sequence-level length correspondence with norm_title_len_nonneg. *)
  Theorem truncate_string_length_Z :
    forall (max_nat : nat) (s : list Char),
      Z.of_nat max_nat = MAX_TITLE_LEN ->
      Z.of_nat (length (truncate_string max_nat s)) =
        norm_title_len (Z.of_nat (length s)).
  Proof.
    intros max_nat s H_max_eq.
    unfold truncate_string, norm_title_len.
    rewrite firstn_length.
    rewrite Nat2Z.inj_min.
    rewrite H_max_eq.
    lia.
  Qed.

  (** Theorem 7: Sequence-level non-empty preservation.
      If max_nat > 0 and the input string is non-empty, the truncated string is non-empty. *)
  Theorem truncate_string_preserves_non_empty :
    forall (max_nat : nat) (s : list Char),
      (0 < max_nat)%nat ->
      is_non_empty_title s = true ->
      is_non_empty_title (truncate_string max_nat s) = true.
  Proof.
    intros max_nat s H_max_pos H_non_empty.
    destruct s as [| c cs].
    - simpl in H_non_empty. discriminate H_non_empty.
    - destruct max_nat as [| m'].
      + lia.
      + simpl. reflexivity.
  Qed.

  (** Theorem 8: Preservation of background notification options and bounded title invariant
      in CreateNotificationData. *)
  Theorem create_notification_data_invariants :
    forall (max_nat : nat) (raw_title : list Char) (silent req_int : bool),
      Z.of_nat max_nat = MAX_TITLE_LEN ->
      let nd := create_notification_data max_nat raw_title silent req_int in
      Z.of_nat (length (nd_title nd)) = Z.min (Z.of_nat (length raw_title)) MAX_TITLE_LEN /\
      (0 < Z.of_nat (length raw_title) -> 0 < Z.of_nat (length (nd_title nd))) /\
      nd_silent nd = silent /\
      nd_require_interaction nd = req_int.
  Proof.
    intros max_nat raw_title silent req_int H_max_eq nd.
    unfold nd, create_notification_data, truncate_string.
    simpl.
    rewrite firstn_length.
    rewrite Nat2Z.inj_min.
    rewrite H_max_eq.
    pose proof H_MAX_POS as H_max.
    split; [lia | split; [lia | split; reflexivity]].
  Qed.

End NotificationTitleBounding.
```

---

## 5. Verification Analysis

### 5.1 Proof Completeness Audit (0 Admits)
All 8 theorems in `BlinkNotificationTitleTruncationSemantics.v` are closed with `Qed` and use no `Admitted`, `admit`, or unsound axioms:
- `norm_title_len_eq_min`: Proven via linear integer arithmetic (`lia`).
- `norm_title_len_strictly_positive`: Proven via `lia` under hypothesis `0 < MAX_TITLE_LEN`.
- `norm_title_len_bounds`: Proven via `lia`, establishing non-negativity, upper-bounding by `MAX_TITLE_LEN`, upper-bounding by `raw`, and positivity preservation.
- `norm_title_len_idempotent`: Proven via `lia`, guaranteeing that repeated normalization across renderer and browser processes is a no-op.
- `norm_title_len_monotonic`: Proven via `lia`.
- `truncate_string_length_Z`: Bridges the concrete list operations (`List.firstn`) to the integer specification (`Z.min`) via `firstn_length` and `Nat2Z.inj_min`.
- `truncate_string_preserves_non_empty`: Proven by structural case analysis on the character list `s` and bound `max_nat`.
- `create_notification_data_invariants`: Proven for the composite `NotificationData` record.

### 5.2 Preservation of Background Processing Invariants
In Chromium's Web Push and Background Sync architecture:
1. **Service Worker Push Dispatch**: When a `push` event triggers `ServiceWorkerRegistration.showNotification(title, options)` in a background worker thread, `CreateNotificationData` constructs the Mojo payload.
2. **IPC Serialization Invariant**: Theorem 6 and Theorem 8 prove that `nd_title` is deterministically bounded by `MAX_TITLE_LEN` before crossing the Mojo pipe into `PlatformNotificationContextImpl`, preventing oversized database entries in the Chrome Notification Database (LevelDB) and OS notification bridges.
3. **Orthogonality**: Theorem 8 confirms that normalizing and truncating `nd_title` is strictly orthogonal to behavioral flags (`nd_silent`, `nd_require_interaction`), preserving background notification semantics without side effects.