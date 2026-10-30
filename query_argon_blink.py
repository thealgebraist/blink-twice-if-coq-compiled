import os
import sys
from pathlib import Path
from google import genai
from google.genai import types

def get_argon_response():
    key = Path("key.txt").read_text().strip()
    client = genai.Client(api_key=key)

    prompt = """
We need to choose a non-trivial, well-defined, and interesting function from Chromium Blink (third_party/blink), such as from CSS layout, CSS parsing/matching (e.g. selector matching or specificity calculation), DOM traversal, flexbox layout algorithm (e.g., flex line breaking / item sizing), scroll offset clamping, or URL / path sanitization / hit testing.

Requirements:
1. Select a real, concrete, non-trivial function from Chromium Blink with multiple parameters (at least 3-5 distinct parameters/configurations).
   Give the exact source file path and C++ signature / behavior in Chromium Blink.
2. Formalize this function in Coq (Rocq Prover, Coq 8.18+ / 9.x compatible).
3. The formalization MUST be designed specifically so that it is possible within Coq to step-by-step specialize it with respect to each of its parameters!
   Specifically:
   - Formulate curried definitions or parameter records with step-by-step partial application / specialization lemmas or tactics.
   - Show how each parameter can be specialized one by one:
     e.g., Param 1 specialized -> yields simplified intermediate function P1.
     Then Param 2 specialized -> yields P2,
     ... down to a fully specialized concrete evaluator or decision procedure.
   - Prove specialization correctness / equivalence lemmas in Coq (e.g., that evaluating the specialized pipeline equals evaluating the general function with those fixed arguments).
   - Compute test evaluations in Coq (`Compute ...`) demonstrating the step-by-step reduction at each stage.
4. Ensure the Coq code compiles cleanly with `coqc`. Use standard standard library modules (e.g., `From Coq Require Import List ZArith Bool Ascii String.`, `Import ListNotations.`, etc.). Avoid external dependencies unless they are standard.

Please provide:
1. The chosen Blink function, its location in Chromium Blink, and why it is non-trivial and a great candidate for parameter specialization (e.g., partial evaluation / staging / constant propagation / performance specialization).
2. The complete, self-contained Coq (.v) file ready to compile with `coqc`.
"""

    config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_budget=1024),
        temperature=0.2,
    )

    print("Querying gemini-4-argon with thinking budget (low)...")
    res = client.models.generate_content(
        model="gemini-4-argon",
        contents=prompt,
        config=config,
    )
    
    with open("argon_blink_coq.md", "w") as f:
        f.write(res.text)
    print("Done. Saved output to argon_blink_coq.md")

if __name__ == "__main__":
    get_argon_response()

