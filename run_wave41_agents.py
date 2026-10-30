import os
import time
import concurrent.futures
from google import genai
from google.genai import types

API_KEY = os.environ.get("GEMINI_API_KEY")
if not API_KEY and os.path.exists("key.txt"):
    with open("key.txt", "r") as f:
        API_KEY = f.read().strip()

client = genai.Client(api_key=API_KEY)
MODEL_NAME = "gemini-4-argon"

AGENTS = [
    {
        "id": 561,
        "filename": "agent561_webgpu_buffer_alignment.md",
        "topic": "WebGPU uniform buffer size alignment (size mod 4 == 0)",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_buffer.cc",
        "spec": "WebGPU §6.2",
        "theory": "BlinkWebGPUBufferAlignmentSemantics.v",
        "math": "aligned_size = (size + 3) / 4 * 4; aligned_size mod 4 == 0."
    },
    {
        "id": 562,
        "filename": "agent562_webgpu_buffer_map_state.md",
        "topic": "WebGPU buffer mapping state machine",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_buffer.cc",
        "spec": "WebGPU §6.2.1",
        "theory": "BlinkWebGPUBufferMapStateSemantics.v",
        "math": "map states: unmapped(0), pending(1), mapped(2); unmap resets to unmapped(0)."
    },
    {
        "id": 563,
        "filename": "agent563_webgpu_bind_group_bounds.md",
        "topic": "WebGPU bind group index bounds (index < maxBindGroups)",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_bind_group.cc",
        "spec": "WebGPU §8.2",
        "theory": "BlinkWebGPUBindGroupBoundsSemantics.v",
        "math": "is_valid_bind_group_index(idx, max_groups) = (0 <=? idx) && (idx <? max_groups)."
    },
    {
        "id": 564,
        "filename": "agent564_webgpu_texture_dimension.md",
        "topic": "WebGPU 2D texture dimension bounds",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_texture.cc",
        "spec": "WebGPU §7.1",
        "theory": "BlinkWebGPUTextureDimensionBoundsSemantics.v",
        "math": "valid_texture_dim(w, h, max_dim) = (0 <? w) && (w <=? max_dim) && (0 <? h) && (h <=? max_dim)."
    },
    {
        "id": 565,
        "filename": "agent565_webgpu_mip_level_bounds.md",
        "topic": "WebGPU mip level bounds",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_texture.cc",
        "spec": "WebGPU §7.2",
        "theory": "BlinkWebGPUMipLevelBoundsSemantics.v",
        "math": "mip_level < max_mip_levels; mip_level >= 0."
    },
    {
        "id": 566,
        "filename": "agent566_webgpu_clear_color_clamp.md",
        "topic": "WebGPU render pass clear color clamping",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_render_pass_encoder.cc",
        "spec": "WebGPU §10.1",
        "theory": "BlinkWebGPUClearColorClampingSemantics.v",
        "math": "clamped_channel(c) = min(255, max(0, c)); 0 <= clamped <= 255."
    },
    {
        "id": 567,
        "filename": "agent567_webgpu_depth_stencil_format.md",
        "topic": "WebGPU depth/stencil format compatibility check",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_render_pipeline.cc",
        "spec": "WebGPU §10.2",
        "theory": "BlinkWebGPUDepthStencilFormatSemantics.v",
        "math": "has_depth(format), has_stencil(format) boolean predicates sound."
    },
    {
        "id": 568,
        "filename": "agent568_webgpu_workgroup_count_bounds.md",
        "topic": "WebGPU compute pass workgroup count bounds",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_compute_pass_encoder.cc",
        "spec": "WebGPU §11.1",
        "theory": "BlinkWebGPUWorkgroupCountBoundsSemantics.v",
        "math": "valid_workgroups(x, y, z, max_wg) = (0 <=? x) && (x <=? max_wg) && ...;"
    },
    {
        "id": 569,
        "filename": "agent569_webgpu_command_buffer_state.md",
        "topic": "WebGPU command buffer state machine",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_command_buffer.cc",
        "spec": "WebGPU §9.1",
        "theory": "BlinkWebGPUCommandBufferStateSemantics.v",
        "math": "states: recording(0) -> ready(1) -> submitted(2); submitted is terminal."
    },
    {
        "id": 570,
        "filename": "agent570_webgpu_queue_submission_monotonic.md",
        "topic": "WebGPU queue submission timestamp monotonicity",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_queue.cc",
        "spec": "WebGPU §13.1",
        "theory": "BlinkWebGPUQueueSubmissionMonotonicitySemantics.v",
        "math": "submission_id(n + 1) > submission_id(n); strictly monotonic."
    },
    {
        "id": 571,
        "filename": "agent571_webgpu_query_set_bounds.md",
        "topic": "WebGPU query set index bounds",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_query_set.cc",
        "spec": "WebGPU §14.1",
        "theory": "BlinkWebGPUQuerySetIndexBoundsSemantics.v",
        "math": "valid_query_index(idx, count) = (0 <=? idx) && (idx <? count)."
    },
    {
        "id": 572,
        "filename": "agent572_webgpu_shader_compilation_boolean.md",
        "topic": "WebGPU shader compilation error boolean consistency",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_shader_module.cc",
        "spec": "WebGPU §12.1",
        "theory": "BlinkWebGPUShaderCompilationStatusSemantics.v",
        "math": "is_valid_module = negb has_compilation_errors."
    },
    {
        "id": 573,
        "filename": "agent573_webgpu_pipeline_layout_compat.md",
        "topic": "WebGPU pipeline layout binding compatibility check",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_pipeline_layout.cc",
        "spec": "WebGPU §8.1",
        "theory": "BlinkWebGPUPipelineLayoutCompatibilitySemantics.v",
        "math": "binding_compatible(layout_type, resource_type) = (layout_type =? resource_type)."
    },
    {
        "id": 574,
        "filename": "agent574_webgpu_sampler_address_mode.md",
        "topic": "WebGPU sampler address mode",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_sampler.cc",
        "spec": "WebGPU §7.3",
        "theory": "BlinkWebGPUSamplerAddressModeSemantics.v",
        "math": "address modes: clamp-to-edge(0), repeat(1), mirror-repeat(2)."
    },
    {
        "id": 575,
        "filename": "agent575_webgpu_vertex_stride_alignment.md",
        "topic": "WebGPU vertex buffer stride 4-byte alignment",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_render_pipeline.cc",
        "spec": "WebGPU §10.3",
        "theory": "BlinkWebGPUVertexStrideAlignmentSemantics.v",
        "math": "is_valid_stride(stride) = (stride mod 4 =? 0) && (stride <=? 2048)."
    },
    {
        "id": 576,
        "filename": "agent576_webgpu_device_loss_terminal.md",
        "topic": "WebGPU device loss state terminal irreversibility",
        "source": "third_party/blink/renderer/modules/webgpu/gpu_device.cc",
        "spec": "WebGPU §5.1",
        "theory": "BlinkWebGPUDeviceLossTerminalSemantics.v",
        "math": "device_lost(st) = (st =? 1); once lost, device cannot transition back to active."
    }
]

def run_agent(agent):
    prompt = f"""You are a formal methods expert and WebGPU graphics pipeline researcher analyzing Chromium Blink's WebGPU architecture.
Topic: {agent['topic']}
Chromium Source: {agent['source']}
Specification: {agent['spec']}
Formal Theory Target: {agent['theory']}
Mathematical Property: {agent['math']}

Write a comprehensive research report in Markdown covering:
1. Exact normative W3C WebGPU specification requirements.
2. Blink implementation details and invariants in {agent['source']}.
3. Formal specification definitions in Rocq/Coq (types, functions, predicates).
4. Concrete theorems with complete, admitted-free Rocq/Coq proofs using ZArith/Lia/Bool.
5. Verification analysis proving 0 admits and preservation of GPU pipeline safety.

Respond with the report in Markdown format."""

    config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_budget=2048),
        max_output_tokens=3500,
        temperature=0.2,
    )
    
    t0 = time.time()
    try:
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=prompt,
            config=config,
        )
        duration = time.time() - t0
        content = response.text
        with open(agent["filename"], "w") as f:
            f.write(content)
        
        usage = response.usage_metadata
        prompt_tokens = usage.prompt_token_count if usage else 0
        cand_tokens = usage.candidates_token_count if usage else 0
        print(f"[Agent {agent['id']}] Done in {duration:.1f}s | tokens: in={prompt_tokens}, out={cand_tokens}")
        with open("token_usage.log", "a") as f:
            f.write(f"Wave41-Agent{agent['id']},{MODEL_NAME},{prompt_tokens},{cand_tokens},{duration:.2f}\n")
        return True
    except Exception as e:
        print(f"[Agent {agent['id']}] FAILED: {e}")
        return False

print(f"Launching 16 concurrent agents for Wave 41 using {MODEL_NAME}...")
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
    futures = [executor.submit(run_agent, agent) for agent in AGENTS]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

print(f"Wave 41 complete: {sum(results)}/16 succeeded.")
