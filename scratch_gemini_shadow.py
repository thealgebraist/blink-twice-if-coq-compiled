import os
from google import genai

api_key = open("key.txt").read().strip()
client = genai.Client(api_key=api_key)

prompt = """
We are formally specifying and proving properties of leaf functions from Chromium Blink (third_party/blink) in Coq/Rocq.
Specifically, we want to formalize visual rect expansion in Blink:
ShadowList::AdjustRectForShadow or ShadowData::RectWithShadow or ComputeOutsets in blink renderer.
Can you provide the exact C++ source code from Blink for:
1. `ShadowList::AdjustRectForShadow` or `ShadowData` outset computation.
2. How `blur`, `spread`, `offset` (X and Y), and `kMax` saturation are calculated for `gfx::RectF` or `PhysicalRect`.
3. How multiple shadows in `ShadowList` accumulate (union of rects vs sum of outsets).
Give the exact Blink C++ method implementations and types (LayoutUnit, gfx::OutsetsF, etc.).
"""

response = client.models.generate_content(
    model="gemini-4-argon",
    contents=prompt,
)

print(response.text)
