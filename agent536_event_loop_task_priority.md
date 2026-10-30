# Formal Verification Report: Blink Event Loop Microtask Draining Semantics

**Target File:** `third_party/blink/renderer/platform/scheduler/main_thread/main_thread_scheduler_impl.cc`  
**Formal Artifact:** `BlinkEventLoopMicrotaskDrainingSemantics.v`  
**Specification Reference:** WHATWG HTML Standard §8.1.7.2 (Processing model) & §8.1.7.3 (Perform a microtask checkpoint)  
**Mathematical Property:** Microtask queue cardinality must converge to $0$ prior to the dispatch of any subsequent macrotask ($\forall \sigma_i \to \sigma_{i+1} \in \text{MacroDispatch}, |\text{microtasks}(\sigma_i)| = 0$).

---

## 1. Normative Specification Requirements

In the WHATWG HTML Standard §8.1.7 ("Event loops"), an **event loop** coordinates execution across browsing contexts, workers, and worklets by managing **task queues** (conceptually sets of macrotasks) and a **microtask queue**.

### 1.1 Event Loop Processing Model (§8.1.7.2)
An event loop continually runs through the following critical phases during a single iteration of its processing loop:
1. **Select Runnable Task:** Let *taskQueue* be one of the event loop's task queues, chosen in an implementation-defined manner, containing at least one runnable task. If there is no such task queue, jump to the microtasks step.
2. **Pop Macrotask:** Let *oldestTask* be the first runnable task in *taskQueue*, and remove it from *taskQueue*.
3. **Execute Macrotask:** Set the event loop's currently running task to *oldestTask*, perform its steps, and subsequently reset the currently running task back to null.
4. **Microtask Checkpoint:** **Perform a microtask checkpoint.**
5. **Update the Rendering:** If it is a window event loop, run rendering, layout, and animation frame callbacks (which also trigger internal microtask checkpoints).

### 1.2 Performing a Microtask Checkpoint (§8.1.7.3)
When the user agent is to *perform a microtask checkpoint*:
1. If the event loop's **performing a microtask checkpoint** flag is true, then return (preventing re-entrant draining).
2. Set the event loop's **performing a microtask checkpoint** flag to true.
3. **While** the event loop's microtask queue is **not empty**:
   a. Let *oldestMicrotask* be the result of dequeuing from the microtask queue.
   b. Set the event loop's currently running task to *oldestMicrotask*.
   c. Run *oldestMicrotask*. (*Note: Running a microtask may enqueue further microtasks, such as Promise reactions or WebAssembly async compilation resolutions, onto the exact same microtask queue.*)
   d. Set the event loop's currently running task back to null.
4. Notify environment settings objects of rejected promises and cleanup IndexedDB transactions.
5. Set the **performing a microtask checkpoint** flag to false.

**Normative Invariant:** Because step 4 of the event loop processing model invokes §8.1.7.3 unconditionally after every macrotask execution, and §8.1.7.3 loops until the microtask queue is completely empty (including newly enqueued microtasks), **no subsequent macrotask can begin execution while the microtask queue length is greater than 0**, assuming termination of the microtask checkpoint.

---

## 2. Blink Implementation & Invariants

In Chromium's Blink engine, the scheduling architecture is mediated by `blink::scheduler::MainThreadSchedulerImpl` (`third_party/blink/renderer/platform/scheduler/main_thread/main_thread_scheduler_impl.cc`), interacting with `base::sequence_manager::SequenceManager` and V8's `v8::MicrotaskQueue`.

### 2.1 Execution Pipeline in `main_thread_scheduler_impl.cc`
Blink implements the HTML Event Loop task lifecycle via `SequenceManager::TaskObserver` callbacks registered on the main thread scheduler:

```cpp
void MainThreadSchedulerImpl::WillProcessTask(
    const base::PendingTask& pending_task,
    bool was_blocked_or_low_priority) {
  // Sets up task state, updates renderer task type, tracks nesting level.
  // ...
}

void MainThreadSchedulerImpl::DidProcessTask(
    const base::PendingTask& pending_task) {
  // ...
  // Enforces the HTML §8.1.7.2 Step 4 Microtask Checkpoint
  if (isolate()) {
    // Dispatches to EventLoop::PerformMicrotaskCheckpoint() / 
    // v8::MicrotasksScope::PerformCheckpoint(isolate())
    PerformMicrotaskCheckpoint();
  }
  // Updates task queues, priority anti-starvation, and compositor state.
}
```

### 2.2 `PerformMicrotaskCheckpoint()` Mechanics
Inside `MainThreadSchedulerImpl::PerformMicrotaskCheckpoint()`:
1. **Re-entrancy Guard & Nesting Level:** Blink checks `v8::MicrotasksScope::IsRunningMicrotasks(isolate())` and ensures the JavaScript execution stack is empty (unless under explicit `kDoNotRunMicrotasks` scope policies).
2. **V8 Microtask Draining:** Blink delegates to ` blink::EventLoop::PerformMicrotaskCheckpoint()`, which invokes `v8_microtask_queue->PerformCheckpoint(isolate())`.
3. **Iterative Exhaustion:** V8's `MicrotaskQueue::RunMicrotasks(Isolate* isolate)` executes a `while (size() > 0)` loop. If a WebAssembly `WebAssembly.instantiate()` promise resolves or a worklet message port triggers a microtask that schedules another `queueMicrotask()`, `size()` dynamically grows and shrinks during the loop, terminating only when `size() == 0` or an unrecoverable termination exception occurs.

### 2.3 Architectural Invariants
* **Invariant $\mathcal{I}_1$ (Post-Task Checkpoint Enforcement):** Every top-level macrotask dispatched by `SequenceManager` invokes `MainThreadSchedulerImpl::DidProcessTask` immediately upon completion.
* **Invariant $\mathcal{I}_2$ (Exhaustive Draining):** `PerformMicrotaskCheckpoint` does not yield control back to `SequenceManager::SelectNextTask` until the active `v8::MicrotaskQueue` reports `GetMicrotasksScopeDepth() == 0` and queue length $0$.
* **Invariant $\mathcal{I}_3$ (Pre-Task Clean Slate):** Assuming initial state $|\mu_0| = 0$ and that external threads (e.g., Worker/Worklet threads or IO threads) can only post *macrotasks* to the `SequenceManager` (never directly mutating the thread-local V8 `MicrotaskQueue`), any newly selected macrotask in `WillProcessTask` observes $|\mu| = 0$.

---

## 3. Formal Specification in Rocq / Coq

Below is the complete, self-contained formalization of the Blink Main Thread Scheduler's macrotask/microtask execution semantics. The file `BlinkEventLoopMicrotaskDrainingSemantics.v` models dynamic microtask spawning during both macrotask execution and microtask draining, utilizing a fuel-bounded execution engine to capture total correctness under termination.

```coq
(** * BlinkEventLoopMicrotaskDrainingSemantics.v
    Formal Verification of Chromium Blink Event Loop Microtask Draining
    Source: third_party/blink/renderer/platform/scheduler/main_thread/main_thread_scheduler_impl.cc
    Specification: WHATWG HTML Standard §8.1.7.2 & §8.1.7.3
*)

Require Import Coq.Lists.List.
Require Import Coq.ZArith.ZArith.
Require Import Coq.Sorting.Permutation.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Basic Types and Task Abstractions *)

(** A Microtask models its computational effect on the microtask queue itself:
    when executed, it may dynamically spawn [spawn_micro : nat] new microtasks
    (e.g., Promise.then chains, Wasm async compilation callbacks). *)
Record Microtask : Type := mkMicrotask {
  micro_id : Z;
  spawn_micro : list Z (* List of child microtask IDs spawned when this runs *)
}.

(** A Macrotask represents a PendingTask in Blink's SequenceManager.
    When executed via RunTask, it enqueues a list of initial microtasks. *)
Record Macrotask : Type := mkMacrotask {
  macro_id : Z;
  enqueued_microtasks : list Microtask
}.

(** Phases of the Blink MainThreadSchedulerImpl lifecycle *)
Inductive SchedulerPhase : Type :=
  | PhaseIdle            : SchedulerPhase (* Waiting to select next macrotask *)
  | PhaseWillProcessTask : SchedulerPhase (* Inside WillProcessTask / running macrotask *)
  | PhaseDidProcessTask  : SchedulerPhase (* Inside DidProcessTask before checkpoint *)
  | PhaseDrainingMicro   : SchedulerPhase (* Inside PerformMicrotaskCheckpoint *).

(** Event Loop State modeling MainThreadSchedulerImpl + v8::MicrotaskQueue *)
Record EventLoopState : Type := mkState {
  phase : SchedulerPhase;
  macro_queue : list Macrotask;
  micro_queue : list Microtask;
  performing_checkpoint : bool;
  completed_macros : list Z;
  completed_micros : list Z
}.

(** ** 2. State Predicates and Observers *)

Definition micro_queue_len (st : EventLoopState) : Z :=
  Z.of_nat (length (micro_queue st)).

Definition macro_queue_len (st : EventLoopState) : Z :=
  Z.of_nat (length (macro_queue st)).

(** The fundamental safety property: Whenever a macrotask is about to begin
    (PhaseWillProcessTask) or the loop is ready to pick the next macrotask (PhaseIdle),
    the microtask queue length is strictly 0. *)
Definition MicrotaskDrainedInvariant (st : EventLoopState) : Prop :=
  (phase st = PhaseIdle \/ phase st = PhaseWillProcessTask) ->
  micro_queue_len st = 0.

(** Stronger structural invariant maintained across the entire unified pipeline *)
Definition WellFormedLoopState (st : EventLoopState) : Prop :=
  match phase st with
  | PhaseIdle =>
      micro_queue st = [] /\ performing_checkpoint st = false
  | PhaseWillProcessTask =>
      micro_queue st = [] /\ performing_checkpoint st = false
  | PhaseDidProcessTask =>
      performing_checkpoint st = false
  | PhaseDrainingMicro =>
      performing_checkpoint st = true
  end.

(** ** 3. Operational Semantics of Microtask Draining (§8.1.7.3) *)

(** Single step of executing one microtask from the V8 MicrotaskQueue.
    Note: Newly spawned microtasks here are non-spawning leaves to model
    finite promise chain resolution, or arbitrary pre-constructed trees. *)
Definition step_microtask (m : Microtask) (rest : list Microtask) : list Microtask :=
  let spawned := map (fun id => mkMicrotask id []) (spawn_micro m) in
  rest ++ spawned.

(** Bounded fuel execution of v8::MicrotaskQueue::PerformCheckpoint.
    Returns (Some final_completed_micros) if the queue fully drains within [fuel] steps,
    or None if fuel is exhausted before draining completes. *)
Fixpoint drain_microtasks_fuel (fuel : nat) (q : list Microtask) (acc_done : list Z)
  : option (list Microtask * list Z) :=
  match q with
  | [] => Some ([], acc_done)
  | m :: rest =>
      match fuel with
      | O => None (* Out of fuel: non-terminating microtask loop *)
      | S fuel' =>
          let next_q := step_microtask m rest in
          drain_microtasks_fuel fuel' next_q (acc_done ++ [micro_id m])
      end
  end.

(** Blink's PerformMicrotaskCheckpoint transition in DidProcessTask *)
Definition perform_microtask_checkpoint (fuel : nat) (st : EventLoopState)
  : option EventLoopState :=
  if performing_checkpoint st then
    (* HTML §8.1.7.3 Step 1: Re-entrancy guard *)
    Some st
  else
    match drain_microtasks_fuel fuel (micro_queue st) (completed_micros st) with
    | Some (remaining_micros, done_micros) =>
        Some (mkState
                PhaseIdle
                (macro_queue st)
                remaining_micros
                false
                (completed_macros st)
                done_micros)
    | None => None
    end.

(** ** 4. Blink MainThreadSchedulerImpl Lifecycle Transitions *)

(** Step 1: SequenceManager selects next macrotask and calls WillProcessTask *)
Definition select_next_macrotask (st : EventLoopState) : option EventLoopState :=
  match phase st with
  | PhaseIdle =>
      match macro_queue st with
      | [] => Some st (* No runnable task *)
      | _ :: _ =>
          Some (mkState
                  PhaseWillProcessTask
                  (macro_queue st)
                  (micro_queue st)
                  (performing_checkpoint st)
                  (completed_macros st)
                  (completed_micros st))
      end
  | _ => None
  end.

(** Step 2: Execute the oldest macrotask, which may enqueue microtasks *)
Definition execute_macrotask (st : EventLoopState) : option EventLoopState :=
  match phase st with
  | PhaseWillProcessTask =>
      match macro_queue st with
      | [] => None (* Impossible in well-formed execution *)
      | task :: rest_macros =>
          Some (mkState
                  PhaseDidProcessTask
                  rest_macros
                  (micro_queue st ++ enqueued_microtasks task)
                  false
                  (completed_macros st ++ [macro_id task])
                  (completed_micros st))
      end
  | _ => None
  end.

(** Step 3: MainThreadSchedulerImpl::DidProcessTask triggers microtask checkpoint *)
Definition did_process_task (fuel : nat) (st : EventLoopState) : option EventLoopState :=
  match phase st with
  | PhaseDidProcessTask => perform_microtask_checkpoint fuel st
  | _ => None
  end.

(** Complete atomic macro-turn of the Event Loop (Select -> Execute -> DidProcessTask) *)
Definition run_event_loop_turn (micro_fuel : nat) (st : EventLoopState)
  : option EventLoopState :=
  match select_next_macrotask st with
  | None => None
  | Some st1 =>
      match phase st1 with
      | PhaseIdle => Some st1 (* Macro queue was empty *)
      | PhaseWillProcessTask =>
          match execute_macrotask st1 with
          | None => None
          | Some st2 => did_process_task micro_fuel st2
          end
      | _ => None
      end
  end.

(** Multi-turn execution across [turns] macrotasks *)
Fixpoint run_event_loop (turns : nat) (micro_fuel : nat) (st : EventLoopState)
  : option EventLoopState :=
  match turns with
  | O => Some st
  | S turns' =>