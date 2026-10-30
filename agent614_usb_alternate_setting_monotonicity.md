# Formal Verification Report: WebUSB Alternate Settings Validation and Selection Semantics

**Agent**: Formal Verification Agent 614 (Web Hardware & Peripheral Platform APIs)  
**Topic**: WebUSB Alternate Settings Validation and Selection Semantics  
**Chromium Source**: `third_party/blink/renderer/modules/webusb/usb_interface.cc` (and `usb_device.cc`)  
**Specification**: W3C WebUSB API §3.5 `selectAlternateInterface` / `USBInterface`  
**Formal Theory Target**: `BlinkWebUSBAlternateSettingSemantics.v`  
**Mathematical Property**: Alternate setting index is valid if and only if $0 \le \text{alt\_idx} < \text{num\_alternate\_settings}$.

---

## 1. Normative W3C WebUSB Specification Requirements

The W3C WebUSB specification defines the object model and operational semantics for USB interfaces and their alternate settings. A USB interface groups together endpoints into a functional unit (e.g., an audio streaming interface), and *alternate settings* allow the host to dynamically change endpoint characteristics (such as isochronous bandwidth allocation) on an active configuration without resetting the entire device.

### 1.1 `USBInterface` Attributes and Constructors (§3.6)
Under the WebUSB specification, a `USBInterface` object represents a single interface descriptor group within a `USBConfiguration`:

- **`interfaceNumber`** (`octet`): The zero-based index of this interface as defined by `bInterfaceNumber` in the USB Interface Descriptor.
- **`alternate`** (`USBAlternateInterface`): The currently selected alternate setting for this interface. By default, when a configuration is selected or before an interface is claimed and modified, this defaults to the alternate setting with `bAlternateSetting == 0` (typically at index 0).
- **`alternates`** (`FrozenArray<USBAlternateInterface>`): A list of all alternate interface descriptors exposed by the device for this `bInterfaceNumber`.

### 1.2 `selectAlternateInterface(interfaceNumber, alternateSetting)` (§3.5)
When the script invokes `device.selectAlternateInterface(interfaceNumber, alternateSetting)`:

1. Let `promise` be a new Promise.
2. Let `device` be the target `USBDevice` object.
3. Verify device state invariants:
   - If `device.[[opened]]` is `false`, reject `promise` with an `InvalidStateError` (`DOMException`) and abort.
   - Let `configuration` be the active `USBConfiguration`. If `configuration` is `null`, reject `promise` with an `InvalidStateError` and abort.
4. Locate the target interface:
   - Find the `interface` in `configuration.interfaces` whose `interfaceNumber` matches the argument. If no such interface exists, reject `promise` with a `NotFoundError` and abort.
   - If `interface.[[claimed]]` is `false`, reject `promise` with an `InvalidStateError` and abort.
5. Validate the alternate setting:
   - Search `interface.alternates` for an entry whose `alternateSetting` attribute equals the passed `alternateSetting` octet.
   - **Normative Boundary Requirement**: If no such `USBAlternateInterface` exists within the bounded `alternates` array, reject `promise` with a `NotFoundError` (`DOMException`) and abort.
6. Issue a `SET_INTERFACE` control transfer to the underlying USB bus. Upon success, update the active alternate setting state of the interface to the validated index and resolve `promise`.

---

## 2. Blink Implementation Details and Invariants

In Chromium's Blink rendering engine, the representation and validation of `USBInterface` and its alternate settings are implemented across `third_party/blink/renderer/modules/webusb/usb_interface.cc` and `usb_device.cc`, backed by Mojo descriptors (`device::mojom::blink::UsbInterfaceInfo`).

### 2.1 Representation in `usb_interface.cc`

In Blink, a `USBInterface` object does not duplicate descriptor memory. Instead, it holds indices pointing into the immutable Mojo configuration tree stored on the parent `USBDevice`:

- `device_`: `Member<USBDevice>` referencing the owning device.
- `configuration_index_`: `wtf_size_t` indexing into `device_->Info().configurations`.
- `interface_index_`: `wtf_size_t` indexing into `configurations[configuration_index_]->interfaces`.

The underlying Mojo struct `UsbInterfaceInfo` contains:
```cpp
uint8_t interface_number;
uint8_t first_interface;
WTF::Vector<UsbAlternateInterfaceInfoPtr> alternates;
```

### 2.2 Constructor and Index Validation (`usb_interface.cc`)

```cpp
USBInterface::USBInterface(const USBDevice* device,
                           wtf_size_t configuration_index,
                           wtf_size_t interface_index)
    : device_(device),
      configuration_index_(configuration_index),
      interface_index_(interface_index) {
  DCHECK_LT(configuration_index_, device_->Info().configurations.size());
  DCHECK_LT(interface_index_, device_->Info()
                                  .configurations[configuration_index_]
                                  ->interfaces.size());
}
```

### 2.3 Alternate Setting Lookup and Bounds Invariant

When accessing or selecting an alternate setting, Blink translates between the `uint8_t alternate_setting` value (`bAlternateSetting` from the USB descriptor) and the internal vector index `alt_idx` (`wtf_size_t`):

```cpp
USBAlternateInterface* USBInterface::alternate() const {
  if (device_->IsInterfaceClaimed(interface_index_)) {
    wtf_size_t alternate_index =
        device_->SelectedAlternateInterface(interface_index_);
    DCHECK_LT(alternate_index, Info().alternates.size());
    return MakeGarbageCollected<USBAlternateInterface>(this, alternate_index);
  }
  return nullptr;
}

HeapVector<Member<USBAlternateInterface>> USBInterface::alternates() const {
  HeapVector<Member<USBAlternateInterface>> alternates;
  for (wtf_size_t i = 0; i < Info().alternates.size(); ++i)
    alternates.push_back(MakeGarbageCollected<USBAlternateInterface>(this, i));
  return alternates;
}
```

When `USBDevice::selectAlternateInterface` is called, Blink resolves the interface index and searches the `alternates` vector for the matching `alternate_setting`. Let `num_alternate_settings` be `Info().alternates.size()`. An internal index `alt_idx` is valid if and only if:

$$0 \le \text{alt\_idx} < \text{num\_alternate\_settings}$$

If the search fails (meaning no `alt_idx` within $[0, \text{num\_alternate\_settings})$ matches the requested setting, or an out-of-bounds index is checked), Blink rejects the script promise with `DOMExceptionCode::kNotFoundError` ("The alternate setting provided is not supported by the device."). If valid, `selected_alternate_indices_[interface_index_]` is updated to `alt_idx`, preserving the invariant that `SelectedAlternateInterface(interface_index_)` always satisfies $0 \le \text{alt\_idx} < \text{num\_alternate\_settings}$.

---

## 3. Formal Specification & Complete Proofs in Rocq/Coq

Below is the self-contained, admitted-free formalization in Rocq/Coq (`BlinkWebUSBAlternateSettingSemantics.v`). It models the Blink `USBInterface` state machine, index validation, `bAlternateSetting` resolution, and state transition invariants using `ZArith`, `List`, `Bool`, and `Lia`.

```coq
(** * BlinkWebUSBAlternateSettingSemantics.v
    Formal verification of WebUSB alternate settings validation and selection
    semantics in Chromium Blink (third_party/blink/renderer/modules/webusb/usb_interface.cc).
*)

Require Import Coq.ZArith.ZArith.
Require Import Coq.Lists.List.
Require Import Coq.Bool.Bool.
Require Import Coq.micromega.Lia.
Import ListNotations.

Open Scope Z_scope.

(** ** 1. Data Types and Hardware Descriptor Models *)

(** Represents device::mojom::blink::UsbAlternateInterfaceInfo *)
Record UsbAlternateInterfaceInfo : Type := mkAltInfo {
  bAlternateSetting : Z; (** uint8_t in [0, 255] *)
  bInterfaceClass   : Z;
  numEndpoints      : Z
}.

(** Represents the state of a USBInterface in Blink paired with its parent USBDevice state *)
Record BlinkUSBInterfaceState : Type := mkInterfaceState {
  interface_number       : Z;
  device_opened          : bool;
  configuration_active   : bool;
  interface_claimed      : bool;
  alternates             : list UsbAlternateInterfaceInfo;
  selected_alternate_idx : Z
}.

(** DOMException error codes relevant to WebUSB §3.5 *)
Inductive WebUSBError : Type :=
  | InvalidStateError : WebUSBError
  | NotFoundError     : WebUSBError.

(** Result of a WebUSB Promise operation *)
Inductive Result (A : Type) : Type :=
  | Ok  : A -> Result A
  | Err : WebUSBError -> Result A.

Arguments Ok {A} _.
Arguments Err {A} _.

(** ** 2. Core Predicates and Validation Functions *)

(** Number of alternate settings available on the interface *)
Definition num_alternate_settings (st : BlinkUSBInterfaceState) : Z :=
  Z.of_nat (length (alternates st)).

(** Decidable boolean check for alternate index validity:
    0 <= alt_idx < num_alternate_settings *)
Definition is_valid_alt_idx_b (alt_idx : Z) (num_alts : Z) : bool :=
  (0 <=? alt_idx) && (alt_idx <? num_alts).

(** Propositional specification of alternate index validity *)
Definition valid_alt_idx (alt_idx : Z) (num_alts : Z) : Prop :=
  0 <= alt_idx < num_alts.

(** Well-formedness invariant of a Blink USBInterface object corresponding to
    DCHECK_LT(alternate_index, Info().alternates.size()) in usb_interface.cc *)
Definition interface_state_wf (st : BlinkUSBInterfaceState) : Prop :=
  num_alternate_settings st > 0 /\
  valid_alt_idx (selected_alternate_idx st) (num_alternate_settings st).

(** Lookup an alternate index by index in the alternates vector *)
Fixpoint nth_alt_opt (l : list UsbAlternateInterfaceInfo) (idx : Z) : option UsbAlternateInterfaceInfo :=
  match l with
  | [] => None
  | x :: xs =>
      if idx <? 0 then None
      else if idx =? 0 then Some x
      else nth_alt_opt xs (idx - 1)
  end.

(** Search for the index of a given bAlternateSetting value, mirroring
    Blink's FindAlternateIndex in usb_device.cc *)
Fixpoint find_alt_idx_aux (l : list UsbAlternateInterfaceInfo) (setting_val : Z) (curr_idx : Z) : option Z :=
  match l with
  | [] => None
  | x :: xs =>
      if bAlternateSetting x =? setting_val then Some curr_idx
      else find_alt_idx_aux xs setting_val (curr_idx + 1)
  end.

Definition find_alt_idx (st : BlinkUSBInterfaceState) (setting_val : Z) : option Z :=
  find_alt_idx_aux (alternates st) setting_val 0.

(** Direct index selection semantics (constructing USBAlternateInterface(this, alt_idx)) *)
Definition select_alternate_by_index (st : BlinkUSBInterfaceState) (alt_idx : Z)
  : Result BlinkUSBInterfaceState :=
  if negb (device_opened st) then Err InvalidStateError
  else if negb (configuration_active st) then Err InvalidStateError
  else if negb (interface_claimed st) then Err InvalidStateError
  else if is_valid_alt_idx_b alt_idx (num_alternate_settings st) then
    Ok (mkInterfaceState
          (interface_number st)
          (device_opened st)
          (configuration_active st)
          (interface_claimed st)
          (alternates st)
          alt_idx)
  else
    Err NotFoundError.

(** WebUSB §3.5 selectAlternateInterface(interfaceNumber, alternateSetting) *)
Definition select_alternate_setting (st : BlinkUSBInterfaceState) (setting_val : Z)
  : Result BlinkUSBInterfaceState :=
  if negb (device_opened st) then Err InvalidStateError
  else if negb (configuration_active st) then Err InvalidStateError
  else if negb (interface_claimed st) then Err InvalidStateError
  else
    match find_alt_idx st setting_val with
    | Some idx => select_alternate_by_index st idx
    | None => Err NotFoundError
    end.

(** Blink USBInterface::alternate() getter semantics *)
Definition get_active_alternate (st : BlinkUSBInterfaceState) : option UsbAlternateInterfaceInfo :=
  if interface_claimed st then
    nth_alt_opt (alternates st) (selected_alternate_idx st)
  else
    None.

(** ** 3. Formal Theorems and Complete Proofs *)

(** *** Theorem 1: Boolean reflection for alternate setting index bounds *)
Theorem is_valid_alt_idx_b_iff :
  forall (alt_idx num_alts : Z),
    is_valid_alt_idx_b alt_idx num_alts = true <-> valid_alt_idx alt_idx num_alts.
Proof.
  intros alt_idx num_alts.
  unfold is_valid_alt_idx_b, valid_alt_idx.
  rewrite andb_true_iff.
  rewrite Z.leb_le.
  rewrite Z.ltb_lt.
  tauto.
Qed.

(** *** Theorem 2: Negative reflection (Invalid index iff out of bounds) *)
Theorem is_valid_alt_idx_b_false_iff :
  forall (alt_idx num_alts : Z),
    is_valid_alt_idx_b alt_idx num_alts = false <-> (alt_idx < 0 \/ alt_idx >= num_alts).
Proof.
  intros alt_idx num_alts.
  unfold is_valid_alt_idx_b.
  rewrite andb_false_iff.
  rewrite Z.leb_gt.
  rewrite Z.ltb_ge.
  lia.
Qed.

(** *** Lemma 3: Safe vector indexing within bounds *)
Lemma nth_alt_opt_some_iff :
  forall (l : list UsbAlternateInterfaceInfo) (idx : Z),
    (exists info, nth_alt_opt l idx = Some info) <-> (0 <= idx < Z.of_nat (length l)).
Proof.
  induction l as [| x xs IH]; intros idx.
  - simpl. split.
    + intros [info H]. discriminate H.
    + intros H. lia.
  - simpl length. rewrite Nat2Z.inj_succ. simpl nth_alt_opt.
    destruct (idx <? 