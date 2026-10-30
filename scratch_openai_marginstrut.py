import os
from openai import OpenAI

api_key = open("openai.key.txt").read().strip()
client = OpenAI(api_key=api_key)

prompt = """
We are formally specifying and proving central Blink layout algorithms in Coq/Rocq.
Two central layout engines in Blink:
1. `MarginStrut` (Margin Collapsing in Block layout):
   - `third_party/blink/renderer/core/layout/block_layout_algorithm.cc` or `margin_strut.h` / `margin_strut.cc`.
   - How positive and negative margins collapse (positive_margin, negative_margin, quirks_positive_margin).
   - Invariants: `Sum() = positive_margin - negative_margin`, `Append(LayoutUnit value, bool is_quirk)`.
2. `BlockLayoutAlgorithm::CalculateSelfCollapsingMargins` or `ResolveBordersAndPadding`.

Can you provide:
1. The exact C++ methods of `MarginStrut` in Blink:
   - `MarginStrut::Append(LayoutUnit value, ...)`
   - `MarginStrut::Sum() const`
   - `MarginStrut::IsEmpty() const`
   - How negative margins and positive margins are separated and collapsed.
2. The exact mathematical invariants and edge cases (zero margin, multiple negative margins taking max absolute value, etc.).
Keep it mathematically rigorous and clear.
"""

response = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": prompt}],
    max_tokens=1500
)

print(response.choices[0].message.content)

