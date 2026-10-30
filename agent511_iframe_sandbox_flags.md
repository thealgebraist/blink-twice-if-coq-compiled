# Formal Verification of IFrame Sandbox Flag Bitmask Accumulation in Chromium Blink

## 1. Normative Specification Requirements

### 1.1 WHATWG HTML Standard §4.8.5 & §7.1.4
The HTML Standard defines the `iframe` element (§4.8.5) and its associated `sandbox` content attribute, which controls the sandboxing policies applied to the nested navigable's active document. The underlying mechanics are defined in §7.1.4 (*Sandboxing*).

A **sandboxing flag set** is a set of zero or more flags used to restrict the capabilities of potentially untrusted resources:
*   *sandboxed navigation browsing context flag*
*   *sandboxed auxiliary navigation browsing context flag*
*   *sandboxed top-level navigation without user activation browsing context flag*
*   *sandboxed top-level navigation with user activation browsing context flag*
*   *sandboxed plugins browsing context flag*
*   *sandboxed origin browsing context flag*
*   *sandboxed forms browsing context flag*
*   *sandboxed pointer lock browsing context flag*
*   *sandboxed scripts browsing context flag*
*   *sandboxed automatic features browsing context flag*
*   *sandboxed document.domain browsing context flag*
*   *sandboxed orientation lock browsing context flag*
*   *sandboxed presentation browsing context flag*
*   *sandboxed downloads browsing context flag*
*   *sandboxed custom protocols navigation browsing context flag*

### 1.2 The "Parse a Sandboxing Directive" Algorithm
When an `iframe` element's `sandbox` attribute is set, changed, or removed, the user agent must invoke the **parse a sandboxing directive** algorithm (HTML Standard §7.1.4.1), given an input string (the attribute value) and an output *sandboxing flag set*:

1.  **Split on ASCII whitespace**: Let $tokens$ be the result of splitting the input on ASCII whitespace.
2.  **Populate Initial Restriction Set**: Add *all* possible sandboxing flags to the output flag set.
3.  **Selective Relaxation**: Remove specific flags from the output set based on the presence of corresponding allow-tokens in $tokens$:
    *   `allow-same-origin` removes the *sandboxed origin browsing context flag*.
    *   `allow-forms` removes the *sandboxed forms browsing context flag*.
    *   `allow-scripts` removes the *sandboxed scripts browsing context flag* and the *sandboxed automatic features browsing context flag*.
    *   `allow-top-navigation` removes the *sandboxed top-level navigation without user activation browsing context flag* and the *sandboxed top-level navigation with user activation browsing context flag*.
    *   (And similarly for `allow-popups`, `allow-pointer-lock`, `allow-orientation-lock`, `allow-popups-to-escape-sandbox`, `allow-modals`, `allow-presentation`, `allow-top-navigation-by-user-activation`, `allow-downloads`, and `allow-top-navigation-to-custom-protocols`).

### 1.3 Monotonic Inheritance and Policy Accumulation
Crucially, sandboxing flags are **monotonically accumulated** across browsing context boundaries and policy delivery mechanisms (such as the `Content-Security-Policy: sandbox` HTTP header):

$$\text{EffectiveSandboxFlags} = \text{ParentSandboxFlags} \cup \text{IframeAttributeFlags} \cup \text{CSPHeaderFlags}$$

Once a restriction flag is present in the effective set, no nested context or subsequent directive can remove it. In bitmask representations where $1$ denotes a *restriction* (a set sandboxing flag), accumulation corresponds to bitwise disjunction ($\lor$), and token-based relaxation during parsing corresponds to bitwise intersection with the complement ($\land \neg$).

---

## 2. Chromium Blink Implementation Analysis

### 2.1 Source Location and Types
*   **Element Handling**: `third_party/blink/renderer/core/html/html_iframe_element.cc`
*   **Token Parsing**: `third_party/blink/renderer/core/frame/csp/execution_context_csp_delegate.cc` and `services/network/public/cpp/web_sandbox_flags.cc`
*   **Bitmask Enumeration**: `services/network/public/mojom/web_sandbox_flags.mojom`

In Chromium, the sandboxing flag set is represented by the bitmask enumeration `network::mojom::blink::WebSandboxFlags`:

```cpp
// services/network/public/mojom/web_sandbox_flags.mojom (Conceptual C++ mapping)
enum class WebSandboxFlags : int32_t {
  kNone                                   = 0,
  kNavigation                             = 1 << 0, // 1
  kPlugins                                = 1 << 1, // 2
  kOrigin                                 = 1 << 2, // 4
  kForms                                  = 1 << 3, // 8
  kScripts                                = 1 << 4, // 16
  kTopNavigation                          = 1 << 5, // 32
  kPopups                                 = 1 << 6, // 64
  kAutomaticFeatures                      = 1 << 7, // 128
  kPointerLock                            = 1 << 8, // 256
  kDocumentDomain                         = 1 << 9, // 512
  kOrientationLock                        = 1 << 10, // 1024
  kPropagatesToAuxiliaryBrowsingContexts  = 1 << 11, // 2048
  kModals                                 = 1 << 12, // 4096
  kPresentationController                 = 1 << 13, // 8192
  kTopNavigationByUserActivation          = 1 << 14, // 16384
  kDownloads                              = 1 << 15, // 32768
  kStorageAccessByUserActivation          = 1 << 16, // 65536
  kTopNavigationToCustomProtocols         = 1 << 17, // 131072
  kAll                                    = -1
};
```

### 2.2 Attribute Parsing in `HTMLIFrameElement`
In `third_party/blink/renderer/core/html/html_iframe_element.cc`, `HTMLIFrameElement::ParseAttribute` intercepts modifications to `html_names::kSandboxAttr`:

```cpp
void HTMLIFrameElement::ParseAttribute(
    const AttributeModificationParams& params) {
  if (params.name == html_names::kSandboxAttr) {
    sandbox_->DidUpdateAttributeValue(params.old_value, params.new_value);
    network::mojom::blink::WebSandboxFlags current_flags =
        network::mojom::blink::WebSandboxFlags::kNone;
    if (!params.new_value.IsNull()) {
      using network::mojom::blink::WebSandboxFlags;
      // Default to kAll restrictions when the sandbox attribute is present,
      // then clear flags corresponding to valid allow-* tokens.
      auto parsed = network::ParseWebSandboxPolicy(sandbox_->value().Utf8(),
                                                   WebSandboxFlags::kNone);
      current_flags = parsed.flags;
      if (!parsed.error_message.empty()) {
        GetDocument().AddConsoleMessage(MakeGarbageCollected<ConsoleMessage>(
            mojom::blink::ConsoleMessageSource::kOther,
            mojom::blink::ConsoleMessageLevel::kError,
            WebString::FromUTF8("Error while parsing the 'sandbox' attribute: " +
                                parsed.error_message)));
      }
    }
    SetSandboxFlags(current_flags);
    UseCounter::Count(GetDocument(), WebFeature::kSandboxViaIFrame);
  } else {
    HTMLFrameElementBase::ParseAttribute(params);
  }
}
```

### 2.3 Bitwise Operators and Invariants
In `services/network/public/cpp/web_sandbox_flags.h` and `web_sandbox_flags.cc`, bitwise operators are overloaded for `WebSandboxFlags`:

```cpp
inline constexpr WebSandboxFlags operator&(WebSandboxFlags a, WebSandboxFlags b) {
  return static_cast<WebSandboxFlags>(static_cast<int>(a) & static_cast<int>(b));
}

inline constexpr WebSandboxFlags operator|(WebSandboxFlags a, WebSandboxFlags b) {
  return static_cast<WebSandboxFlags>(static_cast<int>(a) | static_cast<int>(b));
}

inline constexpr WebSandboxFlags operator~(WebSandboxFlags a) {
  return static_cast<WebSandboxFlags>(~static_cast<int>(a));
}
```

During policy parsing (`ParseWebSandboxPolicy`) and frame policy merging (`FramePolicy::sandbox_flags`), two core bitwise patterns govern security boundaries:

1.  **Restriction Accumulation**:
    ```cpp
    effective_flags = parent_flags | iframe_attribute_flags | csp_sandbox_flags;
    ```
    *Invariant*: If a flag $F$ is set in `mask`, then after accumulating any additional flags `flag`, $F$ remains set (`has_flag(mask | flag, F) == true`). Furthermore, `has_flag(mask | flag, flag) == true`.

2.  **Token Relaxation**:
    ```cpp
    WebSandboxFlags flags = WebSandboxFlags::kAll & ~ignored_flags;
    for (const auto& token : tokens) {
      flags = flags & ~ParseSandboxToken(token);
    }
    ```
    *Invariant*: Clearing a permitted token flag `allow_mask` via `flags & ~allow_mask` guarantees that `has_flag(flags & ~allow_mask, allow_mask) == false` (for non-zero masks) while strictly preserving any unrelated restriction $F$ where `(F & allow_mask) == 0`.

---

## 3. Formal Specification in Rocq (Coq)

We formalize the bitmask semantics in `BlinkIFrameSandboxBitmaskSemantics.v` using `Coq.ZArith.ZArith`. Representing bitmasks over $\mathbb{Z}$ models arbitrary-width and fixed-width two's complement bitvectors accurately (including `kAll = -1`, since $Z.lor\ (-1)\ x = -1$ and $Z.ldiff\ x\ y = Z.land\ x\ (Z.lnot\ y)$ in Coq's binary integer library).

### 3.1 Formal Definitions
We define:
*   `SandboxMask := Z`: The type of bitmasks representing combinations of `WebSandboxFlags`.
*   `has_flag (mask flag : SandboxMask) : bool`: The predicate `(mask & flag) == flag`, corresponding to `blink::FramePolicy` and `SecurityContext::IsSandboxed(flag)`.
*   `accumulate_flag (mask flag : SandboxMask) : SandboxMask`: Bitwise OR `Z.lor mask flag`.
*   `clear_flag (mask flag : SandboxMask) : SandboxMask`: Bitwise AND-NOT `Z.land mask (Z.lnot flag)`.
*   Concrete `WebSandboxFlags` constants (`kNone`, `kNavigation`, ..., `kAll`) and the `HTMLIFrameElement` parsing state machine.

---

## 4. Formal Verification (`BlinkIFrameSandboxBitmaskSemantics.v`)

The complete, self-contained, admitted-free Rocq formalization and proofs are presented below.

```coq
(** * BlinkIFrameSandboxBitmaskSemantics.v
    Formal verification of Chromium Blink's IFrame sandbox flags bitmask
    accumulation, monotonic inheritance, and token-based relaxation.
    
    Source: third_party/blink/renderer/core/html/html_iframe_element.cc
            services/network/public/cpp/web_sandbox_flags.cc
    Specification: WHATWG HTML Standard §4.8.5, §7.1.4
*)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Bitmask Representation and WebSandboxFlags Constants *)

Definition SandboxMask : Type := Z.

Definition kNone                                  : SandboxMask := 0.
Definition kNavigation                            : SandboxMask := Z.shiftl 1 0.  (* 1 *)
Definition kPlugins                               : SandboxMask := Z.shiftl 1 1.  (* 2 *)
Definition kOrigin                                : SandboxMask := Z.shiftl 1 2.  (* 4 *)
Definition kForms                                 : SandboxMask := Z.shiftl 1 3.  (* 8 *)
Definition kScripts                               : SandboxMask := Z.shiftl 1 4.  (* 16 *)
Definition kTopNavigation                         : SandboxMask := Z.shiftl 1 5.  (* 32 *)
Definition kPopups                                : SandboxMask := Z.shiftl 1 6.  (* 64 *)
Definition kAutomaticFeatures                     : SandboxMask := Z.shiftl 1 7.  (* 128 *)
Definition kPointerLock                           : SandboxMask := Z.shiftl 1 8.  (* 256 *)
Definition kDocumentDomain                        : SandboxMask := Z.shiftl 1 9.  (* 512 *)
Definition kOrientationLock                       : SandboxMask := Z.shiftl 1 10. (* 1024 *)
Definition kPropagatesToAuxiliaryBrowsingContexts : SandboxMask := Z.shiftl 1 11. (* 2048 *)
Definition kModals                                : SandboxMask := Z.shiftl 1 12. (* 4096 *)
Definition kPresentationController                : SandboxMask := Z.shiftl 1 13. (* 8192 *)
Definition kTopNavigationByUserActivation         : SandboxMask := Z.shiftl 1 14. (* 16384 *)
Definition kDownloads                             : SandboxMask := Z.shiftl 1 15. (* 32768 *)
Definition kStorageAccessByUserActivation         : SandboxMask := Z.shiftl 1 16. (* 65536 *)
Definition kTopNavigationToCustomProtocols        : SandboxMask := Z.shiftl 1 17. (* 131072 *)
Definition kAll                                   : SandboxMask := -1.

(** ** 2. Core Bitmask Operations and Predicates *)

(** Checks if all bits in [flag] are set in [mask].
    Matches Chromium's `(mask & flag) == flag` check in SecurityContext::IsSandboxed. *)
Definition has_flag (mask flag : SandboxMask) : bool :=
  Z.eqb (Z.land mask flag) flag.

(** Accumulates a restriction flag or mask into an existing mask via bitwise OR. *)
Definition accumulate_flag (mask flag : SandboxMask) : SandboxMask :=
  Z.lor mask flag.

(** Clears an allowed flag mask from a restriction mask via bitwise AND-NOT. *)
Definition clear_flag (mask flag : SandboxMask) : SandboxMask :=
  Z.land mask (Z.lnot flag).

(** Disjointness predicate for two bitmasks. *)
Definition disjoint_masks (m1 m2 : SandboxMask) : Prop :=
  Z.land m1 m2 = 0.

(** ** 3. Fundamental Bitwise Lemmas *)

Lemma has_flag_spec