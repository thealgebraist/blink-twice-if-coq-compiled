**Audit Report: Agent 469**
**Target:** Blink CSS Selector Engine (`SelectorChecker`)
**Subject:** `:nth-child(An+B)` Arithmetic Progression Evaluation Formula

In Blink, the `:nth-child(An+B)` pseudo-class (and its variants like `:nth-last-child`, `:nth-of-type`, etc.) is evaluated using 1-based indexing. Let $I$ be the 1-based index of the element among its siblings (or filtered siblings, if the `of S` syntax is used), such that $I \ge 1$. 

The selector matches if and only if there exists a non-negative integer $n$ ($n \ge 0$) that satisfies the linear equation:

$$A \cdot n + B = I$$

During evaluation, rather than iterating through values of $n$, Blink solves for $n$ directly and validates the constraints using integer arithmetic:

$$n = \frac{I - B}{A}$$

In C++ (`third_party/blink/renderer/core/css/selector_checker.cc` / `CSSSelector`), the exact matching logic branches into three primary cases based on the coefficient $A$:

### 1. Zero Step ($A = 0$)
When $A = 0$, the progression does not scale; it targets a single, specific index.
* **Formula:** $I == B$
* **Condition:** Matches if and only if the element's index equals the offset $B$.

### 2. Positive Step ($A > 0$)
When $A$ is positive, the progression moves forward from offset $B$.
* **Formula:** $(I - B) \ge 0 \quad \land \quad (I - B) \pmod A == 0$
* **Condition:** 
  1. $I$ must be greater than or equal to $B$ (ensuring $n \ge 0$).
  2. The difference $(I - B)$ must be evenly divisible by $A$ (ensuring $n$ is an integer).

### 3. Negative Step ($A < 0$)
When $A$ is negative, the progression steps backward from a positive offset $B$.
* **Formula:** $(I - B) \le 0 \quad \land \quad (I - B) \pmod A == 0$
* **Condition:**
  1. $I$ must be less than or equal to $B$ (since $A$ is negative, $(I - B)$ must also be negative or zero to ensure $n \ge 0$).
  2. The difference $(I - B)$ must be evenly divisible by $A$. *(Note: To avoid C++ implementation-defined behavior or confusion with negative modulo operations, this is often implemented by negating both sides: $(B - I) \ge 0 \land (B - I) \pmod{-A} == 0$).*

---

### Summary of Implementation Logic (`MatchNth`)
The internal `MatchNth(int count)` function in Blink effectively executes the following:

```cpp
bool MatchNth(int a, int b, int count) {
  if (!a)
    return count == b;
  if (a > 0) {
    if (count < b)
      return false;
    return (count - b) % a == 0;
  }
  // a < 0
  if (count > b)
    return false;
  return (b - count) % (-a) == 0;
}
```
*End of Audit.*