import os
from pathlib import Path
from google import genai
from google.genai import types

def formalize_leaf_functions():
    key = Path("key.txt").read_text().strip()
    client = genai.Client(api_key=key)

    prompt = """
You are a Principal Formal Methods Researcher and Compiler Verification Specialist.

Task:
Formalize the two top leaf functions from Chromium Blink:
1. `MinimumValueForLength` (`third_party/blink/renderer/platform/geometry/length_functions.cc`)
2. `InlineSizeFromAspectRatio` (`third_party/blink/renderer/core/layout/length_utils.cc`)

Requirements for the Coq/Rocq File (`BlinkLeafFunctions.v`):
1. Complete, self-contained Coq implementation compatible with standard library (`From Stdlib Require Import ZArith List Lia.`).
2. Domain Models:
   - Exact 26.6 fixed-point 32-bit saturating `LayoutUnit` (int32 bounds: -2147483648 to 2147483647).
   - Sentinel `kIndefiniteSize = -64`.
   - `Length` inductive type: `Fixed (v : Z)`, `Percent (pct : Z)` (representing percentage 0..100 or scaled), `Auto`, `FillAvailable`.
   - `BoxStrut` record: `block_sum`, `inline_sum`.
   - `LogicalSize` record: `aspect_inline`, `aspect_block`.
   - `EBoxSizing`: `ContentBox` vs `BorderBox`.
   - 64-bit intermediate scaling `MulDiv(val, num, den)` with saturating 32-bit clamping.
3. For each of the two functions:
   a) Provide the pure mathematical Gallina specification.
   b) Formulate Step-by-Step Parameter Specialization (e.g., Fixed length specialization, Percent length with definite container, ContentBox with zero padding, 1:1 aspect ratio).
   c) Prove formal correctness / equivalence theorems for each specialization in Coq (using `Qed`, no `admit`).
   d) Provide `Compute` tests demonstrating reduction and evaluation in Coq.

Please provide:
1. The exact C++ definitions from Chromium Blink.
2. The complete, self-contained Coq file `BlinkLeafFunctions.v` ready to compile with `coqc`.
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

    out_path = Path("blink_leaf_formalization_output.md")
    out_path.write_text(response.text)
    print(f"Saved to {out_path}")

if __name__ == "__main__":
    formalize_leaf_functions()

