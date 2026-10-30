import os
from openai import OpenAI

api_key = open("openai.key.txt").read().strip()
client = OpenAI(api_key=api_key)

prompt = """
We are formalizing leaf functions from Chromium Blink (third_party/blink) in Coq.
Specifically: ShadowData / ShadowList rect expansion and outsets:
In Blink:
- third_party/blink/renderer/core/style/shadow_data.h
- third_party/blink/renderer/core/style/shadow_list.h / cc
How does ShadowData compute its outset / rect expansion?
Give the exact method definitions:
1. `ShadowData::RectWithShadow(gfx::RectF rect)` or `PhysicalRect`
2. How `blur`, `spread`, `x_offset`, `y_offset` expand `left`, `right`, `top`, `bottom`.
3. How `BoxPainterBase::AdjustRectForShadow` works.
Keep it concise and show the C++ code formulas.
"""

response = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": prompt}],
    max_tokens=1000
)

print(response.choices[0].message.content)

