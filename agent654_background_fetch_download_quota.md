# Formal Verification Report: Background Fetch `downloadTotal` Non-Negative Quota Bounding

**Agent**: Formal Verification Agent 654 (Web Push, Notifications, Badging & Background Sync)  
**Topic**: Background Fetch `downloadTotal` non-negative quota bounding  
**Chromium Source**: `third_party/blink/renderer/modules/background_fetch/background_fetch_registration.cc`  
**Specification**: WICG Background Fetch API §4.1 (`BackgroundFetchOptions.downloadTotal >= 0`)  
**Formal Theory Target**: `BlinkBackgroundFetchDownloadQuotaSemantics.v`  
**Mathematical Property**: $\text{is\_valid\_download\_total}(\text{tot}) \iff (0 \le \text{tot})$

---

## 1. Exact Normative W3C / WICG Specification Requirements

The Background Fetch API (a WICG specification closely integrated with the W3C Service Workers and Web Background Sync ecosystem) allows web applications to delegate large downloads or uploads to the user agent's background processing engine. Because background fetches operate outside the lifetime of a foreground document and display persistent system UI (similar to Web Notifications), strict resource quota bounding is required to prevent UI spoofing, integer underflow, and storage exhaustion attacks.

### 1.1 WebIDL Interface Definition (§4.1 & §4.3)
In **§4.1 (`BackgroundFetchManager`)** and **§4.3 (`BackgroundFetchRegistration`)**, the `downloadTotal` member is defined using the WebIDL `unsigned long long` type:

```webidl
dictionary BackgroundFetchUIOptions {
  sequence<ImageResource> icons = [];
  DOMString title = "";
};

dictionary BackgroundFetchOptions : BackgroundFetchUIOptions {
  unsigned long long downloadTotal = 0;
};

[Exposed=(Window,Worker)]
interface BackgroundFetchRegistration : EventTarget {
  readonly attribute DOMString id;
  readonly attribute unsigned long long uploadTotal;
  readonly attribute unsigned long long uploaded;
  readonly attribute unsigned long long downloadTotal;
  readonly attribute unsigned long long downloaded;
  readonly attribute BackgroundFetchResult result;
  readonly attribute BackgroundFetchFailureReason failureReason;
  readonly attribute boolean recordsAvailable;

  attribute EventHandler onprogress;

  Promise<boolean> abort();
  Promise<BackgroundFetchRecord> match(RequestInfo request, optional CacheQueryOptions options = {});
  Promise<sequence<BackgroundFetchRecord>> matchAll(optional RequestInfo request, optional CacheQueryOptions options = {});
};
```

### 1.2 Normative Algorithmic Requirements
1. **Non-Negativity via WebIDL (`[EnforceRange]` / `unsigned long long`)**: Per the WebIDL specification for `unsigned long long`, the valid domain is $[0, 2^{64}-1]$. When passed via `BackgroundFetchOptions`, `downloadTotal` defaults to `0` and cannot be negative.
2. **Quota Enforcement during `fetch()` (§4.1.1)**:
   - Let `downloadTotal` be `options["downloadTotal"]`.
   - If `downloadTotal` exceeds the available storage quota for the origin, the user agent **must** reject the registration promise with a `QuotaExceededError` `DOMException`.
3. **Runtime Progress & Quota Enforcement (§3.2.4 "Execute a background fetch")**:
   - A `BackgroundFetchRegistration` has an associated **download total** (an integer, initially 0) and **downloaded** (an integer, initially 0).
   - Whenever bytes are received over the network and appended to `downloaded`:
     - If `downloadTotal > 0` and `downloaded > downloadTotal`, the user agent **must** immediately abort the fetch, set `result` to `"failure"`, set `failureReason` to `"download-total-exceeded"`, and fire a `backgroundfetchfail` event at the Service Worker registration.

---

## 2. Blink Implementation Details and Invariants

In Chromium Blink, `BackgroundFetchRegistration` is implemented in `third_party/blink/renderer/modules/background_fetch/background_fetch_registration.cc` (and its header `.h`), bridging the Blink V8 bindings with the browser process (`content::BackgroundFetchContext`) via Mojo IPC (`blink::mojom::blink::BackgroundFetchRegistrationData`).

### 2.1 C++ Type Representations and IPC Boundary Hazards
In Blink's V8 bindings (`v8_background_fetch_options.h` / `background_fetch_registration.h`), `downloadTotal` and `downloaded` are exposed to JavaScript as `uint64_t`:

```cpp
// third_party/blink/renderer/modules/background_fetch/background_fetch_registration.cc

BackgroundFetchRegistration::BackgroundFetchRegistration(
    ServiceWorkerRegistration* registration,
    mojom::blink::BackgroundFetchRegistrationDataPtr registration_data)
    : registration_(registration),
      developer_id_(registration_data->developer_id),
      upload_total_(registration_data->upload_total),
      uploaded_(registration_data->uploaded),
      download_total_(registration_data->download_total),
      downloaded_(registration_data->downloaded),
      result_(registration_data->result),
      failure_reason_(registration_data->failure_reason) {}

uint64_t BackgroundFetchRegistration::downloadTotal() const {
  return download_total_;
}

uint64_t BackgroundFetchRegistration::downloaded() const {
  return downloaded_;
}
```

### 2.2 Core Blink Invariants
While the Blink C++ getter returns `uint64_t`, the value traverses multiple architectural boundaries:
1. **ECMAScript Number Conversion**: V8 converts `double` values into `uint64_t` during dictionary coercion (`BackgroundFetchOptions`).
2. **Quota Manager Interoperability**: Chromium's `storage::QuotaManager` and SQLite-backed Service Worker database represent byte counts and deltas using signed 64-bit integers (`int64_t`). If a raw 64-bit integer is interpreted across signed/unsigned boundaries without enforcing $0 \le \text{tot}$, values in $[2^{63}, 2^{64}-1]$ wrap to negative `int64_t` values, bypassing quota checks (`downloaded > download_total`).
3. **Progress Monotonicity and Bounding Invariant**:
   In `BackgroundFetchRegistration::DidUpdateUI` and `Update()` (called via `mojom::blink::BackgroundFetchRegistrationObserver::OnProgress`):
   ```cpp
   void BackgroundFetchRegistration::OnProgress(
       uint64_t upload_total,
       uint64_t uploaded,
       uint64_t download_total,
       uint64_t downloaded,
       mojom::BackgroundFetchResult result,
       mojom::BackgroundFetchFailureReason failure_reason) {
     upload_total_ = upload_total;
     uploaded_ = uploaded;
     download_total_ = download_total;
     downloaded_ = downloaded;
     result_ = result;
     failure_reason_ = failure_reason;
     // Fires "progress" event on ExecutionContext
   }
   ```
   For the state transition in `background_fetch_registration.cc` to remain sound:
   - **Invariant I1 (Non-Negative Quota)**: $\forall \text{reg}, \text{reg}.\text{download\_total\_} \ge 0$.
   - **Invariant I2 (Non-Negative Progress)**: $\forall \text{reg}, \text{reg}.\text{downloaded\_} \ge 0$.
   - **Invariant I3 (Quota Exceeded Termination)**: If $\text{download\_total\_} > 0 \land \text{downloaded\_} > \text{download\_total\_}$, the registration state transitions deterministically to `kFailure` with `kDownloadTotalExceeded`.

---

## 3. Formal Specification Definitions in Rocq/Coq

Below is the formalization of `BlinkBackgroundFetchDownloadQuotaSemantics.v`. We model byte counts over $\mathbb{Z}$ (`Z`) to explicitly capture signed/unsigned boundary hazards, IPC sanitization, and runtime progress transitions in `background_fetch_registration.cc`.

### 3.1 Core Domains and Predicates
- `is_valid_download_total (tot : Z) : Prop := 0 <= tot` (Decision procedure: `is_valid_download_total_b (tot : Z) : bool := (0 <=? tot)`).
- `FailureReason`: Models `mojom::BackgroundFetchFailureReason` (`None`, `Aborted`, `BadStatus`, `FetchError`, `QuotaExceeded`, `DownloadTotalExceeded`).
- `FetchResult`: Models `mojom::BackgroundFetchResult` (`Empty`, `Success`, `Failure`).
- `RegistrationState`: Models the internal fields of `blink::BackgroundFetchRegistration`.

---

## 4. Concrete Theorems and Complete Rocq/Coq Proofs

The following Coq script (`BlinkBackgroundFetchDownloadQuotaSemantics.v`) is completely self-contained, uses standard libraries (`ZArith`, `Lia`, `Bool`, `List`), and contains **zero admits**.

```coq
(** * BlinkBackgroundFetchDownloadQuotaSemantics.v
    Formal Verification of Background Fetch downloadTotal Non-Negative Quota Bounding
    Chromium Source: third_party/blink/renderer/modules/background_fetch/background_fetch_registration.cc
    Specification: WICG Background Fetch API §4.1 & §4.3
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.
Require Import Coq.Bool.Bool.
Require Import Coq.Lists.List.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Mathematical Property & Quota Predicates *)

(** Prop-level specification of valid downloadTotal *)
Definition is_valid_download_total (tot : Z) : Prop :=
  0 <= tot.

(** Computational boolean checker corresponding to Blink bindings / IPC validation *)
Definition is_valid_download_total_b (tot : Z) : bool :=
  0 <=? tot.

(** Signed 64-bit integer upper bound for Chromium QuotaManager compatibility *)
Definition kMaxInt64 : Z := 9223372036854775807.

(** Strict 64-bit safe quota bound *)
Definition is_int64_bounded_quota (tot : Z) : Prop :=
  0 <= tot <= kMaxInt64.

(** Clamping/Sanitization function at the WebIDL / Mojo boundary *)
Definition sanitize_download_total (raw_tot : Z) : Z :=
  if raw_tot <? 0 then 0 else raw_tot.

(** ** 2. BackgroundFetchRegistration State Model *)

Inductive FetchResult : Type :=
  | ResultEmpty
  | ResultSuccess
  | ResultFailure.

Inductive FailureReason : Type :=
  | ReasonNone
  | ReasonAborted
  | ReasonBadStatus
  | ReasonFetchError
  | ReasonQuotaExceeded
  | ReasonDownloadTotalExceeded.

Record RegistrationState : Type := mkRegistration {
  reg_upload_total   : Z;
  reg_uploaded       : Z;
  reg_download_total : Z;
  reg_downloaded     : Z;
  reg_result         : FetchResult;
  reg_failure_reason : FailureReason
}.

(** Well-formedness invariant of blink::BackgroundFetchRegistration *)
Definition registration_invariant (st : RegistrationState) : Prop :=
  is_valid_download_total (reg_download_total st) /\
  0 <= reg_downloaded st /\
  0 <= reg_upload_total st /\
  0 <= reg_uploaded st /\
  (reg_download_total st > 0 ->
   reg_downloaded st > reg_download_total st ->
   reg_result st = ResultFailure /\
   reg_failure_reason st = ReasonDownloadTotalExceeded).

(** ** 3. Operational Semantics of Registration Lifecycle *)

(** Initial registration creation in BackgroundFetchRegistration constructor *)
Definition init_registration (upload_tot download_tot : Z) : RegistrationState :=
  mkRegistration
    (sanitize_download_total upload_tot)
    0
    (sanitize_download_total download_tot)
    0
    ResultEmpty
    ReasonNone.

(** Check if a new downloaded byte count violates the declared downloadTotal quota.
    Note: Per §3.2.4, downloadTotal == 0 means the total size is unknown (unbounded by downloadTotal). *)
Definition exceeds_download_total_b (download_tot downloaded : Z) : bool :=
  (0 <? download_tot) && (download_tot <? downloaded).

(** Step function modeling BackgroundFetchRegistration::OnProgress / byte accumulation *)
Definition step_progress (st : RegistrationState) (delta_bytes : Z) : RegistrationState :=
  match reg_result st with
  | ResultEmpty =>
      let clean_delta := if delta_bytes <? 0 then 0 else delta_bytes in
      let new_downloaded := reg_downloaded st + clean_delta in
      if exceeds_download_total_b (reg_download_total st) new_downloaded then
        mkRegistration
          (reg_upload_total st)
          (reg_uploaded st)
          (reg_download_total st)
          new_downloaded
          ResultFailure
          ReasonDownloadTotalExceeded
      else
        mkRegistration
          (reg_upload_total st)
          (reg_uploaded st)
          (reg_download_total st)
          new_downloaded
          ResultEmpty
          ReasonNone
  | _ => st (* Terminal states do not process further progress deltas *)
  end.

(** Multi-step progress trace execution *)
Fixpoint run_progress_trace (st : RegistrationState) (deltas : list Z) : RegistrationState :=
  match deltas with
  | [] => st
  | d :: ds => run_progress_trace (step_progress st d) ds
  end.

(** ** 4. Formal Verification Theorems & Proofs *)

(** Theorem 1: Equivalence between boolean checker and mathematical specification *)
Theorem is_valid_download_total_reflect :
  forall tot : Z,
    is_valid_download_total_b tot = true <-> is_valid_download_total tot.
Proof.
  intros tot.
  unfold is_valid_download_total_b, is_valid_download_total.
  rewrite Z.leb_le.
  reflexivity.
Qed.

(** Theorem 2: Sanitization guarantees a valid non-negative downloadTotal *)
Theorem sanitize_download_total_valid :
  forall raw_tot : Z,
    is_valid_download_total (sanitize_download_total raw_tot).
Proof.
  intros raw_tot.
  unfold is_valid_download_total, sanitize_download_total.
  destruct (raw_tot <? 0) eqn:Hlt.
  - lia.
  - apply Z.ltb_ge in Hlt. lia.
Qed.

(** Theorem 3: Sanitization is idempotent on already-valid downloadTotal values *)
Theorem sanitize_download_total_idempotent :
  forall tot : Z,
    is_valid_download_total tot ->
    sanitize_download_total tot = tot.
Proof.
  intros tot Hvalid.
  unfold is_valid_download_total in Hvalid.
  unfold sanitize_download_total.
  destruct (tot <? 0) eqn:Hlt.
  - apply Z.ltb_lt in Hlt. lia.
  - reflexivity.
Qed.

(** Theorem 4: Constructor initialization establishes the registration invariant *)
Theorem init_registration_establishes_invariant :
  forall upload_tot download