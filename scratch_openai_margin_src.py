import os
from openai import OpenAI

api_key = open("openai.key.txt").read().strip()
client = OpenAI(api_key=api_key)

prompt = """
Look at the actual Chromium source code for `third_party/blink/renderer/core/layout/margin_strut.h` and `margin_strut.cc`.
What are the exact member variables and `Append` implementation?
Specifically:
In Blink:
```cpp
struct MarginStrut {
  LayoutUnit positive_margin;
  LayoutUnit negative_margin;
  LayoutUnit quirks_positive_margin;
  bool is_quirk = false;
  ...
```
How does `Append(const LayoutUnit& value, const bool is_quirk)` work?
Show the exact lines of C++ code for `Append`, `Sum`, and `operator==`.
"""

response = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": prompt}],
    max_tokens=1000
)

print(response.choices[0].message.content)

