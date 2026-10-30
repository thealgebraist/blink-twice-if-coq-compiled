# Formal Verification of Chromium Blink `PointerEvent` Unique Identifier Tracking and Primary Pointer Invariants

## 1. Normative Specification Requirements (W3C Pointer Events Level 3 §5)

According to **W3C Pointer Events Level 3, Section 5 (PointerEvent Interface)**, user agents must manage abstract pointer input across heterogeneous hardware (mouse, pen, touch) through a unified state machine governed by strict identifier and primacy invariants:

1. **`pointerId` Uniqueness and Lifecycle (§5.2.1):**
   * The `pointerId` attribute is an integer identifier uniquely identifying a pointer during its active session.
   * This identifier must be unique among all *active pointers* at any given time.
   * For mouse inputs, the specification reserves a constant, persistent identifier (`pointerId = 1` in Blink/Web platform conventions) that remains active or hover-capable across the browsing session.
   * For non-mouse inputs (touch, pen/stylus), a pointer becomes active upon hardware contact or proximity (`pointerdown`, `pointerenter`, `pointerover`) and ceases to be active upon release or cancellation (`pointerup`, `pointercancel`, `pointerout`, `pointerleave`).

2. **`isPrimary` Designation and Exclusivity (§5.2.2 & §5.2.3):**
   * In a multi-pointer scenario, the `isPrimary` boolean attribute indicates whether the pointer represents the *primary pointer* for its specific `pointerType` (`"mouse"`, `"pen"`, `"touch"`).
   * **Exclusivity Invariant:** At any point in time, for a given `pointerType`, **at most one** active pointer may have `isPrimary` set to `true`.
   * **First-Active Assignment Rule:** A pointer is designated as primary for its `pointerType` if and only if there are no other active pointers of that `pointerType` when its session begins.
   * **Primary Persistence Rule:** Once a pointer is designated as `isPrimary = true`, it retains its primary designation for the entirety of its active lifecycle, even if subsequent pointers of the same type become active or if the primary pointer ceases to be the lowest-numbered active identifier. If the primary pointer is released while secondary pointers remain active, **none** of the remaining active pointers of that type become primary; the primary slot for that `pointerType` remains vacant until a new pointer initiates while either no pointers of that type are active, or as governed by the primary pointer tracking state. *(Note: Specifically in W3C Pointer Events §5.2.3 and Blink's `PointerEventFactory`, a new pointer becomes primary only when no other pointers of that type are currently active, or if the tracked `primary_id_` for that type is currently unset).*

---

## 2. Chromium Blink Implementation Analysis (`pointer_event_factory.cc`)

In Chromium's rendering engine, `blink::PointerEventFactory` (`third_party/blink/renderer/core/events/pointer_event_factory.cc` and `.h`) serves as the canonical translation layer between platform `WebPointerEvent` instances (dispatched via the compositor/input router and scheduled onto the main thread or worklet queues) and DOM `PointerEvent` objects.

### 2.1 Core Data Structures and State Representation

`PointerEventFactory` maintains several hash maps and counters to enforce the W3C invariants across the main thread event pipeline:

```cpp
// Conceptual structure from third_party/blink/renderer/core/events/pointer_event_factory.h
class CORE_EXPORT PointerEventFactory {
  DISALLOW_NEW();
 public:
  // Fixed Mouse ID per W3C / Blink convention
  static const PointerId kMouseId = 1;
  static const PointerId kInvalidId = 0;

 private:
  struct IncomingId : public std::pair<int, int> {
    IncomingId() = default;
    IncomingId(WebPointerProperties::PointerType pointer_type, int raw_id)
        : std::pair<int, int>(static_cast<int>(pointer_type), raw_id) {}
    int PointerTypeInt() const { return first; }
    int RawId() const { return second; }
  };

  struct PointerAttributes {
    IncomingId incoming_id;
    bool is_active_buttons = false;
    bool hovering = false;
    // ... additional device tracking metadata ...
  };

  // Monotonically increasing generator for non-mouse PointerIds (starts at 2)
  PointerId current_id_ = PointerEventFactory::kMouseId + 1;

  // Bi-directional mapping between platform (PointerType, raw_id) and DOM PointerId
  HashMap<IncomingId, PointerId> pointer_incoming_id_mapping_;
  HashMap<PointerId, PointerAttributes> pointer_id_mapping_;

  // Per-PointerType tracking of the currently designated primary PointerId
  // Indexed by static_cast<size_t>(WebPointerProperties::PointerType)
  std::array<PointerId, static_cast<size_t>(WebPointerProperties::PointerType::kMaxValue) + 1> primary_id_;
  std::array<int, static_cast<size_t>(WebPointerProperties::PointerType::kMaxValue) + 1> id_count_;
};
```

### 2.2 State Transition Mechanics and Invariants

1. **ID Allocation (`AddOrUpdateIdAndActiveButtons`):**
   * When a `WebPointerEvent` arrives with `(type, raw_id)`:
   * If `type == kMouse`, it unconditionally maps to `kMouseId` (`1`), and `primary_id_[kMouse]` is permanently initialized to `kMouseId`.
   * For other types (`kTouch`, `kPen`), if `IncomingId(type, raw_id)` is not present in `pointer_incoming_id_mapping_`:
     * A fresh `PointerId` is allocated from `current_id_++`.
     * If `id_count_[type] == 0` (meaning no pointers of `type` are currently tracked in `pointer_id_mapping_`) and `primary_id_[type] == kInvalidId`, Blink sets `primary_id_[type] = mapped_id`.
     * `id_count_[type]` is incremented, and the bi-directional mappings are inserted.

2. **Primacy Evaluation (`IsPrimary`):**
   * `bool PointerEventFactory::IsPrimary(PointerId id) const` queries `pointer_id_mapping_` to find the `type` associated with `id`, and returns `primary_id_[type] == id`.
   * Because `primary_id_[type]` holds a single scalar `PointerId` (or `kInvalidId = 0`), it is structurally impossible for two distinct `PointerId`s of the same `PointerType` to evaluate `IsPrimary(id) == true` simultaneously.
   * Furthermore, when unified across a single pointer modality (or when abstracting over a per-type slice of the factory state), **at most 1 active pointer is designated as `isPrimary`**.

3. **Teardown and Eviction (`Remove`):**
   * Upon `pointerup` or `pointercancel` (when non-hovering, or upon `pointerleave`), `PointerEventFactory::Remove(const PointerId mapped_id)` is invoked.
   * It decrements `id_count_[type]` and erases `mapped_id` from `pointer_id_mapping_` and `pointer_incoming_id_mapping_`.
   * Crucially, if `primary_id_[type] == mapped_id`, it resets `primary_id_[type] = kInvalidId`. Any remaining active pointers of `type` do *not* inherit `primary_id_[type]`; they remain non-primary until all sessions complete or a new primary assignment occurs when `id_count_[type] == 0`.

---

## 3. Formal Specification in Rocq / Coq (`BlinkPointerEventIdentifierTrackingSemantics.v`)

Below is the complete, self-contained Rocq/Coq formalization of `PointerEventFactory`'s identifier allocation, lifecycle management, and primary pointer tracking. It models both the per-modality structural state and the concrete active pointer list, proving the core mathematical property: **at most 1 active pointer is designated as `isPrimary`**, alongside bi-directional mapping injectivity and monotonic fresh ID generation.

```coq
(** * BlinkPointerEventIdentifierTrackingSemantics.v
    Formal verification of Chromium Blink's PointerEventFactory
    (third_party/blink/renderer/core/events/pointer_event_factory.cc)
    Specification: W3C Pointer Events Level 3, Section 5
*)

From Coq Require Import Bool.Bool.
From Coq Require Import Arith.PeanoNat.
From Coq Require Import Lists.List.
From Coq Require Import ZArith.ZArith.
From Coq Require Import micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Fundamental Types and Constants *)

(** Platform raw identifier from OS/compositor input event *)
Definition RawId := Z.

(** DOM-exposed PointerEvent.pointerId *)
Definition PointerId := Z.

Definition kInvalidId : PointerId := 0.
Definition kMouseId   : PointerId := 1.
Definition kFirstNonMouseId : PointerId := 2.

(** Active pointer record stored in the factory's tracking table *)
Record ActivePointer := mkActivePointer {
  ap_pointer_id  : PointerId;
  ap_raw_id      : RawId;
  ap_is_primary  : bool;
  ap_active_btns : bool;
  ap_hovering    : bool
}.

(** State of the PointerEventFactory for a given pointer modality (e.g., Touch or Pen),
    or unified single-modality slice. *)
Record FactoryState := mkFactoryState {
  fs_next_id        : PointerId;
  fs_primary_id     : PointerId;
  fs_active_list    : list ActivePointer
}.

(** Initial empty state of the factory *)
Definition init_factory_state : FactoryState := {|
  fs_next_id     := kFirstNonMouseId;
  fs_primary_id  := kInvalidId;
  fs_active_list := []
|}.

(** ** 2. Lookup and Filtering Operations *)

Fixpoint find_by_raw_id (r : RawId) (l : list ActivePointer) : option ActivePointer :=
  match l with
  | [] => None
  | p :: ps => if Z.eqb (ap_raw_id p) r then Some p else find_by_raw_id r ps
  end.

Fixpoint find_by_pointer_id (pid : PointerId) (l : list ActivePointer) : option ActivePointer :=
  match l with
  | [] => None
  | p :: ps => if Z.eqb (ap_pointer_id p) pid then Some p else find_by_pointer_id pid ps
  end.

Fixpoint update_or_keep_pointer
  (r : RawId) (btns hover : bool) (l : list ActivePointer) : list ActivePointer :=
  match l with
  | [] => []
  | p :: ps =>
      if Z.eqb (ap_raw_id p) r then
        {| ap_pointer_id  := ap_pointer_id p;
           ap_raw_id      := ap_raw_id p;
           ap_is_primary  := ap_is_primary p;
           ap_active_btns := btns;
           ap_hovering    := hover |} :: update_or_keep_pointer r btns hover ps
      else
        p :: update_or_keep_pointer r btns hover ps
  end.

Fixpoint remove_by_pointer_id (pid : PointerId) (l : list ActivePointer) : list ActivePointer :=
  match l with
  | [] => []
  | p :: ps =>
      if Z.eqb (ap_pointer_id p) pid then
        remove_by_pointer_id pid ps
      else
        p :: remove_by_pointer_id pid ps
  end.

Fixpoint count_primary (l : list ActivePointer) : nat :=
  match l with
  | [] => 0%nat
  | p :: ps =>
      if ap_is_primary p then S (count_primary ps) else count_primary ps
  end.

(** ** 3. Blink PointerEventFactory State Transitions *)

(** Models PointerEventFactory::AddOrUpdateIdAndActiveButtons *)
Definition on_pointer_incoming
  (st : FactoryState) (r : RawId) (btns hover : bool) : FactoryState :=
  match find_by_raw_id r (fs_active_list st) with
  | Some _ =>
      (* Existing active pointer: update attributes, preserve pointerId and isPrimary *)
      {| fs_next_id     := fs_next_id st;
         fs_primary_id  := fs_primary_id st;
         fs_active_list := update_or_keep_pointer r btns hover (fs_active_list st) |}
  | None =>
      (* Fresh pointer session *)
      let new_pid := fs_next_id st in
      let is_prim :=
        match fs_active_list st with
        | [] => Z.eqb (fs_primary_id st) kInvalidId
        | _ :: _ => false
        end in
      let new_primary_id :=
        if is_prim then new_pid else fs_primary_id st in
      let new_entry := {|
        ap_pointer_id  := new_pid;
        ap_raw_id      := r;
        ap_is_primary  := is_prim;
        ap_active_btns := btns;
        ap_hovering    := hover
      |} in
      {| fs_next_id     := new_pid + 1;
         fs_primary_id  := new_primary_id;
         fs_active_list := new_entry :: fs_active_list st |}
  end.

(** Models PointerEventFactory::Remove *)
Definition on_pointer_remove (st : FactoryState) (pid : PointerId) : FactoryState :=
  let new_list := remove_by_pointer_id pid (fs_active_list st) in
  let new_prim :=
    if Z.eqb (fs_primary_id st) pid then kInvalidId else fs_primary_id st in
  {| fs_next_id     := fs_next_id st;
     fs_primary_id  := new_prim;
     fs_active_list := new_list |}.

(** ** 4. Inductive Reachability and Well-Formedness Invariants *)

Inductive Action : Type :=
  | ActIncoming (r : RawId) (btns hover : bool)
  | ActRemove (pid : PointerId).

Definition step (st : FactoryState) (a : Action) : FactoryState :=
  match a with
  | ActIncoming r btns hover => on_pointer_incoming st r btns hover
  | ActRemove pid => on_pointer_remove st pid
  end.

Inductive Reachable : FactoryState -> Prop :=
  | ReachInit : Reachable init_factory_state
  | ReachStep : forall st a,
      Reachable st -> Reachable (step st a).

(** Structural invariant connecting fs_primary_id, fs_next_id, and fs_active_list *)
Definition FactoryInvariant (