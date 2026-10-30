import os
from pathlib import Path
from google import genai
from google.genai import types

def formalize_scroll_and_grid():
    key = Path("key.txt").read_text().strip()
    client = genai.Client(api_key=key)

    prompt = """
You are a Principal Formal Methods Researcher and Chromium Blink Engineer.

Task:
Formalize the next two high-impact leaf functions identified in our research:
1. `ScrollAlignment::GetScrollOffsetToExpose` (`third_party/blink/renderer/core/scroll/scroll_alignment.cc`)
   - 1D/2D interval intersection and scroll delta calculation with `LayoutUnit` (26.6 fixed point).
   - Alignment modes: `kAlignCenterAlways`, `kAlignTopAlways`, `kAlignBottomAlways`, `kAlignToEdgeIfNeeded`.
   - Corner cases: target larger than visible port (inverting edge preference), clipping to scroll bounds [0, max_scroll].
2. `DistributeExtraSpaceToTrack` (CSS Grid track sizing inner loop from `grid_track_collection.cc` / `grid_layout_algorithm.cc`)
   - Leftover space distribution across unmaximized tracks.
   - Sentinels: `kIndefiniteSize = -64` representing infinite growth limits.
   - Division truncation, remainder tracking, monotonic growth constraint.

Requirements for `BlinkScrollAndGrid.v`:
1. Self-contained Coq implementation using standard library (`From Stdlib Require Import ZArith List Lia Bool.`).
2. Exact 26.6 fixed-point 32-bit saturating `LayoutUnit` arithmetic (`sat_clamp`, `kInt32Min`, `kInt32Max`, `kIndefiniteSize = -64`).
3. For both functions:
   a) Pure mathematical Gallina specification.
   b) Staged parameter specializations:
      - For ScrollAlignment: Specializing on `{block: 'nearest', inline: 'nearest'}` and `{block: 'center'}` when target is already visible (identity 0 scroll delta) vs fully outside.
      - For Grid Track Sizing: Specializing on finite vs infinite growth limits (`kIndefiniteSize`) and single unmaximized track.
   c) Formal equivalence/preservation theorems in Coq (closed with `Qed`, no `admit`).
   d) Executable `Compute` tests inside Coq.

Also:
Document any new obstructions encountered (such as 2D coordinate interval clamping, or integer division remainder starvation in Grid distribution).
"""

    print("Querying gemini-4-argon with thinking budget (low = 1024 tokens)...")
    config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_budget=1024),
        temperature=0.2,
    )

    response = client.models.generate_content(
        model="gemini-4-argon",
        contents=prompt,
        config=config,
    )

    out_path = Path("blink_scroll_grid_output.md")
    out_path.write_text(response.text)
    print(f"Saved output to {out_path}")

if __name__ == "__main__":
    formalize_scroll_and_grid()

