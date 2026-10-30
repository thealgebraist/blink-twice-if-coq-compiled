import os
from google import genai

api_key = open("key.txt").read().strip()
client = genai.Client(api_key=api_key)

prompt = """
In Chromium Blink CSS Block Layout:
Please explain the exact CSS margin collapsing algorithm in `MarginStrut` (from `third_party/blink/renderer/core/layout/margin_strut.h` or `margin_strut.cc`).
According to CSS 2.1 specification Section 8.3.1 (Collapsing margins):
"When two or more margins collapse, the resulting margin width is the maximum of the collapsing margins' widths. In the case of negative margins, the maximum of the absolute values of the negative margins is subtracted from the maximum of the positive margins. If there are no positive margins, the maximum of the absolute values of the negative margins is subtracted from zero."

How does Blink's `MarginStrut::Append(LayoutUnit value, bool is_quirk)` implement this?
Does it use `std::max` for positive margins and `std::min` (or `std::max` of absolute value) for negative margins?
What are the exact member variables and `Sum()` formula in Blink?
"""

response = client.models.generate_content(
    model="gemini-4-argon",
    contents=prompt,
)

print(response.text)

