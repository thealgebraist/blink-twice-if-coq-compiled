import os
from google import genai

api_key = open("key.txt").read().strip()
client = genai.Client(api_key=api_key)

prompt = """
We are designing a sound big-step operational semantics in Coq/Rocq for the core Blink HTML/CSS rendering pipeline (specifically LayoutNG: DOM / Box tree -> ConstraintSpace -> LayoutResult / FragmentTree).
In Blink LayoutNG:
- Node types: BlockContainer, FlexContainer, InlineNode, Text, Replaced (images).
- Pipeline phases:
  1. Style resolution / ComputedStyle (display, flex-direction, width, height, margin, padding, borders).
  2. ConstraintSpace: available inline_size, available block_size, percentage resolution size, margin strut.
  3. Layout Algorithm invocation (BlockLayoutAlgorithm::Layout, FlexLayoutAlgorithm::Layout).
  4. Fragment creation: PhysicalBoxFragment with PhysicalOffset and PhysicalSize, plus BoundingBox visual overflow.

What is the cleanest, mathematically sound big-step relation signature:
`(Context, ConstraintSpace, BoxTree) =[ Layout ]=> (PhysicalFragmentTree, VisualOverflow)`?
What are the exact inductive constructors needed to capture:
- Root Layout (Viewport / ICB: Initial Containing Block)
- Block formatting context child sequencing with MarginStrut accumulation
- Flexbox formatting context distribution (ResolveFlexibleLengths)
- Leaf replaced elements (aspect-ratio scaling)
Keep it formal, elegant, and directly translatable to an inductive relation in Coq.
"""

response = client.models.generate_content(
    model="gemini-4-argon",
    contents=prompt,
)

print(response.text)

