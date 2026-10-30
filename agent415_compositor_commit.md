**AGENT 415 // AUDIT LOG: BLINK COMPOSITOR FRAME COMMIT**
**SUBJECT:** Monotonic Frame Token Progression & Pipeline Verification
**STATUS:** ACTIVE AUDIT

---

### 1. ARCHITECTURAL OVERVIEW
In the Chromium rendering pipeline, the **Frame Token** (`uint32_t`, wrapped as `viz::FrameTokenGenerator` or `blink::LocalFrameToken` depending on the layer, specifically `viz::CompositorFrameMetadata::frame_token`) serves as the cryptographic-like invariant linking a specific Main Thread state (Blink DOM/Layout) to its eventual pixel realization in the GPU Display Compositor (`viz`).

The fundamental invariant under audit is **Strict Monotonicity**: For any sequence of submitted frames $F_1, F_2, ..., F_n$ from a single `LayerTreeHost`, their corresponding tokens $T(F)$ must satisfy:
$$T(F_{n}) > T(F_{n-1})$$

---

### 2. LIFECYCLE & PROGRESSION AUDIT

#### Phase I: Main Thread Commit (`cc::LayerTreeHost`)
1. **Initiation:** The `ProxyMain::BeginMainFrame` triggers Blink to update lifecycle phases ( animations, style, layout, paint).
2. **Token Generation:** Upon completion of painting, `LayerTreeHost::CommitComplete` prepares the synchronization state. The `next_frame_token_` (maintained by `LayerTreeHost`) is incremented via `viz::FrameTokenGenerator`.
3. **Commit Payload:** During `LayerTreeHostImpl::CommitComplete` (executing on the Impl thread during the blocked Main thread phase, or via Non-Blocking Commit), the generated token is copied from the `CommitState` to the `LayerTreeImpl` (specifically the **Pending Tree**).

#### Phase II: Impl Thread Activation (`cc::LayerTreeHostImpl`)
1. **Pending to Active:** The Pending Tree processes rasterization tasks (`TileManager`). The frame token remains bound to the `PendingTree`'s metadata.
2. **Tree Activation:** When rasterization is complete, `ActivateSyncTree()` moves the state to the **Active Tree**. 
3. **No-Op Commits:** *Audit Note:* If a BeginMainFrame results in no visual updates (Commit Abort), the `next_frame_token_` may still advance if Presentation Callbacks or swap promises were requested, requiring synthetic token propagation via `DidNotProduceFrame`.

#### Phase III: Frame Submission (`cc::LayerTreeFrameSink`)
1. **Draw Phase:** `LayerTreeHostImpl::DrawLayers` generates a `viz::CompositorFrame`.
2. **Metadata Binding:** The Active Tree’s frame token is stamped into `CompositorFrameMetadata::frame_token`.
3. **IPC Validation:** The frame is sent over Mojo (`SubmitCompositorFrame`) to the `viz::CompositorFrameSinkSupport` in the GPU process.
4. **Monotonicity Check (CRITICAL AUDIT POINT):** 
   Inside `CompositorFrameSinkSupport::MaybeSubmitCompositorFrame`:
   ```cpp
   if (frame.metadata.frame_token <= last_frame_token_) {
       // VIOLATION DETECTED: Mojo Bad Message / Kill Renderer
       return SubmitResult::FRAME_TOKEN_VIOLATION;
   }
   last_frame_token_ = frame.metadata.frame_token;
   ```
   *Note: Wrapping of the 32-bit unsigned integer is handled via serial number arithmetic (`viz::FrameTokenGT`), though in practice 0 is reserved as `kInvalidFrameToken`.*

#### Phase IV: Display & Feedback (`viz::Display` -> `blink::WidgetBase`)
1. **Surface Aggregation:** `viz::SurfaceAggregator` combines frames. The `frame_token` is tracked inside `Surface::PresentationHelper`.
2. **GPU Swap:** Once the buffer hits the OS compositor/display, `gfx::PresentationFeedback` is generated.
3. **Callback Execution:** `DidPresentCompositorFrame` flows back to the Renderer's `LayerTreeHostImpl` via Mojo, matching the `frame_token` to queued `SwapPromise` and `PresentationTimeCallback` queues.
4. **Pruning:** The Renderer uses the monotonic property to dequeue and resolve all callbacks with tokens $\le$ the presented `frame_token`.

---

### 3. EDGE CASES & ANOMALY VECTORS

As Agent 415, I am flagging the following edge cases where monotonic progression is historically vulnerable during commits:

*   **Impl-Side Invalidations (Checkerboarding/Scrolls):** The Impl thread can generate multiple `CompositorFrames` from a *single* Blink commit (e.g., compositor-driven scrolling). However, `viz` requires *every* submitted `CompositorFrame` to have a strictly increasing token. Therefore, the `FrameTokenGenerator` actually lives in a shared/synchronized manner, or more accurately, `LayerTreeHostImpl` generates the `CompositorFrameMetadata::frame_token` at **Draw** time, while mapping it back to the `source_frame_number` (which tracks the Main Thread commit count).
    *   *Correction/Refinement for Audit:* `source_frame_number` tracks the Main Thread Commit monotonically. `frame_token` tracks the *Impl Thread Frame Submission* monotonically. Blink callbacks register against the `frame_token` allocated *at the time of commit* (stored in `LayerTreeImpl`), which is then consumed on the next draw. Subsequent Impl-only draws increment the `frame_token` independently.
*   **LayerTreeFrameSink Recreation (GPU Crash):** If the GPU process crashes, the `CompositorFrameSink` is lost. Upon recreation, `viz` resets `last_frame_token_` to 0. The Renderer's monotonic progression continues unabated, satisfying $T_{current} > 0$.
*   **32-bit Rollover:** At 120Hz, a `uint32_t` rolls over in ~414 days. Progression checks *must* use RFC 1982 serial number arithmetic:
    ```cpp
    inline bool FrameTokenGT(uint32_t token1, uint32_t token2) {
      // 0 is reserved.
      return (token1 != token2) && ((token1 - token2) < 0x80000000u);
    }
    ```

---

### 4. AUDIT CONCLUSION
Monotonic frame token progression is enforced via `viz::FrameTokenGenerator` at the `LayerTreeHostImpl` boundary, linked to Main Thread commits via `PendingTree` synchronization, and strictly policed by `viz::CompositorFrameSinkSupport` upon IPC ingestion. Any out-of-order commit or race condition in the `ProxyImpl` thread hops will immediately trigger a `MOJO_BAD_MESSAGE` termination of the Blink renderer process.

**END AUDIT LOG // AGENT 415**