import os
from pathlib import Path
from google import genai
from google.genai import types

def find_blink_leaf_functions():
    key = Path("key.txt").read_text().strip()
    client = genai.Client(api_key=key)

    prompt = """
You are a Principal Software Engineer on the Chromium Blink layout and rendering engine team, and a Formal Methods Researcher.

Context:
We demonstrated that leaf/near-leaf functions in Blink (like `FlexItem::ClampSizeToMinAndMax` and `MinMaxSizes::ClampSizeToMinAndMax` with 26.6 fixed-point `LayoutUnit` arithmetic, boundary conditions, and sentinel values) can be:
1. Formally specified with high precision across imperative (Layer 1), monadic (Layer 2), and pure mathematical (Layer 3) semantics.
2. Verified with machine-checked simulation/equivalence proofs in Coq/Rocq.
3. Scaled down to fast, branchless specialized forms for common CSS regimes via proven parameter specialization.
4. Differentially verified bit-for-bit against native C++.

Task:
Identify 5-7 ideal "leaf" or "near-leaf" functions in Chromium Blink that:
1. Have well-defined, self-contained algorithmic logic (little to no external state or complex object graphs, purely operating on geometry, CSS values, bitmasks, or strings/tokens).
2. Are non-trivial (contain corner cases, saturating/clamping arithmetic, IEEE float vs fixed-point conversions, sentinel values, or subtle branch prioritization).
3. Suffer from performance overhead in Blink's hot rendering/layout/style loop that would greatly benefit from parameter specialization (partial evaluation).
4. Give:
   - Exact source file path in `third_party/blink/renderer/...`
   - Exact C++ signature & return type
   - What the function does & its edge cases (sentinels, saturation, precision)
   - Why it is an ideal candidate for formalization & parameter specialization (e.g. what static parameters collapse the branches)
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

    out_path = Path("blink_leaf_candidates.md")
    out_path.write_text(response.text)
    print(f"Leaf function candidates saved to {out_path}")

if __name__ == "__main__":
    find_blink_leaf_functions()

