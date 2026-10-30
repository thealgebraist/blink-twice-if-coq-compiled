# Formal Verification of DedicatedWorker FIFO Task Queue Execution in Chromium Blink

**Formal Theory Target**: `BlinkWorkerTaskQueueFIFOSemantics.v`  
**Chromium Implementation**: `third_party/blink/renderer/core/workers/worker_thread.cc`  
**Normative Specification**: WHATWG HTML Standard §10.2 (The worker's lifetime & Processing model) and §8.1.7 (Event loops)  
**Mathematical Property**: Task execution order within a DedicatedWorker task source is strictly First-In, First-Out (FIFO); `dequeue` extracts the task with the minimal arrival index.

---

## 1. Normative Specification Requirements

According to the WHATWG HTML Standard §10.2 (*Dedicated workers and the DedicatedWorkerGlobalScope interface*) and §8.1.7 (*Event loops*), a DedicatedWorker executes an independent worker event loop isolated from the main document thread.

### 1.1 Event Loop and Task Queues (§8.1.7)
1. **Task Queues as Sets vs. Task Sources as FIFO Queues**: While the HTML Standard notes that "task queues are sets, not queues, because the event loop processing model grabs the first runnable task from the chosen queue, instead of dequeuing the first task", it enforces strict FIFO ordering per **task source**:
   > *"For each event loop, every task source must be associated with a specific task queue... Tasks from the same task source must always be added to the same task queue, and must be processed in the order they were added to that queue."* (§8.1.7.1)
2. **Worker Event Loop Processing Model (§10.2.5)**:
   When a `DedicatedWorkerGlobalScope` is created, its event loop continuously selects the oldest runnable task from its message/control task queues, executes the task's steps to completion (run-to-completion semantics), updates microtask checkpoints, and repeats until the worker's `closing` flag is set or the worker is forcibly terminated.

### 1.2 Mathematical Invariant Required by the Spec
Let $\mathcal{T}$ be the domain of tasks associated with a given task source in a `DedicatedWorker`. Each task $t \in \mathcal{T}$ is assigned a strictly monotonically increasing logical arrival timestamp (or sequence number) $\tau(t) \in \mathbb{Z}_{\ge 0}$ upon being queued. If task $t_1$ is enqueued before $t_2$ ($\tau(t_1) < \tau(t_2)$), then $t_1$ must be dequeued and executed strictly before $t_2$.

---

## 2. Chromium Blink Implementation Analysis

In Chromium's Blink rendering engine, `DedicatedWorker` thread execution and task scheduling are orchestrated by `blink::WorkerThread` (`third_party/blink/renderer/core/workers/worker_thread.cc`) and its underlying `scheduler::WorkerScheduler` (`third_party/blink/renderer/platform/scheduler/worker/worker_scheduler_impl.cc`).

### 2.1 Architecture in `worker_thread.cc`
1. **Backing Thread & Scheduler Creation**:
   `WorkerThread` owns or shares a `WorkerBackingThread`. During initialization (`WorkerThread::InitializeOnWorkerThread`), it constructs a `WorkerScheduler` bound to the thread's `base::sequence_manager::SequenceManager`.
2. **Task Runner Binding**:
   `WorkerThread::GetTaskRunner(TaskType)` maps HTML specification task sources (`TaskType::kPostedMessage`, `TaskType::kWorkerAnimation`, `TaskType::kInternalDefault`, etc.) to underlying `base::sequence_manager::TaskQueue` instances.
3. **FIFO Enqueueing and Sequence Numbers**:
   When `PostTask` is invoked on a worker's `SingleThreadTaskRunner` (e.g., via `WorkerThread::PerformTaskOnWorkerThread` or `PostCrossThreadTask`), `SequenceManager` stamps the `base::PendingTask` with an atomic `enqueue_order` (`base::sequence_manager::EnqueueOrder`), a strictly monotonically increasing 64-bit integer.
4. **Dequeueing Invariant**:
   Within a single `TaskQueue` (and across equal-priority queues sharing a task source), `WorkQueue::TakeTaskFromWorkQueue()` pops from the head of an intrusive heap/ring-buffer ordered strictly by `EnqueueOrder`.

### 2.2 Implementation Invariants
* **Invariant I1 (Monotonic Stamping)**: The worker queue maintains a monotonic counter `next_seq`. Every `enqueue` operation assigns `next_seq` to the incoming task and increments `next_seq` by $1$.
* **Invariant I2 (Sorted Queue Structure)**: The internal task buffer is strictly sorted in ascending order of `arrival_seq` from the head (next to dequeue) to the tail (most recently enqueued).
* **Invariant I3 (Head-Popping Dequeue)**: `dequeue` extracts the element at the head of the queue, guaranteeing that the extracted task has an `arrival_seq` strictly less than all remaining tasks in the queue.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkWorkerTaskQueueFIFOSemantics.v`. It models the task structure, the worker task queue state, the FIFO ordering invariant, and proves that `enqueue` and `dequeue` preserve the invariant and guarantee earliest-arrival execution.

```coq
(** * BlinkWorkerTaskQueueFIFOSemantics.v
    Formal verification of DedicatedWorker FIFO task queue execution
    in Chromium Blink (third_party/blink/renderer/core/workers/worker_thread.cc)
    against WHATWG HTML Standard §10.2. *)

From Coq Require Import ZArith.
From Coq Require Import List.
From Coq Require Import Bool.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Data Types and Queue State *)

(** A Task in WorkerThread's SequenceManager contains a payload ID
    and an arrival sequence number (EnqueueOrder). *)
Record Task : Type := mkTask {
  task_id : Z;
  arrival_seq : Z
}.

(** A WorkerTaskQueue models a single TaskType queue in WorkerScheduler
     junto with the SequenceManager's monotonic sequence generator
    and the trace of executed tasks. *)
Record WorkerTaskQueue : Type := mkQueue {
  pending : list Task;
  next_seq : Z;
  executed_trace : list Task
}.

(** Initial empty worker task queue state. *)
Definition init_queue : WorkerTaskQueue := {|
  pending := [];
  next_seq := 0;
  executed_trace := []
|}.

(** ** 2. Operational Semantics (Enqueue and Dequeue) *)

(** Enqueue a new task with payload [tid] at the tail of the worker queue,
    stamping it with [next_seq] and incrementing [next_seq]. *)
Definition enqueue (tid : Z) (q : WorkerTaskQueue) : WorkerTaskQueue :=
  let t := {| task_id := tid; arrival_seq := q.(next_seq) |} in
  {|
    pending := q.(pending) ++ [t];
    next_seq := q.(next_seq) + 1;
    executed_trace := q.(executed_trace)
  |}.

(** Dequeue the earliest task from the head of the worker queue,
    recording it in the executed trace. *)
Definition dequeue (q : WorkerTaskQueue) : (option Task * WorkerTaskQueue) :=
  match q.(pending) with
  | [] => (None, q)
  | t :: rest =>
      (Some t, {|
        pending := rest;
        next_seq := q.(next_seq);
        executed_trace := q.(executed_trace) ++ [t]
      |})
  end.

(** ** 3. Structural Predicates and Well-Formedness Invariants *)

(** All tasks in list [l] have arrival_seq strictly greater than [bound]. *)
Fixpoint all_gt (bound : Z) (l : list Task) : Prop :=
  match l with
  | [] => True
  | t :: rest => bound < t.(arrival_seq) /\ all_gt bound rest
  end.

(** All tasks in list [l] have arrival_seq strictly less than [limit]. *)
Fixpoint all_lt (limit : Z) (l : list Task) : Prop :=
  match l with
  | [] => True
  | t :: rest => t.(arrival_seq) < limit /\ all_lt limit rest
  end.

(** A list of tasks is strictly sorted by [arrival_seq] in ascending order. *)
Fixpoint strictly_sorted (l : list Task) : Prop :=
  match l with
  | [] => True
  | t :: rest => all_gt t.(arrival_seq) rest /\ strictly_sorted rest
  end.

(** Well-formedness invariant of the WorkerTaskQueue. *)
Definition wf_queue (q : WorkerTaskQueue) : Prop :=
  0 <= q.(next_seq) /\
  strictly_sorted q.(pending) /\
  all_lt q.(next_seq) q.(pending).
```

---

## 4. Concrete Theorems and Complete Proofs

We now prove helper lemmas and the primary verification theorems establishing that:
1. The initial queue is well-formed.
2. `enqueue` preserves `wf_queue`.
3. `dequeue` preserves `wf_queue`.
4. **Core FIFO Property**: Whenever `dequeue` pops a task $t$, $t$ has an `arrival_seq` strictly smaller than every remaining task in the queue (`all_gt t.(arrival_seq) q'.(pending)`).
5. **FIFO Pairwise Execution Order**: Any task $t_1$ enqueued before $t_2$ is guaranteed to be positioned ahead of $t_2$ and popped first.

```coq
(** ** 4. Helper Lemmas for List Invariants *)

Lemma all_gt_app : forall (b : Z) (l1 l2 : list Task),
  all_gt b l1 ->
  all_gt b l2 ->
  all_gt b (l1 ++ l2).
Proof.
  intros b l1 l2 H1 H2.
  induction l1 as [| x xs IH]; simpl in *.
  - exact H2.
  - destruct H1 as [Hx Hxs].
    split.
    + exact Hx.
    + apply IH. exact Hxs.
Qed.

Lemma all_lt_app : forall (lim : Z) (l1 l2 : list Task),
  all_lt lim l1 ->
  all_lt lim l2 ->
  all_lt lim (l1 ++ l2).
Proof.
  intros lim l1 l2 H1 H2.
  induction l1 as [| x xs IH]; simpl in *.
  - exact H2.
  - destruct H1 as [Hx Hxs].
    split.
    + exact Hx.
    + apply IH. exact Hxs.
Qed.

Lemma all_lt_mono : forall (lim1 lim2 : Z) (l : list Task),
  lim1 <= lim2 ->
  all_lt lim1 l ->
  all_lt lim2 l.
Proof.
  intros lim1 lim2 l Hle Hlt.
  induction l as [| x xs IH]; simpl in *.
  - exact I.
  - destruct Hlt as [Hx Hxs].
    split.
    + lia.
    + apply IH. exact Hxs.
Qed.

Lemma strictly_sorted_snoc : forall (l : list Task) (t : Task),
  strictly_sorted l ->
  all_lt t.(arrival_seq) l ->
  strictly_sorted (l ++ [t]).
Proof.
  intros l t Hsort Hlt.
  induction l as [| x xs IH]; simpl in *.
  - split; exact I.
  - destruct Hsort as [Hgt Hsort_xs].
    destruct Hlt as [Hx_lt Hlt_xs].
    split.
    + apply all_gt_app.
      * exact Hgt.
      * simpl. split; [lia | exact I].
    + apply IH; assumption.
Qed.

Lemma all_gt_in : forall (b : Z) (l : list Task) (x : Task),
  all_gt b l ->
  In x l ->
  b < x.(arrival_seq).
Proof.
  intros b l x Hgt Hin.
  induction l as [| y ys IH]; simpl in *.
  - contradiction.
  - destruct Hgt as [Hy Hys].
    destruct Hin as [Heq | Hin_ys].
    + subst x. exact Hy.
    + apply IH; assumption.
Qed.

(** ** 5. Main Verification Theorems *)

(** Theorem 1: The initial queue satisfies the well-formedness invariant. *)
Theorem init_queue_wf : wf_queue init_queue.
Proof.
  unfold wf_queue, init_queue; simpl.
  repeat split; lia.
Qed.

(** Theorem 2: Enqueue preserves the well-formedness invariant. *)
Theorem enqueue_preserves_wf : forall (tid : Z) (q : WorkerTaskQueue),
  wf_queue q ->
  wf_queue (enqueue tid q).
Proof.
  intros tid q Hwf.
  destruct Hwf as [Hseq [Hsort Hlt]].
  unfold wf_queue, enqueue; simpl.
  repeat split.
  - lia.
  - apply strictly_sorted_snoc.
    + exact Hsort.
    + simpl. exact Hlt.
  - apply all_lt_app.
    + apply (all_lt_mono q.(next_seq) (q.(next_seq) + 1)).
      * lia.
      * exact Hlt.
    + simpl. split; [lia | exact I].
Qed.

(** Theorem 3: Dequeue preserves the well-formedness invariant. *)
Theorem dequeue_preserves_wf : forall (q q' : WorkerTaskQueue) (opt_t : option Task),
  wf_queue q ->
  dequeue q = (opt_t, q') ->
  wf_queue q'.
Proof.
  intros q q' opt_t Hwf Hdeq.
  destruct Hwf as [Hseq [Hsort Hlt]].
  unfold dequeue in Hdeq.
  destruct (pending q) as [| t rest] eqn:Hpend.
  - inversion Hdeq; subst.
    unfold wf_queue. rewrite Hpend.
    repeat split; assumption.
  - inversion Hdeq; subst.
    unfold wf_queue; simpl in *.
    destruct Hsort as [_ Hsort_rest].
    destruct Hlt as [_ Hlt_rest].
    repeat split; assumption.
Qed.

(** Theorem 4 (Core Mathematical Property):
    Task execution order is strictly FIFO: dequeue pops the earliest arrival.
    Specifically, if [dequeue] pops task [t] leaving queue [q'], then for EVERY
    remaining task [rem] in [q'], [t.(arrival_seq) < rem.(arrival_seq)]. *)
Theorem dequeue_pops_earliest_arrival :
  forall (q q' : WorkerTaskQueue) (t : Task) (rem : Task),
    wf_queue q ->
    dequeue q = (Some t, q') ->
    