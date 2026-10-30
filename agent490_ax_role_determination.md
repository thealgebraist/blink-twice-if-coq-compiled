**AUDIT REPORT: Blink Accessibility (AX) Engine**
**Agent:** 490
**Target:** `AXObject::DetermineAccessibilityRole()` (`third_party/blink/renderer/modules/accessibility/ax_object.cc` and `ax_node_object.cc`)
**Subject:** AXRole Determination & Override Precedence

---

### 1. Executive Summary
In the Chromium Blink rendering engine, the final `ax::mojom::blink::Role` assigned to an `AXObject` is not determined solely by the HTML tag or the `role` attribute. Instead, it undergoes a strict, multi-stage resolution pipeline. The engine balances explicit author intent (ARIA) against structural validity, host-language semantics, and browser security/usability constraints.

Below is the exact precedence hierarchy, ordered from **Highest Precedence (1)** to **Lowest Precedence (8)**.

---

### 2. Role Override Precedence Hierarchy

#### **Level 1: Complete Exclusion & Invisibility**
Before a role is calculated, Blink determines if the node should exist in the AX Tree at all. While technically mapped to `kNone` or `kIgnored` rather than a standard role, this overrides all downstream logic.
*   **Triggers:** `display: none`, `visibility: hidden`, `aria-hidden="true"`, or inert subtrees (e.g., backgrounded `<dialog>` elements or `<template>` contents).
*   **Override Defense:** Even if an element has an explicit `role="button"`, if it is `aria-hidden="true"`, it is pruned. *(Exception: Focusable elements inside `aria-hidden` may sometimes be repaired/exposed depending on current Blink flags, though standard behavior suppresses them).*

#### **Level 2: Native Host Language Supersedence (Anti-ARIA Constraints)**
Blink enforces specific W3C HTML-AAM (Accessibility API Mappings) rules where native semantics **forbid** author-supplied ARIA roles to prevent broken user experiences.
*   **Condition:** `NativeRoleIgnoringAria()` takes precedence over `AriaRoleAttribute()` in specific hardcoded contexts.
*   **Examples:** 
    *   An `<input type="file">` or `<input type="color">` cannot have its internal shadow DOM structure overridden by simple container roles without breaking functionality.
    *   Certain pseudo-elements or internal media controls (`::-webkit-media-controls`) ignore author ARIA roles.

#### **Level 3: Forced Presentational Conflict Resolution (Global Attrs & Focus)**
If an author explicitly sets `role="presentation"` or `role="none"`, Blink attempts to strip the semantic role. **However, Blink overrides the author's `presentation` role** and restores the **Native Role** if the element is interactive or carries global ARIA states.
*   **Triggers (`HasGlobalARIAAttribute` / `IsFocusable`):**
    *   The element is focusable (`tabindex="0"`, `<button>`, `<input>`).
    *   The element has global ARIA attributes (e.g., `aria-label`, `aria-describedby`, `aria-live`, `aria-invalid`).
*   **Result:** `<button role="presentation" aria-label="Close">` **ignores** `role="presentation"` and resolves to `ax::mojom::blink::Role::kButton`.

#### **Level 4: Contextual/Structural ARIA Validation**
If a valid explicit ARIA role is provided (and survives Level 3), Blink checks if the role is structurally allowed in its current DOM/AX context.
*   **Condition:** Certain ARIA roles require specific parent contexts (`AriaRoleRequiresParent`).
*   **Examples:** `role="listitem"` must be inside a `list`; `role="row"` must be inside a `table`, `grid`, or `treegrid`; `role="tab"` must be inside a `tablist`.
*   **Override:** If the required parent is missing, Blink invalidates the ARIA role and falls back to the **Native Role** (Level 6) or **Generic Role** (Level 7).

#### **Level 5: Explicit Author ARIA Role (`AriaRoleAttribute`)**
If the element passes Levels 1–4, the `role` attribute takes precedence over the native HTML element semantics.
*   **Mechanism:** `AXObject::DetermineAriaRoleAttribute()` parses the space-delimited token list of the `role` attribute.
*   **Fallback Token Resolution:** Blink iterates through the tokens from left to right. The *first* token that maps to a valid, recognized WAI-ARIA role in Blink's `ARIARoleMap` is selected. (e.g., `role="foobaz button"` resolves to `kButton`).
*   **Abstract Roles:** Abstract roles (like `command`, `composite`, `input`, `landmark`, `range`, `roletype`, `section`, `sectionhead`, `select`, `structure`, `widget`, `window`) are ignored by Blink as invalid author roles, triggering fallback to the next token or native role.

#### **Level 6: Inherited Presentational Overrides (Parent-Driven)**
If no explicit ARIA role is present on the node, its native role may still be stripped by an ancestor.
*   **Condition:** The parent element has `role="presentation"` or `role="none"` AND the current node is a required owned element of that parent.
*   **Examples:** A `<table role="presentation">` forces its native child `<tr>` and `<td>` elements to lose their `kRow` and `kCell` roles, overriding their native semantics and mapping them to `kNone` / `kGenericContainer` (unless the child itself has an explicit ARIA role or fails Level 3).
*   *Note: The same applies to `<ul>`/`<ol>` and their `<li>` children.*

#### **Level 7: Implicit Native Host-Language Semantics (`NativeRoleIgnoringAria`)**
If no ARIA role is present (or if the ARIA role was invalidated in Levels 3–5), Blink determines the role based on the DOM node, its attributes, and its context (`AXNodeObject::NativeRoleIgnoringAria()`).
*   **Tag + Attribute Context:**
    *   `<a>` with `href` -> `kLink`. Without `href` -> `kGenericContainer` (or `kAnchor`).
    *   `<input>` -> Role depends heavily on the `type` attribute (`text` -> `kTextField`, `checkbox` -> `kCheckBox`, ` range` -> `kSlider`).
    *   `<header>` / `<footer>` -> Resolves to `kBanner` / `kContentInfo` *only* if not a descendant of an `<article>`, `<aside>`, `<main>`, `<nav>`, or `<section>`. Otherwise, overridden to `kGenericContainer` (or `kHeader`/`kFooter`).
    *   `<section>` / `<form>` -> Resolves to `kRegion` / `kForm` *only* if it has an accessible name (`aria-label`, `aria-labelledby`, or `title`). Otherwise, falls back to `kGenericContainer`.
    *   `<img>` -> If `alt=""` (empty string) and no other naming attributes exist, native role is overridden to `kNone`/`kPresentational`.
*   **Table Heuristics:** Native `<table>` elements may have their roles stripped or altered if Blink heuristics determine they are "Layout Tables" rather than "Data Tables" (though explicit ARIA always overrides this heuristic).

#### **Level 8: Layout & CSS Fallback (`kGenericContainer` / `kGroup`)**
If the element has no ARIA role and no specific native semantic mapping (e.g., `<div>`, `<span>`, or a nameless `<section>`), Blink assigns a fallback role so the node can still participate in the layout/AX tree if necessary (e.g., if it has an event listener, `tabindex`, or CSS flexbox/grid properties).
*   **Resolution:** Typically resolves to `ax::mojom::blink::Role::kGenericContainer`.

---

### 3. Summary Flowchart (Code Execution Path)

```text
[DOM Node / LayoutObject]
       │
       ▼
Is Ignored / Hidden? ──(Yes)──> [Role::kNone / Pruned]
       │ (No)
       ▼
Has Explicit ARIA Role?
       ├──(Yes)──> Is it "presentation"/"none"?
       │                 ├──(Yes)──> Is Focusable OR Has Global ARIA?
       │                 │                 ├──(Yes)──> [USE NATIVE ROLE] (Conflict Resolution)
       │                 │                 └──(No)───> [Role::kNone]
       │                 └──(No)───> Is ARIA Role Valid in Context & Not Abstract?
       │                                   ├──(Yes)──> [USE ARIA ROLE]
       │                                   └──(No)───> (Fallthrough to Native)
       ▼ (No / Fallthrough)
Does Parent Force Presentational? (e.g., <table role="none"> -> <td>)
       ├──(Yes)──> [Role::kNone / kGenericContainer]
       ▼ (No)
Evaluate Native HTML Semantics (Tag + Attributes + DOM Ancestors)
       ├──(Has Semantic Mapping)──> [USE NATIVE ROLE]
       ▼ (No Semantic Mapping, e.g., <div>)
[Role::kGenericContainer]
```

**Audit Conclusion:** Blink's role determination strictly adheres to W3C ARIA in HTML specifications, prioritizing **user access to interactive/labeled controls (Level 3)** over **author hiding intent (`role="none"`)**, and prioritizing **valid author ARIA (Level 5)** over **native HTML semantics (Level 7)**. 

*End of Report — Agent 490.*