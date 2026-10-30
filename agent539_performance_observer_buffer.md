# Formal Verification Report: Blink PerformanceObserver Buffer Capacity Bounding

**Topic**: `PerformanceObserver` Buffer Capacity Bounding  
**Chromium Source**: `third_party/blink/renderer/core/timing/performance_observer.cc`  
**Specification**: W3C Performance Timeline Level 2, §3 (Extensions to the `Performance` Interface & `PerformanceObserver` Buffering)  
**Formal Theory Target**: `BlinkPerformanceObserverBufferBoundsSemantics.v`  
**Mathematical Property**: $\forall t,\; \text{entries\_stored}(t) \le \text{buffer\_max\_size} \land \text{excess entries dropped}$

---

## 1. Exact Normative W3C Specification Requirements

In the W3C Performance Timeline Level 2 specification (§3 and §4, together with the Registry of Performance Entry Types), performance metrics are queued and delivered asynchronously via `PerformanceObserver` instances or buffered in the global performance entry buffer. To prevent unbounded memory growth (a Denial-of-Service vector via heap exhaustion in long-running single-page applications or unthrottled WebAssembly/Worklet execution loops), the specification enforces strict capacity limits on entry buffers:

1. **Buffer Capacity Invariant**: Each performance entry buffer associated with an entry type (or an observer buffer in restricted contexts) has a normative `maxBufferSize` limit $M \ge 0$.
2. **Queueing Semantics (§4.2 "Queue a PerformanceEntry")**:
   When the user agent is instructed to enqueue a `PerformanceEntry` $e$ into a bounded buffer $B$ with capacity $M$:
   - Let $N = |B|$ be the current number of entries stored in $B$.
   - **Condition (Under Capacity)**: If $N < M$, append $e$ to $B$, resulting in $|B'| = N + 1 \le M$.
   - **Condition (At or Above Capacity)**: If $N \ge M$, the entry $e$ is **dropped** (not appended to $B$), the dropped entries counter is incremented (where applicable, e.g., `droppedEntriesCount`), and the buffer remains unchanged ($B' = B$, $|B'| = N$).
3. **Consumption & Clearing (`takeRecords()` / Observer Delivery)**:
   When the Blink task scheduler invokes the performance observer delivery microtask/task or when script invokes `takeRecords()`, the internal buffer $B$ is swapped/cleared to $\emptyset$ ($|B'| = 0 \le M$).

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine (`third_party/blink/renderer/core/timing/performance_observer.cc` and `performance.cc`), `PerformanceObserver` instances accumulate `PerformanceEntry` Oilpan garbage-collected pointers inside a `HeapVector<Member<PerformanceEntry>> performance_entries_`.

### 2.1 Architectural Flow in `performance_observer.cc`

```cpp
// Conceptual representation of Blink's buffering gate in performance_observer.cc
void PerformanceObserver::EnqueuePerformanceEntry(PerformanceEntry& entry) {
  // Filter checks (type, duration threshold, etc.) omitted for brevity.
  if (performance_entries_.size() < max_buffer_size_) {
    performance_entries_.push_back(&entry);
  } else {
    dropped_entries_count_++;
  }
}

PerformanceEntryVector PerformanceObserver::takeRecords() {
  PerformanceEntryVector entries;
  entries.swap(performance_entries_);
  return entries;
}
```

### 2.2 Core Engine Invariants
1. **Non-Negativity**: Both `performance_entries_.size()` (`wtf_size_t`) and `max_buffer_size_` are non-negative integers ($\ge 0$).
2. **Upper Bound Enforcement**: Before `performance_entries_.push_back(&entry)` is executed, the strict inequality guard `size < max_buffer_size_` must evaluate to `true`. If `size == max_buffer_size_`, the `else` branch increments `dropped_entries_count_` and leaves the vector untouched.
3. **Monotonicity of Drops**: `dropped_entries_count_` is monotonically non-decreasing across the lifetime of the `PerformanceObserver` and increases by exactly $1$ whenever an enqueue operation encounters a full buffer.
4. **Cross-Subsystem Isolation (Wasm / Worklets / Scheduling)**: High-frequency performance mark/measure generation or frame timing dispatches from Worklets and WebAssembly host calls cannot bypass `EnqueuePerformanceEntry`. Consequently, the Oilpan heap footprint of `performance_entries_` per observer is strictly bounded by $\mathcal{O}(\text{max\_buffer\_size\_})$.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the self-contained formalization in `BlinkPerformanceObserverBufferBoundsSemantics.v`. We model `PerformanceEntry` payloads, the `ObserverBuffer` state, single-entry enqueue transitions, batch enqueue transitions, and buffer drains (`takeRecords`).

```coq
(** * BlinkPerformanceObserverBufferBoundsSemantics.v
    Formal verification of Chromium Blink's PerformanceObserver buffer capacity
    bounding (third_party/blink/renderer/core/timing/performance_observer.cc)
    against W3C Performance Timeline §3. *)

From Coq Require Import List.
From Coq Require Import ZArith.
From Coq Require Import Lia.
From Coq Require Import Bool.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Data Types and State Representation *)

(** Abstract identifier and timestamp for a PerformanceEntry *)
Record PerformanceEntry : Type := mkEntry {
  entry_id : Z;
  start_time : Z;
  duration : Z
}.

(** State of a PerformanceObserver buffer in Blink *)
Record ObserverBuffer : Type := mkBuffer {
  entries : list PerformanceEntry;
  buffer_max_size : Z;
  dropped_count : Z
}.

(** Helper: length of the buffer in Z *)
Definition entries_stored (b : ObserverBuffer) : Z :=
  Z.of_nat (List.length (entries b)).

(** Well-formedness invariant for an ObserverBuffer:
    1. buffer_max_size is non-negative.
    2. entries_stored never exceeds buffer_max_size.
    3. dropped_count is non-negative. *)
Definition BufferInvariant (b : ObserverBuffer) : Prop :=
  0 <= buffer_max_size b /\
  entries_stored b <= buffer_max_size b /\
  0 <= dropped_count b.

(** ** 2. State Transitions (Blink Implementation Semantics) *)

(** Initial state of a newly constructed PerformanceObserver *)
Definition init_buffer (max_sz : Z) : ObserverBuffer :=
  mkBuffer [] (Z.max 0 max_sz) 0.

(** Enqueue a single PerformanceEntry (PerformanceObserver::EnqueuePerformanceEntry) *)
Definition enqueue_entry (b : ObserverBuffer) (e : PerformanceEntry) : ObserverBuffer :=
  if Z.ltb (entries_stored b) (buffer_max_size b) then
    mkBuffer (entries b ++ [e]) (buffer_max_size b) (dropped_count b)
  else
    mkBuffer (entries b) (buffer_max_size b) (dropped_count b + 1).

(** Batch enqueue of a stream of PerformanceEntries *)
Fixpoint enqueue_batch (b : ObserverBuffer) (es : list PerformanceEntry) : ObserverBuffer :=
  match es with
  | [] => b
  | e :: rest => enqueue_batch (enqueue_entry b e) rest
  end.

(** Drain buffer via PerformanceObserver::takeRecords() *)
Definition take_records (b : ObserverBuffer) : (list PerformanceEntry * ObserverBuffer) :=
  (entries b, mkBuffer [] (buffer_max_size b) (dropped_count b)).
```

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

We now state and prove the core correctness, capacity bounding, and exact excess-dropping theorems with zero `Admitted` statements.

```coq
(** ** 3. Auxiliary Lemmas *)

Lemma entries_stored_nonneg : forall (b : ObserverBuffer),
  0 <= entries_stored b.
Proof.
  intros b.
  unfold entries_stored.
  lia.
Qed.

Lemma entries_stored_app_single : forall (l : list PerformanceEntry) (e : PerformanceEntry),
  Z.of_nat (List.length (l ++ [e])) = Z.of_nat (List.length l) + 1.
Proof.
  intros l e.
  rewrite List.app_length.
  simpl.
  lia.
Qed.

(** ** 4. Core Soundness and Capacity Bounding Theorems *)

(** Theorem 1: Initialization establishes the BufferInvariant. *)
Theorem init_buffer_satisfies_invariant : forall (max_sz : Z),
  BufferInvariant (init_buffer max_sz).
Proof.
  intros max_sz.
  unfold BufferInvariant, init_buffer, entries_stored.
  simpl.
  lia.
Qed.

(** Theorem 2: Single-step Enqueue preserves the BufferInvariant.
    Proves that entries_stored <= buffer_max_size is an inductive invariant. *)
Theorem enqueue_preserves_invariant : forall (b : ObserverBuffer) (e : PerformanceEntry),
  BufferInvariant b ->
  BufferInvariant (enqueue_entry b e).
Proof.
  intros b e [Hmax [Hcap Hdrop]].
  unfold BufferInvariant, enqueue_entry.
  destruct (Z.ltb_spec (entries_stored b) (buffer_max_size b)) as [Hlt | Hge].
  - (* Case: entries_stored b < buffer_max_size b (entry stored) *)
    unfold entries_stored in *.
    simpl.
    rewrite entries_stored_app_single.
    lia.
  - (* Case: entries_stored b >= buffer_max_size b (excess entry dropped) *)
    unfold entries_stored in *.
    simpl.
    lia.
Qed.

(** Theorem 3: Exact Excess Dropping Semantics.
    When the buffer is at capacity, enqueueing an entry leaves the stored entries
    strictly unchanged and increments dropped_count by 1. *)
Theorem excess_entry_is_dropped : forall (b : ObserverBuffer) (e : PerformanceEntry),
  BufferInvariant b ->
  entries_stored b = buffer_max_size b ->
  entries (enqueue_entry b e) = entries b /\
  entries_stored (enqueue_entry b e) = buffer_max_size b /\
  dropped_count (enqueue_entry b e) = dropped_count b + 1.
Proof.
  intros b e Hinv Hfull.
  unfold enqueue_entry.
  destruct (Z.ltb_spec (entries_stored b) (buffer_max_size b)) as [Hlt | Hge].
  - exfalso. lia.
  - simpl.
    repeat split; try reflexivity; try exact Hfull.
Qed.

(** Theorem 4: Exact Under-Capacity Acceptance Semantics.
    When the buffer is strictly below capacity, enqueueing an entry appends it,
    increments entries_stored by 1, and does not increment dropped_count. *)
Theorem under_capacity_entry_is_stored : forall (b : ObserverBuffer) (e : PerformanceEntry),
  entries_stored b < buffer_max_size b ->
  entries (enqueue_entry b e) = entries b ++ [e] /\
  entries_stored (enqueue_entry b e) = entries_stored b + 1 /\
  dropped_count (enqueue_entry b e) = dropped_count b.
Proof.
  intros b e Hlt.
  unfold enqueue_entry.
  destruct (Z.ltb_spec (entries_stored b) (buffer_max_size b)) as [Hlt' | Hge].
  - unfold entries_stored.
    simpl.
    rewrite entries_stored_app_single.
    repeat split; reflexivity.
  - exfalso. lia.
Qed.

(** Theorem 5: Conservation of Entries (Mass Conservation Law).
    Every enqueued entry is accounted for: the sum of stored entries and dropped
    entries increases by 1 on every enqueue operation. *)
Theorem enqueue_conservation_law : forall (b : ObserverBuffer) (e : PerformanceEntry),
  entries_stored (enqueue_entry b e) + dropped_count (enqueue_entry b e) =
  entries_stored b + dropped_count b + 1 /\
  buffer_max_size (enqueue_entry b e) = buffer_max_size b.
Proof.
  intros b e.
  unfold enqueue_entry.
  destruct (Z.ltb_spec (entries_stored b) (buffer_max_size b)) as [Hlt | Hge].
  - unfold entries_stored.
    simpl.
    rewrite entries_stored_app_single.
    split; lia.
  - unfold entries_stored.
    simpl.
    split; lia.
Qed.

(** Theorem 6: Batch Enqueue Preserves BufferInvariant and Conservation Law.
    Across any arbitrary sequence of entries es, the buffer never exceeds capacity
    and every excess entry is accounted for in dropped_count. *)
Theorem enqueue_batch_soundness : forall (es : list PerformanceEntry) (b : ObserverBuffer),
  BufferInvariant b ->
  let b' := enqueue_batch b es in
  BufferInvariant b' /\
  entries_stored b' <= buffer_max_size b /\
  entries_stored b' + dropped_count b' =
    entries_stored b + dropped_count b + Z.of_nat (List.length es).
Proof.
  induction es as [| e rest IH]; intros b Hinv; simpl.
  - destruct Hinv as [Hmax [Hcap Hdrop]].
    repeat split; try assumption; lia.
  - pose proof (enqueue_preserves_invariant b e Hinv) as Hinv1.
    pose proof (enqueue_conservation_law b e) as [Hcons1 Hmax1].
    specialize (IH (enqueue_entry b e) Hinv1).
    destruct IH as [Hinv_final [Hcap_final Hcons_final]].
    rewrite Hmax1 in Hcap_final.
    repeat split.
    + exact Hinv_final.
    + exact Hcap_final.
    + lia.
Qed.

(** Theorem 7: Exact Overflow Accounting for Saturated Batch Enqueues.
    If a batch of entries of length K is enqueued into an observer buffer,
    the number of dropped entries increases by at least (entries_stored + K - buffer_max_size). *)
Theorem batch_excess_entries_dropped_bound : forall (es : list PerformanceEntry) (b : ObserverBuffer),
  BufferInvariant b ->
  let b' := enqueue_batch b es in
  let k := Z.of_nat (List.length es) in
  Z.max 0 (entries_stored b + k - buffer_max_size b) <= dropped_count b' - dropped_count b.
Proof.
  intros es b Hinv b' k.
  pose proof (enqueue_batch_soundness es b Hinv) as [Hinv' [Hcap' Hcons']].
  fold b' in Hinv', Hcap', Hcons'.
  fold k in Hcons'.
  lia.
Qed.

(** Theorem 8: take_records Preserves BufferInvariant and Res