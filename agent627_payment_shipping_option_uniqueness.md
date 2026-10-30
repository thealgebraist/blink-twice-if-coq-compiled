# Formal Verification Report: W3C Payment Request Shipping Options ID Uniqueness in Chromium Blink

**Agent ID:** Formal Verification Agent 627  
**Domain:** Web Payments, Autofill & Form Normalization (Chromium Blink / W3C Specifications)  
**Target Source:** `third_party/blink/renderer/modules/payments/payment_request.cc`  
**Specification:** W3C Payment Request API §5.6 (`PaymentDetailsBase` & `PaymentShippingOption` Validation)  
**Formal Theory Target:** `BlinkPaymentShippingOptionUniquenessSemantics.v`  
**Core Invariant:** $\text{all\_unique\_ids}(opts) \iff \forall i \neq j, opts[i].id \neq opts[j].id$

---

## 1. Normative W3C Payment Request Specification Requirements

In the W3C Payment Request API specification ( specifically within the algorithms for **Process shipping options** under §5.6 *PaymentDetailsBase* and the `PaymentRequest` constructor / `PaymentRequestUpdateEvent.updateWith()` algorithms), shipping options provided by the merchant web application must undergo strict structural and semantic validation before being presented to the user agent's payment sheet or selecting a default `shippingOption`.

### 1.1 Normative Algorithm: Process Shipping Options
When `requestShipping` is set to `true` in `PaymentOptions`, the user agent processes `details.shippingOptions` (a sequence of `PaymentShippingOption` dictionaries) according to the following exact normative steps:

1. Let `options` be an empty `sequence<PaymentShippingOption>`.
2. Let `ids` be an empty `List` of strings (representing a mathematical set of seen identifiers).
3. If `details["shippingOptions"]` is present:
   a. For each `option` in `details["shippingOptions"]`:
      i. Validate and canonicalize `option.amount` (must be a valid decimal monetary value; not negative).
      ii. **Uniqueness Check:** If `ids` contains `option.id`:
          1. Set `options` to an empty `sequence<PaymentShippingOption>`.
          2. Break out of the loop (or in `PaymentRequest` construction / update contexts where specified by Blink's strict validation mode or state resets, either clear options or throw a `TypeError` depending on the exact W3C spec revision implemented).
          *Note on Spec Evolution & Blink Alignment:* In earlier revisions of the W3C Payment Request API and specific Blink validation paths, duplicate shipping option IDs either throw a `TypeError` ("Duplicate shipping option identifiers are not allowed") or invalidate the shipping options collection and set `selected_shipping_option` to `null`. Both rely on the exact same boolean decision procedure: detecting whether all `id` fields in `shippingOptions` are pairwise distinct.
      iii. Append `option` to `options`.
      iv. Append `option.id` to `ids`.

### 1.2 Selection Invariant
Furthermore, during option iteration, the specification dictates:
> For each `option` of `options`: if `option.selected` is `true`, set the request's `shippingOption` attribute to `option.id`. (If multiple options have `selected == true`, the last one in sequence order wins).

Crucially, because `all_unique_ids(options)` holds, the `shippingOption` string stored on the `PaymentRequest` instance unambiguously identifies **at most one** `PaymentShippingOption` record in the validated `options` array. Without ID uniqueness, dispatching the `shippingoptionchange` event would suffer from referential ambiguity, allowing price-spoofing attacks where the UI displays one shipping cost while the merchant script resolves `request.shippingOption` to a different option sharing the same `id`.

---

## 2. Chromium Blink Implementation Details and Invariants

In Chromium's rendering engine (`third_party/blink/renderer/modules/payments/payment_request.cc`), shipping option validation is executed inside the helper function `ValidateAndConvertPaymentDetailsBase` (called by `ValidateAndConvertPaymentDetailsInit` during `PaymentRequest::Create` and `ValidateAndConvertPaymentDetailsUpdate` during `OnUpdatePaymentDetails`).

### 2.1 C++ Implementation Structure in `payment_request.cc`
```cpp
void ValidateAndConvertPaymentDetailsBase(
    const PaymentDetailsBase* input,
    const PaymentOptions* options,
    PaymentDetailsPtr& output,
    String& shipping_option_output,
    ExecutionContext& execution_context,
    ExceptionState& exception_state) {
  // ... [ modifiers and displayItems validation ] ...

  if (options->requestShipping() && input->hasShippingOptions()) {
    HashSet<String> unique_ids;
    for (PaymentShippingOption* option : input->shippingOptions()) {
      ValidateAndConvertPaymentShippingOption(
          option, output, shipping_option_output, unique_ids,
          execution_context, exception_state);
      if (exception_state.HadException())
        return;
    }
  }
}
```

And inside `ValidateAndConvertPaymentShippingOption`:
```cpp
void ValidateAndConvertPaymentShippingOption(
    const PaymentShippingOption* input,
    PaymentDetailsPtr& output,
    String& shipping_option_output,
    HashSet<String>& unique_ids,
    ExecutionContext& execution_context,
    ExceptionState& exception_state) {
  // 1. Validate presence and non-emptiness of required fields
  // ...
  // 2. Check ID uniqueness via HashSet<String>
  if (unique_ids.Contains(input->id())) {
    exception_state.ThrowTypeError(
        "Duplicate shipping option identifiers are not allowed");
    return;
  }
  unique_ids.insert(input->id());

  // 3. Track selected shipping option (last selected == true wins)
  if (input->selected()) {
    shipping_option_output = input->id();
  }

  // 4. Convert to Mojom structure and append to output->shipping_options
  output->shipping_options.push_back(mojo_option);
}
```

### 2.2 Core Implementation Invariants
1. **HashSet Soundness & Completeness:** The accumulator `HashSet<String> unique_ids` maintains the exact set of `.id()` strings for all prefixes of `input->shippingOptions()` processed so far.
2. **Pairwise Index Inequality Equivalence:** The imperative loop with `unique_ids.Contains(input->id())` terminates without throwing an exception **if and only if** for every pair of valid indices $i, j \in [0, |opts|)$ with $i \neq j$, $opts[i].id \neq opts[j].id$.
3. **Referential Unambiguity of `shipping_option_output`:** Upon successful completion of `ValidateAndConvertPaymentDetailsBase`, if `shipping_option_output` is non-null, there exists a **unique** index $k < |output\rightarrow\text{shipping\_options}|$ such that $output\rightarrow\text{shipping\_options}[k].id = \text{shipping\_option\_output}$, and for that $k$, $input\rightarrow\text{shippingOptions}[k].selected = \text{true}$.

---

## 3. Formal Specification Definitions in Rocq / Coq

Below is the complete, self-contained formalization of `BlinkPaymentShippingOptionUniquenessSemantics.v`. We represent option identifiers using `Z` (from `ZArith`), which models arbitrary-precision integer hashes or encoded string code-point sequences, and model both the declarative W3C pairwise specification and Blink's stateful `HashSet` accumulator algorithm.

## 4. Concrete Theorems and Complete Admitted-Free Proofs

```coq
(** * BlinkPaymentShippingOptionUniquenessSemantics.v
    Formal Verification of W3C Payment Request API §5.6 Shipping Options ID Uniqueness
    Target: third_party/blink/renderer/modules/payments/payment_request.cc
    Agent 627 - Web Payments, Autofill & Form Normalization *)

From Coq Require Import ZArith.
From Coq Require Import Bool.
From Coq Require Import List.
From Coq Require Import Lia.
Import ListNotations.

Open Scope Z_scope.

Section BlinkPaymentShippingOptionUniqueness.

  (** ** 1. Data Model Definitions *)

  (** Identifier type (models WTF::String in Blink via integer encoding) *)
  Definition OptionId := Z.

  (** Monetary value representation *)
  Record PaymentCurrencyAmount : Type := mkCurrencyAmount {
    currency : Z;
    value    : Z
  }.

  (** W3C PaymentShippingOption dictionary / Mojom struct *)
  Record PaymentShippingOption : Type := mkShippingOption {
    opt_id       : OptionId;
    opt_label    : Z;
    opt_amount   : PaymentCurrencyAmount;
    opt_selected : bool
  }.

  (** Default dummy option for total indexing via nth *)
  Definition default_option : PaymentShippingOption :=
    mkShippingOption 0 0 (mkCurrencyAmount 0 0) false.

  (** ** 2. Mathematical Specification of Pairwise ID Uniqueness *)

  (** Declarative specification:
      all_unique_ids(opts) = forall i <> j, opts[i].id <> opts[j].id *)
  Definition all_unique_ids_spec (opts : list PaymentShippingOption) : Prop :=
    forall (i j : nat),
      (i < length opts)%nat ->
      (j < length opts)%nat ->
      i <> j ->
      opt_id (nth i opts default_option) <> opt_id (nth j opts default_option).

  (** Structural inductive characterization via List.NoDup on projected IDs *)
  Definition option_ids (opts : list PaymentShippingOption) : list OptionId :=
    map opt_id opts.

  Definition no_dup_ids (opts : list PaymentShippingOption) : Prop :=
    NoDup (option_ids opts).

  (** ** 3. Blink Imperative HashSet Validation Model *)

  (** Models HashSet<String>::Contains(id) *)
  Fixpoint hashset_contains (s : list OptionId) (id : OptionId) : bool :=
    match s with
    | [] => false
    | x :: xs => if Z.eqb x id then true else hashset_contains xs id
    end.

  (** Models HashSet<String>::insert(id) *)
  Definition hashset_insert (s : list OptionId) (id : OptionId) : list OptionId :=
    id :: s.

  (** Validation outcome modeling Blink ExceptionState & Mojom output *)
  Inductive BlinkValidationResult : Type :=
    | ValidationSuccess (validated_opts : list PaymentShippingOption)
                        (selected_id : option OptionId)
                        (final_set : list OptionId)
    | TypeErrorDuplicateId.

  (** Single step of ValidateAndConvertPaymentShippingOption *)
  Definition validate_step
             (opt : PaymentShippingOption)
             (acc_opts : list PaymentShippingOption)
             (sel_id : option OptionId)
             (seen_ids : list OptionId)
    : option (list PaymentShippingOption * option OptionId * list OptionId) :=
    if hashset_contains seen_ids (opt_id opt) then
      None (* exception_state.ThrowTypeError("Duplicate shipping option identifiers...") *)
    else
      let new_seen := hashset_insert seen_ids (opt_id opt) in
      let new_sel  := if opt_selected opt then Some (opt_id opt) else sel_id in
      let new_opts := acc_opts ++ [opt] in
      Some (new_opts, new_sel, new_seen).

  (** Loop in ValidateAndConvertPaymentDetailsBase over input->shippingOptions() *)
  Fixpoint blink_validate_loop
           (remaining : list PaymentShippingOption)
           (acc_opts : list PaymentShippingOption)
           (sel_id : option OptionId)
           (seen_ids : list OptionId)
    : BlinkValidationResult :=
    match remaining with
    | [] => ValidationSuccess acc_opts sel_id seen_ids
    | opt :: rest =>
        match validate_step opt acc_opts sel_id seen_ids with
        | None => TypeErrorDuplicateId
        | Some (acc_opts', sel_id', seen_ids') =>
            blink_validate_loop rest acc_opts' sel_id' seen_ids'
        end
    end.

  (** Top-level entry point starting with empty output, no selected ID, and empty HashSet *)
  Definition blink_validate_shipping_options
             (input_opts : list PaymentShippingOption) : BlinkValidationResult :=
    blink_validate_loop input_opts [] None [].

  (** Pure boolean uniqueness checker corresponding to Blink's check *)
  Fixpoint check_unique_loop (opts : list PaymentShippingOption) (seen : list OptionId) : bool :=
    match opts with
    | [] => true
    | opt :: rest =>
        if hashset_contains seen (opt_id opt) then false
        else check_unique_loop rest (hashset_insert seen (opt_id opt))
    end.

  Definition blink_all_unique_ids_b (opts : list PaymentShippingOption) : bool :=
    check_unique_loop opts [].

  (** ** 4. Lemmas on HashSet Operations *)

  Lemma hashset_contains_iff_In : forall (s : list OptionId) (id : OptionId),
    hashset_contains s id = true <-> In id s.
  Proof.
    induction s as [| x xs IH]; simpl; intros id.
    - split; intros H; inversion H.
    - destruct (Z.eqb_spec x id) as [Heq | Hneq].
      + subst. split; intros _; [left; reflexivity | reflexivity].
      + rewrite IH. split; intros H.
        * right; exact H.
        * destruct H as [Heq | Hin]; [congruence | exact Hin].
  Qed.

  Lemma hashset_contains_false_iff_not_In : forall (s : list OptionId) (id : OptionId),
    hashset_contains s id = false <-> ~ In id s.
  Proof.
    intros s id.
    rewrite <- hashset_contains_iff_In.
    destruct (hashset_contains s id); split; intros H; try reflexivity; try congruence.
    exfalso; apply H; reflexivity.
  Qed.

  (** ** 5. Equivalence between Blink Boolean Check and List.NoDup *)

  Lemma check_unique_loop_spec : forall (opts : list PaymentShippingOption) (seen : list OptionId),
    check_unique_loop opts seen = true <->
    (NoDup (option_ids opts) /\ (forall x, In x (option_ids opts) -> ~ In x seen)).
  Proof.
    induction opts as [| opt rest IH]; intros seen; simpl.
    - split; intros H.
      + split; [constructor | intros x Hx; inversion Hx].
      + reflexivity.
    - destruct (hashset_contains seen (opt_id opt)) eqn:Hcont.
      + rewrite hashset_contains_iff_In in Hcont.
        split; intros H; [discriminate H |].
        destruct H as [_ Hdisj].
        exfalso. apply (Hdisj (opt_id opt)); [left; reflexivity |