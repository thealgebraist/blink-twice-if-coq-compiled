# Formal Verification Report: Badging API Display Count Formatting Ceiling Capping

**Agent ID:** Formal Verification Agent 653  
**Specialization:** Web Push, Notifications, Badging & Background Sync in Chromium Blink  
**Chromium Source:** `third_party/blink/renderer/modules/badging/badge.cc`  
**Specification Target:** Badging API §4.1 (Display of a badge)  
**Formal Theory Target:** `BlinkBadgingMaxDisplayCeilingSemantics.v`  
**Mathematical Property:** $\text{display\_badge}(n) = \text{if } n > 99 \text{ then } 99 \text{ else } n$

---

## 1. Normative W3C Badging API Specification Requirements

The W3C Badging API Specification defines the mechanism by which web applications (including foreground contexts via `Navigator` and background execution contexts via `WorkerNavigator` in Service Workers) set or clear application-wide status badges.

### 1.1 Normative Processing Model (§4.1 & §7)

When `setAppBadge(contents)` is invoked with an optional `[EnforceRange] unsigned long long contents`:

1. **Badge State Representation (§4):** An application's badge state is modeled as one of:
   * **"nothing"**: Indicates that no badge is currently set (`BadgeValue::Nothing`).
   * **"flag"**: Indicates that a generic status indicator (e.g., a dot) is set (`BadgeValue::Flag`).
   * **A positive integer $n \in [1, 2^{64}-1]$**: Indicates a numerical notification count.
2. **Zero Handling (§7.1):** If `contents` is explicitly passed as `0`, the user agent MUST set the application badge to **"nothing"** ( clearing the badge).
3. **Display Formatting & Ceiling Capping (§4.1):** When the badge value is an integer $n > 0$, the user agent formats and renders the count on the host OS desktop/taskbar icon. Section 4.1 explicitly dictates:
   > *"If the user agent cannot display the full number of digits (e.g., "1234" is too wide), the user agent SHOULD cap the number at a platform-convenient maximum (e.g., "99+")."*

To maintain consistent visual layout bounds across UI surfaces and prevent text truncation overflow in Web Push and Background Sync notification handlers, the semantic display model maps any positive integer $n > 99$ to the ceiling threshold $99$ (rendered with a saturation indicator or capped directly at $99$).

---

## 2. Chromium Blink Implementation Details and Invariants

In Chromium, the Badging API is implemented within `third_party/blink/renderer/modules/badging/badge.cc` and communicates across the Mojo IPC boundary to the browser process via `blink::mojom::blink::BadgeService`.

### 2.1 Renderer-Side Validation and IPC Dispatch (`badge.cc`)

When `Badge::setAppBadge` is invoked in Blink:

```cpp
// third_party/blink/renderer/modules/badging/badge.cc
ScriptPromise<IDLUndefined> Badge::setAppBadge(ScriptState* script_state,
                                               uint64_t content,
                                               ExceptionState& exception_state) {
  if (content == 0) {
    BadgeServiceFromExecutionContext(ExecutionContext::From(script_state))
        ->ClearBadge();
  } else {
    BadgeServiceFromExecutionContext(ExecutionContext::From(script_state))
        ->SetBadge(mojom::blink::BadgeValue::NewNumber(content));
  }
  return ToResolvedUndefinedPromise(script_state);
}
```

### 2.2 Architectural Invariants

1. **Range Enforcement Invariant:** The WebIDL signature `[EnforceRange] unsigned long long` guarantees that prior to entering `Badge::setAppBadge`, any negative values or values exceeding $2^{64}-1$ throw a `TypeError` in V8 bindings. Thus, within `badge.cc`, $0 \le \text{content} \le 2^{64}-1$.
2. **Zero-to-Clear Equivalence Invariant:** Calling `setAppBadge(0)` does not transmit a `BadgeValue::NewNumber(0)` payload over Mojo; it invokes `ClearBadge()`, preserving the invariant that `BadgeValue::NewNumber(n)` strictly implies $n \ge 1$.
3. **Display Ceiling Saturation Invariant:** Downstream OS badging controllers (`chrome/browser/badging/badge_manager.cc` and platform UI delegates) apply the §4.1 formatting cap (`kMaxBadgeContent = 99`). Any value $n > 99$ passed from `badge.cc` via `NewNumber(n)` saturates at $99$, ensuring bounded string width (`<= 3` glyphs including `+`) and idempotence under repeated ceiling applications.
4. **Background Execution Context Parity:** Because `Badge` supplements both `Navigator` and `WorkerNavigator`, badges updated silently during a `push` or `sync` event in a Service Worker obey identical state transitions and ceiling bounds as foreground document updates.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the formal specification of the Badging API display ceiling semantics, state transitions, and background processing invariants in Rocq/Coq (`BlinkBadgingMaxDisplayCeilingSemantics.v`).

```coq
(** * BlinkBadgingMaxDisplayCeilingSemantics.v
    Formal Verification of W3C Badging API §4.1 Display Ceiling Capping
    and Chromium Blink third_party/blink/renderer/modules/badging/badge.cc *)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.

Import ListNotations.
Open Scope Z_scope.

(** ** 1. Constants & Bounds *)

(** Maximum unsigned 64-bit integer enforced by WebIDL [EnforceRange] unsigned long long *)
Definition UINT64_MAX : Z := 18446744073709551615.

(** W3C Badging API §4.1 Display Capping Ceiling *)
Definition BADGE_DISPLAY_CEILING : Z := 99.

(** Predicate validating WebIDL [EnforceRange] unsigned long long *)
Definition valid_uint64 (n : Z) : Prop :=
  0 <= n <= UINT64_MAX.

(** ** 2. Core Mathematical Property: Display Badge Capping *)

(** Mathematical Property: display_badge(n) = if n > 99 then 99 else n *)
Definition display_badge (n : Z) : Z :=
  if n >? BADGE_DISPLAY_CEILING then BADGE_DISPLAY_CEILING else n.

(** ** 3. Blink Mojo IPC & Badge State Model (badge.cc) *)

(** Represents blink::mojom::blink::BadgeValue and ClearBadge state *)
Inductive BadgeIPCState : Type :=
  | BadgeNothing : BadgeIPCState          (* ClearBadge() / "nothing" *)
  | BadgeFlag    : BadgeIPCState          (* SetBadge(NewFlag(0)) / "flag" *)
  | BadgeNumber  : Z -> BadgeIPCState.    (* SetBadge(NewNumber(n)) where n >= 1 *)

(** Represents optional parameter in setAppBadge([EnforceRange] optional unsigned long long contents) *)
Inductive SetBadgeArg : Type :=
  | ArgOmitted : SetBadgeArg
  | ArgValue   : Z -> SetBadgeArg.

(** Models Badge::setAppBadge in third_party/blink/renderer/modules/badging/badge.cc *)
Definition blink_set_app_badge (arg : SetBadgeArg) : BadgeIPCState :=
  match arg with
  | ArgOmitted => BadgeFlag
  | ArgValue n =>
      if n <=? 0 then BadgeNothing
      else BadgeNumber n
  end.

(** Models Badge::clearAppBadge in third_party/blink/renderer/modules/badging/badge.cc *)
Definition blink_clear_app_badge : BadgeIPCState :=
  BadgeNothing.

(** ** 4. End-to-End UI Display Presentation Semantics *)

Inductive RenderedBadge : Type :=
  | RenderNone      : RenderedBadge
  | RenderDot       : RenderedBadge
  | RenderCount     : Z -> bool -> RenderedBadge. (* (displayed_number, is_capped_plus) *)

(** Evaluates the final visual presentation of an IPC badge state per §4.1 *)
Definition render_badge_state (st : BadgeIPCState) : RenderedBadge :=
  match st with
  | BadgeNothing  => RenderNone
  | BadgeFlag     => RenderDot
  | BadgeNumber n =>
      RenderCount (display_badge n) (n >? BADGE_DISPLAY_CEILING)
  end.

(** Extracts the effective numeric count shown to the user (0 for None/Dot) *)
Definition effective_displayed_count (st : BadgeIPCState) : Z :=
  match st with
  | BadgeNothing  => 0
  | BadgeFlag     => 0
  | BadgeNumber n => display_badge n
  end.

(** ** 5. Background Service Worker Event Trace Model *)

Inductive BadgingOperation : Type :=
  | OpSet   : SetBadgeArg -> BadgingOperation
  | OpClear : BadgingOperation.

Definition execute_op (st : BadgeIPCState) (op : BadgingOperation) : BadgeIPCState :=
  match op with
  | OpSet arg => blink_set_app_badge arg
  | OpClear   => blink_clear_app_badge
  end.

Definition execute_trace (ops : list BadgingOperation) (init : BadgeIPCState) : BadgeIPCState :=
  fold_left execute_op ops init.

(** Well-formedness invariant of BadgeIPCState produced by Blink *)
Definition wf_badge_ipc_state (st : BadgeIPCState) : Prop :=
  match st with
  | BadgeNothing  => True
  | BadgeFlag     => True
  | BadgeNumber n => 1 <= n
  end.
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

The following theorems formally verify the ceiling bounds, idempotence, monotonicity, `Z.min` equivalence, Blink IPC state invariants, and multi-step Service Worker background execution preservation. All proofs are complete and free of `Admitted`.

```coq
(** ** 6. Formal Theorems and Proofs *)

(** Theorem 1: Exact specification equivalence for display_badge *)
Theorem display_badge_spec : forall n : Z,
  (n > 99 -> display_badge n = 99) /\
  (n <= 99 -> display_badge n = n).
Proof.
  intros n.
  unfold display_badge, BADGE_DISPLAY_CEILING.
  destruct (Z.gtb_spec n 99) as [Hgt | Hle].
  - split; intros H; [reflexivity | lia].
  - split; intros H; [lia | reflexivity].
Qed.

(** Theorem 2: Equivalence with Z.min ceiling operator *)
Theorem display_badge_eq_zmin : forall n : Z,
  display_badge n = Z.min n BADGE_DISPLAY_CEILING.
Proof.
  intros n.
  unfold display_badge, BADGE_DISPLAY_CEILING.
  destruct (Z.gtb_spec n 99) as [Hgt | Hle].
  - symmetry. apply Z.min_r. lia.
  - symmetry. apply Z.min_l. lia.
Qed.

(** Theorem 3: Upper bound ceiling invariant for all integers *)
Theorem display_badge_upper_bound : forall n : Z,
  display_badge n <= BADGE_DISPLAY_CEILING.
Proof.
  intros n.
  rewrite display_badge_eq_zmin.
  apply Z.le_min_r.
Qed.

(** Theorem 4: Strict range [1, 99] invariant for positive badge counts *)
Theorem display_badge_positive_range : forall n : Z,
  1 <= n -> 1 <= display_badge n <= 99.
Proof.
  intros n Hpos.
  unfold display_badge, BADGE_DISPLAY_CEILING.
  destruct (Z.gtb_spec n 99) as [Hgt | Hle]; lia.
Qed.

(** Theorem 5: Non-negativity preservation for WebIDL uint64 inputs *)
Theorem display_badge_nonneg : forall n : Z,
  0 <= n -> 0 <= display_badge n <= 99.
Proof.
  intros n Hnonneg.
  unfold display_badge, BADGE_DISPLAY_CEILING.
  destruct (Z.gtb_spec n 99) as [Hgt | Hle]; lia.
Qed.

(** Theorem 6: Idempotence of display ceiling formatting *)
Theorem display_badge_idempotent : forall n : Z,
  display_badge (display_badge n) = display_badge n.
Proof.
  intros n.
  unfold display_badge, BADGE_DISPLAY_CEILING.
  destruct (Z.gtb_spec n 99) as [Hgt | Hle].
  - replace (99 >? 99) with false by reflexivity.
    reflexivity.
  - destruct (Z.gtb_spec n 99) as [Hgt2 | Hle2]; [lia | reflexivity].
Qed.

(** Theorem 7: Monotonicity of display_badge across count increments *)
Theorem display_badge_monotonic : forall n m : Z,
  n <= m -> display_badge n <= display_badge m.
Proof.
  intros n m Hle.
  repeat rewrite display_badge_eq_zmin.
  unfold BADGE_DISPLAY_CEILING.
  lia.
Qed.

(** Theorem 8: Blink setAppBadge(0) clears the badge instead of sending Number(0) *)
Theorem blink_zero_clears_badge :
  blink_set_app_badge (ArgValue 0) = BadgeNothing /\
  effective_displayed_count (blink_set_app_badge (ArgValue 0)) = 0.
Proof.
  unfold blink_set_app_badge, effective_displayed_count.
  simpl. split; reflexivity.
Qed.

(** Theorem 9: Blink setAppBadge maintains the positive number IPC invariant *)
Theorem blink_set_app_badge_wf : forall arg : SetBadgeArg,
  wf_badge_ipc_state (blink_set_app_badge arg).
Proof.
  intros [ | n]; simpl.
  - exact I.
  - destruct (Z.leb_spec n 0) as [Hle | Hgt]; simpl.
    + exact I.
    + lia.
Qed.

(** Theorem 10: Effective displayed count is always bounded in [0, 99] for valid states *)
Theorem effective_displayed_count_bounded : forall st : BadgeIPCState,
  wf_badge_ipc_state st ->
  0 <= effective_displayed_count st <= 99.
Proof.
  intros [ | | n] Hwf; simpl in *.
  - lia.
  - lia.
  - pose proof (display_badge_positive_range n Hwf