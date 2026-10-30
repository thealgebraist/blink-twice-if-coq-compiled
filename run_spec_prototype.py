import os
from pathlib import Path
from google import genai
from google.genai import types

def generate_end_to_end_test():
    key = Path("key.txt").read_text().strip()
    client = genai.Client(api_key=key)

    prompt = """
You are a Principal Formal Methods Researcher and Compiler Verification Specialist.

Goal:
Implement a concrete, working end-to-end prototype of the proposed methodology on an isolated, non-trivial function from Chromium Blink.

Function Selection:
Select a concrete, non-trivial, isolated function from Blink (for example:
`LayoutUnit::ClampNegativeToZero` / saturating operations,
or `FlexItem::ClampSizeToMinAndMax` with `min_size`, `max_size`, and saturating `LayoutUnit` bounds,
or `ScrollOffsetClamping` / `CSSSelectorSpecificity::Calculate` / `Hyphenation::LastHyphenLocation`).
A great candidate is `FlexItem::ClampSizeToMinAndMax` or `LayoutUnit` saturating operations / `ResolveFlexibleLengths` item distribution step with exact fixed-point `LayoutUnit` (6-bit fractional 1/64th px, 32-bit signed saturating integer).

Requirements for the Prototype:
1. Provide the exact Chromium Blink C++ source code snippet (with `LayoutUnit` clamping, mutation, pointers/references, and sentinel checks like `kIndefiniteSize = -1`).
2. Provide the formal Coq (Rocq) implementation:
   a) Imperative C++ AST / Monadic State representation (Layer 1/2) that models the C++ statement execution (variables, conditionals, mutation).
   b) Pure Gallina mathematical specification (Layer 3) representing the intended mathematical behavior.
   c) A formal Coq proof of semantic equivalence / refinement between the imperative representation and the pure specification!
   d) Staged Specialization: Step-by-step specialization with respect to parameters (e.g., when `max_size` is unconstrained / None, or `min_size` is 0), with proven equivalence theorem in Coq.
   e) Executability: Include `Compute` / test evaluations showing that the pure spec and specialized spec compute exact identical results.
3. Provide an extracted or directly verifiable OCaml/Python/C test harness demonstrating differential execution against the C++ code on test vectors (boundary cases: 0, negative values, saturated bounds, sentinels).
4. Ensure the Coq (.v) code compiles cleanly with `coqc`.

Please output:
1. The chosen Blink function and its C++ definition.
2. The complete Coq file (`BlinkSemanticSpecPrototype.v`) that compiles with `coqc`.
3. The executable differential testing script to verify behavior.
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

    output_path = Path("prototype_argon_output.md")
    output_path.write_text(response.text)
    print(f"Prototype plan and code saved to {output_path}")

if __name__ == "__main__":
    generate_end_to_end_test()

