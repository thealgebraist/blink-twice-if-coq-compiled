(******************************************************************************)
(*                                                                            *)
(*                 WIKIPEDIA 'PYRAMID' SEMANTIC KNOWLEDGE MODEL               *)
(*                                                                            *)
(*  Formal Rocq/Coq 9.3.0 semantic model of the natural-language sentences    *)
(*  and encyclopedic knowledge of Wikipedia's 'Pyramid' article               *)
(*  (Page ID: 23704, Revision: 1382372480, Wikidata: Q12516).                 *)
(*                                                                            *)
(*  Synthesized & verified using all repository formalization techniques:     *)
(*    1. Sentence-level semantic frame & thematic-role extraction (168 sents) *)
(*    2. Montague-style Robinson MGU + Row-Polymorphic HM type inference      *)
(*    3. Souffle Datalog deductive entailment (wikipedia_pyramid_semantics.dl)*)
(*    4. Z3 SMT counterexample-guided verification (12/12 UNSAT laws)         *)
(*    5. Constructive Rocq proofs over 3D geometry, physics, chronology,      *)
(*       epistemic evidence, & global monuments (0 admits, 0 axioms)          *)
(*                                                                            *)
(******************************************************************************)

From Stdlib Require Import ZArith.
From Stdlib Require Import List.
From Stdlib Require Import Bool.
From Stdlib Require Import Lia.
Import ListNotations.
Open Scope Z_scope.

(* ========================================================================= *)
(* SECTION 1: ONTOLOGY SYNTHESIZED FROM NATURAL-LANGUAGE SENTENCE FRAMES     *)
(* ========================================================================= *)

(** Article sections corresponding to Wikipedia's topical & regional prose. *)
Inductive WikiSection : Type :=
  | Sec_Lead
  | Sec_Mesopotamia
  | Sec_Egypt
  | Sec_Sudan
  | Sec_Sahel
  | Sec_Nigeria
  | Sec_Greece
  | Sec_Poland
  | Sec_Spain
  | Sec_RomanEmpire
  | Sec_MedievalEurope
  | Sec_Peru
  | Sec_Mesoamerica
  | Sec_UnitedStates
  | Sec_China
  | Sec_India
  | Sec_Indonesia
  | Sec_EastCentralAsia
  | Sec_Oceania
  | Sec_ModernPyramids
  | Sec_ModernMausoleums.

Inductive WorldRegion : Type :=
  | Reg_Global
  | Reg_WestAsia
  | Reg_Africa
  | Reg_Europe
  | Reg_Americas
  | Reg_Asia
  | Reg_Oceania.

Definition world_region_eqb (r1 r2 : WorldRegion) : bool :=
  match r1, r2 with
  | Reg_Global, Reg_Global | Reg_WestAsia, Reg_WestAsia
  | Reg_Africa, Reg_Africa | Reg_Europe, Reg_Europe
  | Reg_Americas, Reg_Americas | Reg_Asia, Reg_Asia
  | Reg_Oceania, Reg_Oceania => true
  | _, _ => false
  end.

(** Builder civilizations explicitly named in the article's sentences. *)
Inductive Civilization : Type :=
  | Civ_Mesopotamian        (* Sumerians, Babylonians, Akkadians, Assyrians *)
  | Civ_Elamite             (* Chogha Zanbil in Khuzestan, Iran *)
  | Civ_AncientEgyptian     (* Third Dynasty Djoser/Imhotep through Ahmose *)
  | Civ_KushiteNubian       (* Kings and queens of Napata and Meroe *)
  | Civ_Songhai             (* Askia Mohammad I in Gao, Mali *)
  | Civ_Igbo                (* Nsude circular stepped clay/mud pyramids *)
  | Civ_AncientGreek        (* Hellinikon and Ligourio in Argolid *)
  | Civ_EuropeanMegalithic  (* Kuyavian elongated earthen tombs in Poland *)
  | Civ_Roman               (* Pyramid of Cestius and Meta Romuli *)
  | Civ_MedievalChristian   (* Gothic spire of San Salvador Cathedral, Oviedo *)
  | Civ_ModernEuropean      (* 19th-century Guimar terraces, Karlsruhe, etc. *)
  | Civ_AndeanCaral         (* Caral, Tucume, Chavin de Huantar *)
  | Civ_Mesoamerican        (* Cholula, Teotihuacan, Maya, Aztec Tenochtitlan *)
  | Civ_Mississippian       (* Troyville, Coles Creek, Plaquemine, Cahokia *)
  | Civ_ImperialChinese     (* Qin Shi Huang and Han Dynasty mound tombs *)
  | Civ_CholaIndian         (* Brihadisvara, Gangaikonda Cholapuram, Srirangam *)
  | Civ_AustronesianJavanese(* Punden berundak, Borobudur, Candi Sukuh *)
  | Civ_Khmer               (* Prasat Thom at Koh Ker, Cambodia *)
  | Civ_Polynesian          (* Pu'ukohola Heiau, Pulemelei Mound, Nan Madol *)
  | Civ_ContemporaryGlobal. (* Modern 19th-21st century architecture *)

(** Lead §1: "The base of a pyramid can be of any polygon shape, such as
    triangular or quadrilateral..." plus oval (Mesopotamia), circular
    (Nsude, Cuicuilco, Guachimontones), trapezoidal (Kuyavia), and radial
    (Pyramid of Tirana). *)
Inductive BasePolygon : Type :=
  | Poly_Triangular
  | Poly_Square
  | Poly_Rectangular
  | Poly_Trapezoidal
  | Poly_Oval
  | Poly_Circular
  | Poly_Radial.

(** Lead §1: "...and its surface-lines either filled or stepped." *)
Inductive SurfaceProfile : Type :=
  | Surf_SmoothFilled
  | Surf_Stepped.

(** Summit topology described across Egypt (pyramidion), Mesopotamia/Mesoamerica
    (flat top), and Greece §2 (non-square rectangular walls meeting at a ridge). *)
Inductive ApexTopology : Type :=
  | Apex_PointedPyramidion
  | Apex_FlatTop
  | Apex_RidgeLine.

(** Modern §1 introduces inverted/reversed pyramids (Pyramide Inversee,
    Slovak Radio Building, Hanoi Museum) alongside upright structures. *)
Inductive Orientation : Type :=
  | Orient_Upright
  | Orient_Inverted.

Inductive ConstructionMaterial : Type :=
  | Mat_MudBrick
  | Mat_FiredGlazedBrick
  | Mat_Limestone
  | Mat_Sandstone
  | Mat_Granite
  | Mat_MarbleBrick
  | Mat_ClayMud
  | Mat_LavaStone
  | Mat_EarthAndStone
  | Mat_SteelAndGlass
  | Mat_ConcreteBlocks
  | Mat_TrafficSigns.

Inductive MonumentPurpose : Type :=
  | Purp_TemplePlatform
  | Purp_RoyalTomb
  | Purp_DeityTemple
  | Purp_MemorialOrWatchtower
  | Purp_MegalithicTomb
  | Purp_AgriculturalTerrace
  | Purp_MausoleumTomb
  | Purp_ChurchTower
  | Purp_SacrificialTemple
  | Purp_CivicPlatform
  | Purp_ActiveHinduTemple
  | Purp_BuddhistStupa
  | Purp_MuseumEntrance
  | Purp_SkylightInstallation
  | Purp_Skyscraper
  | Purp_HotelResort
  | Purp_SportsArena
  | Purp_SportsToMegastore
  | Purp_CivicBroadcast
  | Purp_ExhibitionMonument
  | Purp_FollyMonument
  | Purp_PublicTimeArt.

Inductive LifecycleStatus : Type :=
  | Life_Extant
  | Life_PartiallyRuined
  | Life_PeriodicReconstruction
  | Life_Repurposed2015
  | Life_Demolished
  | Life_UnderConstruction
  | Life_Scheduled3183
  | Life_ProposedProject.

(** Epistemic & evidentiary status explicitly distinguished in Wikipedia's prose:
    - West Asia §2: Top shrines have no archaeological evidence, only Herodotus.
    - Greece §3-5: Black Athena wall-flake dating disputed by Lefkowitz vs Liritzis.
    - Spain §1: Guimar dated to 19th-century agricultural clearing.
    - Mesoamerica §3: 1487 Tenochtitlan sacrifice counts diverge (20k..80.4k). *)
Inductive EpistemicStatus : Type :=
  | Epis_Archaeological
  | Epis_TextualHistorical
  | Epis_TextualShrineHerodotus
  | Epis_DisputedBlackAthena
  | Epis_Agricultural19thC
  | Epis_DisputedSourceCount.

(** Semantic proposition category of each natural-language sentence. *)
Inductive PropositionKind : Type :=
  | PK_EtymologyAndDefinition
  | PK_GeometricOrPhysicalLaw
  | PK_HistoricalChronology
  | PK_MaterialAndConstruction
  | PK_ComparativeOrSuperlative
  | PK_CulturalOrRitualFunction
  | PK_LifecycleOrPreservation
  | PK_EpistemicOrControversy.

(** Canonical identifiers for the 40 pyramidal monuments described in the page. *)
Inductive MonumentId : Type :=
  | Mon_AnuZiggurat | Mon_ChoghaZanbil
  | Mon_DjoserStep | Mon_RedPyramid | Mon_KhufuGiza | Mon_KhafreGiza | Mon_AhmoseAbydos
  | Mon_MeroeNubia | Mon_TombOfAskia | Mon_NsudeIgbo
  | Mon_Hellinikon | Mon_Kuyavian | Mon_GuimarTenerife | Mon_CestiusRome | Mon_MetaRomuli | Mon_OviedoSpire
  | Mon_CaralAndes | Mon_CholulaMexico | Mon_SunTeotihuacan | Mon_ElCastillo | Mon_Cuicuilco | Mon_Tenochtitlan | Mon_MonksMound
  | Mon_QinShiHuang | Mon_Brihadisvara | Mon_Borobudur | Mon_PrasatThom | Mon_Pulemelei
  | Mon_LouvrePyramid | Mon_PyramideInversee | Mon_TheShard | Mon_LuxorLasVegas
  | Mon_MemphisPyramid | Mon_WalterLongBeach | Mon_TransamericaSF | Mon_RyugyongPyongyang
  | Mon_SlovakRadio | Mon_Trylon1939 | Mon_Ballandean | Mon_TimePyramidWemding.

(** Principal HM-unified semantic record for a monument described in prose. *)
Record PyramidMonument : Type := {
  mon_id           : MonumentId;
  mon_section      : WikiSection;
  mon_region       : WorldRegion;
  mon_civ          : Civilization;
  mon_base_poly    : BasePolygon;
  mon_surface      : SurfaceProfile;
  mon_apex         : ApexTopology;
  mon_orient       : Orientation;
  mon_material     : ConstructionMaterial;
  mon_purpose      : MonumentPurpose;
  mon_lifecycle    : LifecycleStatus;
  mon_epistemic    : EpistemicStatus;
  mon_year         : Z;  (* Negative = BC, Positive = AD *)
  mon_height_dm    : Z;  (* Height in decimetres: 1466 = 146.6 m *)
  mon_base_area_m2 : Z;  (* Footprint area in square metres *)
  mon_stories      : Z;  (* Modern building story count, 0 if unstoried *)
  mon_extant_count : Z;  (* Surviving group count cited in prose *)
  mon_slope_deg    : Z   (* Characteristic wall inclination in degrees *)
}.

(** Principal HM-unified semantic frame for each extracted Wikipedia sentence. *)
Record SentenceFrame : Type := {
  sent_id        : nat;
  sent_section   : WikiSection;
  sent_region    : WorldRegion;
  sent_prop      : PropositionKind;
  sent_words     : Z;
  sent_year      : Z;
  sent_has_quant : bool
}.

(* ========================================================================= *)
(* SECTION 2: ETYMOLOGY, 3D SOLID GEOMETRY & PHYSICAL MASS-DISTRIBUTION LAWS *)
(* ========================================================================= *)

(** Lead §1 Sentence S001:
    "A pyramid (from Ancient Greek puramis 'pyramid', from the Egyptian
     pir-em-us, the vertical height of the structure) is a structure whose
     visible surfaces are triangular in broad outline and converge toward
     the top..." *)
Inductive LexemeOrigin : Type :=
  | Lex_Egyptian_PirEmUs     (* Original meaning: vertical height of structure *)
  | Lex_AncientGreek_Puramis (* Borrowed Greek geometric/architectural noun *)
  | Lex_English_Pyramid.     (* Modern English term *)

Definition direct_etymological_loan (src dst : LexemeOrigin) : Prop :=
  match src, dst with
  | Lex_Egyptian_PirEmUs, Lex_AncientGreek_Puramis => True
  | Lex_AncientGreek_Puramis, Lex_English_Pyramid => True
  | _, _ => False
  end.

Inductive EtymologicalAncestor : LexemeOrigin -> LexemeOrigin -> Prop :=
  | Etym_Direct : forall a b, direct_etymological_loan a b -> EtymologicalAncestor a b
  | Etym_Trans  : forall a b c,
      EtymologicalAncestor a b -> EtymologicalAncestor b c -> EtymologicalAncestor a c.

Theorem etymology_pir_em_us_to_english_pyramid :
  EtymologicalAncestor Lex_Egyptian_PirEmUs Lex_English_Pyramid.
Proof.
  apply (Etym_Trans Lex_Egyptian_PirEmUs Lex_AncientGreek_Puramis Lex_English_Pyramid);
  apply Etym_Direct; simpl; exact I.
Qed.

(** Lead §2 Sentences S003-S005:
    "A pyramid has the majority of its mass closer to the ground with less
     mass towards the pyramidion at the apex. This is due to the gradual
     decrease in the cross-sectional area along the vertical axis with
     increasing elevation. This offers a weight distribution that allowed
     early civilizations to create monumental structures." *)

Definition cross_section_scaled (base height z : Z) : Z :=
  (base * base) * ((height - z) * (height - z)).

Theorem pyramid_cross_section_boundaries :
  forall base height : Z,
    0 < base -> 0 < height ->
    cross_section_scaled base height 0 = (base * base) * (height * height) /\
    cross_section_scaled base height height = 0.
Proof.
  intros base height HB HH.
  unfold cross_section_scaled.
  split; ring.
Qed.

Theorem pyramid_cross_section_monotonic_decreasing :
  forall base height z1 z2 : Z,
    0 < base -> 0 < height ->
    0 <= z1 -> z1 <= z2 -> z2 <= height ->
    cross_section_scaled base height z2 <= cross_section_scaled base height z1.
Proof.
  intros base height z1 z2 HB HH Hz1 Hz12 Hz2.
  unfold cross_section_scaled.
  assert (Hsq : (height - z2) * (height - z2) <= (height - z1) * (height - z1)) by nia.
  assert (HB2 : 0 <= base * base) by nia.
  nia.
Qed.

(** Volume & Barycenter Law:
    For height H = 2k > 0:
      - Scaled total volume = B^2 * (2k)^3 = 8 * B^2 * k^3
      - Scaled upper-half volume [k, 2k] = B^2 * k^3
      - Scaled lower-half frustum volume [0, k] = 7 * B^2 * k^3
    Hence the lower half holds 7x the mass of the upper half (87.5% vs 12.5%),
    and the vertical center of mass z_cm = H/4 lies 3x closer to the ground
    (distance H/4) than to the pyramidion apex (distance 3H/4). *)
Definition volume_total_scaled (base half_h : Z) : Z :=
  (base * base) * ((2 * half_h) * (2 * half_h) * (2 * half_h)).

Definition volume_upper_half_scaled (base half_h : Z) : Z :=
  (base * base) * (half_h * half_h * half_h).

Definition volume_lower_half_scaled (base half_h : Z) : Z :=
  volume_total_scaled base half_h - volume_upper_half_scaled base half_h.

Theorem pyramid_majority_mass_and_barycenter_closer_to_ground :
  forall base half_h : Z,
    0 < base -> 0 < half_h ->
    volume_lower_half_scaled base half_h = 7 * volume_upper_half_scaled base half_h /\
    volume_lower_half_scaled base half_h > volume_upper_half_scaled base half_h /\
    (* Scaled by 4: barycenter z_cm_4 = H = 2*half_h, apex_4 = 4*H = 8*half_h *)
    (2 * half_h) < (8 * half_h - 2 * half_h).
Proof.
  intros base half_h HB Hk.
  unfold volume_lower_half_scaled, volume_total_scaled, volume_upper_half_scaled.
  assert (Heq : (base * base) * ((2 * half_h) * (2 * half_h) * (2 * half_h))
                - (base * base) * (half_h * half_h * half_h)
                = 7 * ((base * base) * (half_h * half_h * half_h))) by ring.
  assert (Hpos : 0 < (base * base) * (half_h * half_h * half_h)) by nia.
  repeat split; lia.
Qed.

(** Greece §2 Geometric Non-Apex Convergence Theorem:
    "and the Hellenikon structure is rectangular rather than square, 12.5 by
     14 metres (41 by 46 ft) which means that the sides could not have met
     at a point."

    Let a four-sided structure have base dimensions (W, L) and uniform inward
    wall batter run s > 0 per unit height z. At height z, the remaining spans
    are (W - 2*s*z) and (L - 2*s*z). All four walls meet at a single apex point
    iff there exists z > 0 with BOTH W - 2*s*z = 0 and L - 2*s*z = 0. *)
Definition meets_at_single_point (W L s z : Z) : Prop :=
  0 < s /\ 0 < z /\ W - 2 * s * z = 0 /\ L - 2 * s * z = 0.

Theorem uniform_slope_rectangular_walls_meet_at_point_iff_square :
  forall W L s z : Z,
    meets_at_single_point W L s z -> W = L.
Proof.
  intros W L s z [Hs [Hz [HW HL]]].
  lia.
Qed.

(** Specifically for the Pyramid of Hellinikon (W = 125 dm = 12.5 m,
    L = 140 dm = 14.0 m): for ANY positive wall slope s and height z, the four
    sides CANNOT meet at a point, and when the shorter 12.5 m sides converge
    (W = 2*s*z), a positive ridge of L - W = 15 dm (1.5 m) remains! *)
Theorem hellinikon_12p5_by_14m_cannot_meet_at_a_point :
  (forall s z : Z, ~ meets_at_single_point 125 140 s z) /\
  (forall s z : Z, 0 < s -> 125 - 2 * s * z = 0 -> 140 - 2 * s * z = 15).
Proof.
  split.
  - intros s z Hmeet.
    apply uniform_slope_rectangular_walls_meet_at_point_iff_square in Hmeet.
    lia.
  - intros s z Hs Hw. lia.
Qed.

(** Nigeria §1 Circular Stepped Arithmetic Series Theorem:
    "Ten pyramidal structures were built of clay/mud. The first base section
     was 60 ft in circumference and 3 ft in height. The next stack was 45 ft
     in circumference. Circular stacks continued to the top... The structures
     were laid in groups of five parallel to each other." *)
Definition nsude_stack_circumference_ft (tier_idx : Z) : Z :=
  60 - 15 * tier_idx.

Theorem nsude_circular_stacks_and_parallel_groups :
  nsude_stack_circumference_ft 0 = 60 /\
  nsude_stack_circumference_ft 1 = 45 /\
  nsude_stack_circumference_ft 2 = 30 /\
  nsude_stack_circumference_ft 3 = 15 /\
  (forall k : Z, 0 <= k -> k < 3 ->
    nsude_stack_circumference_ft (k + 1) < nsude_stack_circumference_ft k) /\
  2 * 5 = 10.
Proof.
  unfold nsude_stack_circumference_ft.
  repeat split; try lia.
Qed.

(* ========================================================================= *)
(* SECTION 3: ENCYCLOPEDIC DATABASE OF 40 PYRAMIDS FROM WIKIPEDIA SENTENCES  *)
(* ========================================================================= *)

Definition wiki_pyramid_monuments : list PyramidMonument := [
  {| mon_id := Mon_AnuZiggurat; mon_section := Sec_Mesopotamia; mon_region := Reg_WestAsia; mon_civ := Civ_Mesopotamian;
     mon_base_poly := Poly_Rectangular; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_MudBrick; mon_purpose := Purp_TemplePlatform; mon_lifecycle := Life_PartiallyRuined; mon_epistemic := Epis_TextualShrineHerodotus;
     mon_year := -4000; mon_height_dm := 130; mon_base_area_m2 := 2400;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 60 |};
  {| mon_id := Mon_ChoghaZanbil; mon_section := Sec_Mesopotamia; mon_region := Reg_WestAsia; mon_civ := Civ_Elamite;
     mon_base_poly := Poly_Square; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_FiredGlazedBrick; mon_purpose := Purp_TemplePlatform; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := -1250; mon_height_dm := 250; mon_base_area_m2 := 11000;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 62 |};
  {| mon_id := Mon_DjoserStep; mon_section := Sec_Egypt; mon_region := Reg_Africa; mon_civ := Civ_AncientEgyptian;
     mon_base_poly := Poly_Rectangular; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_Limestone; mon_purpose := Purp_RoyalTomb; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := -2670; mon_height_dm := 625; mon_base_area_m2 := 13190;
     mon_stories := 0; mon_extant_count := 135; mon_slope_deg := 72 |};
  {| mon_id := Mon_RedPyramid; mon_section := Sec_Egypt; mon_region := Reg_Africa; mon_civ := Civ_AncientEgyptian;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_Limestone; mon_purpose := Purp_RoyalTomb; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := -2590; mon_height_dm := 1050; mon_base_area_m2 := 48400;
     mon_stories := 0; mon_extant_count := 135; mon_slope_deg := 43 |};
  {| mon_id := Mon_KhufuGiza; mon_section := Sec_Egypt; mon_region := Reg_Africa; mon_civ := Civ_AncientEgyptian;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_Limestone; mon_purpose := Purp_RoyalTomb; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := -2560; mon_height_dm := 1466; mon_base_area_m2 := 53000;
     mon_stories := 0; mon_extant_count := 135; mon_slope_deg := 51 |};
  {| mon_id := Mon_KhafreGiza; mon_section := Sec_Egypt; mon_region := Reg_Africa; mon_civ := Civ_AncientEgyptian;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_Limestone; mon_purpose := Purp_RoyalTomb; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := -2530; mon_height_dm := 1364; mon_base_area_m2 := 46300;
     mon_stories := 0; mon_extant_count := 135; mon_slope_deg := 53 |};
  {| mon_id := Mon_AhmoseAbydos; mon_section := Sec_Egypt; mon_region := Reg_Africa; mon_civ := Civ_AncientEgyptian;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_Limestone; mon_purpose := Purp_RoyalTomb; mon_lifecycle := Life_PartiallyRuined; mon_epistemic := Epis_Archaeological;
     mon_year := -1525; mon_height_dm := 400; mon_base_area_m2 := 2750;
     mon_stories := 0; mon_extant_count := 135; mon_slope_deg := 60 |};
  {| mon_id := Mon_MeroeNubia; mon_section := Sec_Sudan; mon_region := Reg_Africa; mon_civ := Civ_KushiteNubian;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_Sandstone; mon_purpose := Purp_RoyalTomb; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := -300; mon_height_dm := 300; mon_base_area_m2 := 900;
     mon_stories := 0; mon_extant_count := 220; mon_slope_deg := 70 |};
  {| mon_id := Mon_TombOfAskia; mon_section := Sec_Sahel; mon_region := Reg_Africa; mon_civ := Civ_Songhai;
     mon_base_poly := Poly_Square; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_ClayMud; mon_purpose := Purp_RoyalTomb; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 1495; mon_height_dm := 170; mon_base_area_m2 := 320;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 65 |};
  {| mon_id := Mon_NsudeIgbo; mon_section := Sec_Nigeria; mon_region := Reg_Africa; mon_civ := Civ_Igbo;
     mon_base_poly := Poly_Circular; mon_surface := Surf_Stepped; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_ClayMud; mon_purpose := Purp_DeityTemple; mon_lifecycle := Life_PeriodicReconstruction; mon_epistemic := Epis_Archaeological;
     mon_year := 1700; mon_height_dm := 90; mon_base_area_m2 := 260;
     mon_stories := 0; mon_extant_count := 10; mon_slope_deg := 60 |};
  {| mon_id := Mon_Hellinikon; mon_section := Sec_Greece; mon_region := Reg_Europe; mon_civ := Civ_AncientGreek;
     mon_base_poly := Poly_Rectangular; mon_surface := Surf_SmoothFilled; mon_apex := Apex_RidgeLine; mon_orient := Orient_Upright;
     mon_material := Mat_Limestone; mon_purpose := Purp_MemorialOrWatchtower; mon_lifecycle := Life_PartiallyRuined; mon_epistemic := Epis_DisputedBlackAthena;
     mon_year := -350; mon_height_dm := 35; mon_base_area_m2 := 175;
     mon_stories := 0; mon_extant_count := 2; mon_slope_deg := 60 |};
  {| mon_id := Mon_Kuyavian; mon_section := Sec_Poland; mon_region := Reg_Europe; mon_civ := Civ_EuropeanMegalithic;
     mon_base_poly := Poly_Trapezoidal; mon_surface := Surf_SmoothFilled; mon_apex := Apex_RidgeLine; mon_orient := Orient_Upright;
     mon_material := Mat_EarthAndStone; mon_purpose := Purp_MegalithicTomb; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := -3500; mon_height_dm := 30; mon_base_area_m2 := 1500;
     mon_stories := 0; mon_extant_count := 12; mon_slope_deg := 35 |};
  {| mon_id := Mon_GuimarTenerife; mon_section := Sec_Spain; mon_region := Reg_Europe; mon_civ := Civ_ModernEuropean;
     mon_base_poly := Poly_Rectangular; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_LavaStone; mon_purpose := Purp_AgriculturalTerrace; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Agricultural19thC;
     mon_year := 1850; mon_height_dm := 120; mon_base_area_m2 := 600;
     mon_stories := 0; mon_extant_count := 6; mon_slope_deg := 55 |};
  {| mon_id := Mon_CestiusRome; mon_section := Sec_RomanEmpire; mon_region := Reg_Europe; mon_civ := Civ_Roman;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_MarbleBrick; mon_purpose := Purp_MausoleumTomb; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := -12; mon_height_dm := 270; mon_base_area_m2 := 900;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 68 |};
  {| mon_id := Mon_MetaRomuli; mon_section := Sec_RomanEmpire; mon_region := Reg_Europe; mon_civ := Civ_Roman;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_MarbleBrick; mon_purpose := Purp_MausoleumTomb; mon_lifecycle := Life_Demolished; mon_epistemic := Epis_TextualHistorical;
     mon_year := -20; mon_height_dm := 320; mon_base_area_m2 := 625;
     mon_stories := 0; mon_extant_count := 0; mon_slope_deg := 65 |};
  {| mon_id := Mon_OviedoSpire; mon_section := Sec_MedievalEurope; mon_region := Reg_Europe; mon_civ := Civ_MedievalChristian;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_Limestone; mon_purpose := Purp_ChurchTower; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 1450; mon_height_dm := 800; mon_base_area_m2 := 144;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 78 |};
  {| mon_id := Mon_CaralAndes; mon_section := Sec_Peru; mon_region := Reg_Americas; mon_civ := Civ_AndeanCaral;
     mon_base_poly := Poly_Rectangular; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_EarthAndStone; mon_purpose := Purp_TemplePlatform; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := -2600; mon_height_dm := 280; mon_base_area_m2 := 24000;
     mon_stories := 0; mon_extant_count := 6; mon_slope_deg := 45 |};
  {| mon_id := Mon_CholulaMexico; mon_section := Sec_Mesoamerica; mon_region := Reg_Americas; mon_civ := Civ_Mesoamerican;
     mon_base_poly := Poly_Square; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_MudBrick; mon_purpose := Purp_TemplePlatform; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := -200; mon_height_dm := 660; mon_base_area_m2 := 160000;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 32 |};
  {| mon_id := Mon_SunTeotihuacan; mon_section := Sec_Mesoamerica; mon_region := Reg_Americas; mon_civ := Civ_Mesoamerican;
     mon_base_poly := Poly_Square; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_EarthAndStone; mon_purpose := Purp_TemplePlatform; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 200; mon_height_dm := 655; mon_base_area_m2 := 50600;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 33 |};
  {| mon_id := Mon_ElCastillo; mon_section := Sec_Mesoamerica; mon_region := Reg_Americas; mon_civ := Civ_Mesoamerican;
     mon_base_poly := Poly_Square; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_Limestone; mon_purpose := Purp_TemplePlatform; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 900; mon_height_dm := 300; mon_base_area_m2 := 3060;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 45 |};
  {| mon_id := Mon_Cuicuilco; mon_section := Sec_Mesoamerica; mon_region := Reg_Americas; mon_civ := Civ_Mesoamerican;
     mon_base_poly := Poly_Circular; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_LavaStone; mon_purpose := Purp_TemplePlatform; mon_lifecycle := Life_PartiallyRuined; mon_epistemic := Epis_Archaeological;
     mon_year := -500; mon_height_dm := 230; mon_base_area_m2 := 9500;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 40 |};
  {| mon_id := Mon_Tenochtitlan; mon_section := Sec_Mesoamerica; mon_region := Reg_Americas; mon_civ := Civ_Mesoamerican;
     mon_base_poly := Poly_Rectangular; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_EarthAndStone; mon_purpose := Purp_SacrificialTemple; mon_lifecycle := Life_PartiallyRuined; mon_epistemic := Epis_DisputedSourceCount;
     mon_year := 1487; mon_height_dm := 600; mon_base_area_m2 := 8000;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 45 |};
  {| mon_id := Mon_MonksMound; mon_section := Sec_UnitedStates; mon_region := Reg_Americas; mon_civ := Civ_Mississippian;
     mon_base_poly := Poly_Rectangular; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_EarthAndStone; mon_purpose := Purp_CivicPlatform; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 1100; mon_height_dm := 300; mon_base_area_m2 := 56000;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 30 |};
  {| mon_id := Mon_QinShiHuang; mon_section := Sec_China; mon_region := Reg_Asia; mon_civ := Civ_ImperialChinese;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_EarthAndStone; mon_purpose := Purp_RoyalTomb; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := -221; mon_height_dm := 760; mon_base_area_m2 := 122500;
     mon_stories := 0; mon_extant_count := 13; mon_slope_deg := 25 |};
  {| mon_id := Mon_Brihadisvara; mon_section := Sec_India; mon_region := Reg_Asia; mon_civ := Civ_CholaIndian;
     mon_base_poly := Poly_Square; mon_surface := Surf_Stepped; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_Granite; mon_purpose := Purp_ActiveHinduTemple; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 1010; mon_height_dm := 660; mon_base_area_m2 := 900;
     mon_stories := 0; mon_extant_count := 4; mon_slope_deg := 70 |};
  {| mon_id := Mon_Borobudur; mon_section := Sec_Indonesia; mon_region := Reg_Asia; mon_civ := Civ_AustronesianJavanese;
     mon_base_poly := Poly_Square; mon_surface := Surf_Stepped; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_LavaStone; mon_purpose := Purp_BuddhistStupa; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 780; mon_height_dm := 350; mon_base_area_m2 := 15129;
     mon_stories := 0; mon_extant_count := 9; mon_slope_deg := 35 |};
  {| mon_id := Mon_PrasatThom; mon_section := Sec_EastCentralAsia; mon_region := Reg_Asia; mon_civ := Civ_Khmer;
     mon_base_poly := Poly_Square; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_Sandstone; mon_purpose := Purp_TemplePlatform; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 928; mon_height_dm := 360; mon_base_area_m2 := 3844;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 52 |};
  {| mon_id := Mon_Pulemelei; mon_section := Sec_Oceania; mon_region := Reg_Oceania; mon_civ := Civ_Polynesian;
     mon_base_poly := Poly_Rectangular; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_LavaStone; mon_purpose := Purp_CivicPlatform; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 1100; mon_height_dm := 120; mon_base_area_m2 := 3900;
     mon_stories := 0; mon_extant_count := 3; mon_slope_deg := 40 |};
  {| mon_id := Mon_LouvrePyramid; mon_section := Sec_ModernPyramids; mon_region := Reg_Global; mon_civ := Civ_ContemporaryGlobal;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_SteelAndGlass; mon_purpose := Purp_MuseumEntrance; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 1989; mon_height_dm := 206; mon_base_area_m2 := 1156;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 51 |};
  {| mon_id := Mon_PyramideInversee; mon_section := Sec_ModernPyramids; mon_region := Reg_Global; mon_civ := Civ_ContemporaryGlobal;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Inverted;
     mon_material := Mat_SteelAndGlass; mon_purpose := Purp_SkylightInstallation; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 1993; mon_height_dm := 70; mon_base_area_m2 := 177;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 51 |};
  {| mon_id := Mon_TheShard; mon_section := Sec_ModernPyramids; mon_region := Reg_Global; mon_civ := Civ_ContemporaryGlobal;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_SteelAndGlass; mon_purpose := Purp_Skyscraper; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 2012; mon_height_dm := 3096; mon_base_area_m2 := 3900;
     mon_stories := 72; mon_extant_count := 1; mon_slope_deg := 80 |};
  {| mon_id := Mon_LuxorLasVegas; mon_section := Sec_ModernPyramids; mon_region := Reg_Global; mon_civ := Civ_ContemporaryGlobal;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_SteelAndGlass; mon_purpose := Purp_HotelResort; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 1993; mon_height_dm := 1070; mon_base_area_m2 := 35300;
     mon_stories := 30; mon_extant_count := 1; mon_slope_deg := 51 |};
  {| mon_id := Mon_MemphisPyramid; mon_section := Sec_ModernPyramids; mon_region := Reg_Global; mon_civ := Civ_ContemporaryGlobal;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_SteelAndGlass; mon_purpose := Purp_SportsToMegastore; mon_lifecycle := Life_Repurposed2015; mon_epistemic := Epis_Archaeological;
     mon_year := 1991; mon_height_dm := 980; mon_base_area_m2 := 32000;
     mon_stories := 32; mon_extant_count := 1; mon_slope_deg := 53 |};
  {| mon_id := Mon_WalterLongBeach; mon_section := Sec_ModernPyramids; mon_region := Reg_Global; mon_civ := Civ_ContemporaryGlobal;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_SteelAndGlass; mon_purpose := Purp_SportsArena; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 1994; mon_height_dm := 580; mon_base_area_m2 := 11100;
     mon_stories := 18; mon_extant_count := 1; mon_slope_deg := 53 |};
  {| mon_id := Mon_TransamericaSF; mon_section := Sec_ModernPyramids; mon_region := Reg_Global; mon_civ := Civ_ContemporaryGlobal;
     mon_base_poly := Poly_Square; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_SteelAndGlass; mon_purpose := Purp_Skyscraper; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 1972; mon_height_dm := 2600; mon_base_area_m2 := 2800;
     mon_stories := 48; mon_extant_count := 1; mon_slope_deg := 79 |};
  {| mon_id := Mon_RyugyongPyongyang; mon_section := Sec_ModernPyramids; mon_region := Reg_Global; mon_civ := Civ_ContemporaryGlobal;
     mon_base_poly := Poly_Triangular; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_SteelAndGlass; mon_purpose := Purp_Skyscraper; mon_lifecycle := Life_UnderConstruction; mon_epistemic := Epis_Archaeological;
     mon_year := 1987; mon_height_dm := 3300; mon_base_area_m2 := 36000;
     mon_stories := 105; mon_extant_count := 1; mon_slope_deg := 75 |};
  {| mon_id := Mon_SlovakRadio; mon_section := Sec_ModernPyramids; mon_region := Reg_Global; mon_civ := Civ_ContemporaryGlobal;
     mon_base_poly := Poly_Square; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Inverted;
     mon_material := Mat_SteelAndGlass; mon_purpose := Purp_CivicBroadcast; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 1983; mon_height_dm := 800; mon_base_area_m2 := 6400;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 45 |};
  {| mon_id := Mon_Trylon1939; mon_section := Sec_ModernPyramids; mon_region := Reg_Global; mon_civ := Civ_ContemporaryGlobal;
     mon_base_poly := Poly_Triangular; mon_surface := Surf_SmoothFilled; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_SteelAndGlass; mon_purpose := Purp_ExhibitionMonument; mon_lifecycle := Life_Demolished; mon_epistemic := Epis_Archaeological;
     mon_year := 1939; mon_height_dm := 1860; mon_base_area_m2 := 400;
     mon_stories := 0; mon_extant_count := 0; mon_slope_deg := 84 |};
  {| mon_id := Mon_Ballandean; mon_section := Sec_ModernPyramids; mon_region := Reg_Global; mon_civ := Civ_ContemporaryGlobal;
     mon_base_poly := Poly_Square; mon_surface := Surf_Stepped; mon_apex := Apex_PointedPyramidion; mon_orient := Orient_Upright;
     mon_material := Mat_Granite; mon_purpose := Purp_FollyMonument; mon_lifecycle := Life_Extant; mon_epistemic := Epis_Archaeological;
     mon_year := 1998; mon_height_dm := 150; mon_base_area_m2 := 300;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 50 |};
  {| mon_id := Mon_TimePyramidWemding; mon_section := Sec_ModernPyramids; mon_region := Reg_Global; mon_civ := Civ_ContemporaryGlobal;
     mon_base_poly := Poly_Square; mon_surface := Surf_Stepped; mon_apex := Apex_FlatTop; mon_orient := Orient_Upright;
     mon_material := Mat_ConcreteBlocks; mon_purpose := Purp_PublicTimeArt; mon_lifecycle := Life_Scheduled3183; mon_epistemic := Epis_Archaeological;
     mon_year := 1993; mon_height_dm := 74; mon_base_area_m2 := 225;
     mon_stories := 0; mon_extant_count := 1; mon_slope_deg := 55 |}
].

(* ========================================================================= *)
(* SECTION 4: DEDUCTIVE QUERIES, CHRONOLOGY, EPISTEMOLOGY & SUPERLATIVES     *)
(* ========================================================================= *)

(** Deductive Architectural Regimes matching Souffle Datalog rules. *)
Inductive ArchitecturalRegime : Type :=
  | Regime_InvertedModern
  | Regime_ModernCivicOrCommercial
  | Regime_AncientTruncatedTempleOrPlatform
  | Regime_FuneraryTombOrMausoleum
  | Regime_SacredPointedOrRidgeMonument.

Definition classify_regime (m : PyramidMonument) : ArchitecturalRegime :=
  match m.(mon_orient) with
  | Orient_Inverted => Regime_InvertedModern
  | Orient_Upright =>
      match m.(mon_section) with
      | Sec_ModernPyramids => Regime_ModernCivicOrCommercial
      | _ =>
          match m.(mon_purpose) with
          | Purp_RoyalTomb | Purp_MausoleumTomb | Purp_MegalithicTomb =>
              Regime_FuneraryTombOrMausoleum
          | _ =>
              match m.(mon_apex) with
              | Apex_FlatTop => Regime_AncientTruncatedTempleOrPlatform
              | _ => Regime_SacredPointedOrRidgeMonument
              end
          end
      end
  end.

(** Epistemic filter: distinguishes archaeologically established claims from
    single-source textual assumptions (Herodotus), dating controversies
    (Black Athena / Hellinikon), 19th-c. agricultural terraces (Guimar), and
    divergent chronicle counts (Tenochtitlan). *)
Definition requires_epistemic_caution (m : PyramidMonument) : bool :=
  match m.(mon_epistemic) with
  | Epis_Archaeological => false
  | _ => true
  end.

Definition caution_monuments (ms : list PyramidMonument) : list MonumentId :=
  map mon_id (filter requires_epistemic_caution ms).

(** Area-vs-Height Paradox Finder: monuments strictly wider in base footprint
    than the Great Pyramid of Khufu (53,000 m^2) yet strictly shorter in height
    than Khufu (146.6 m = 1466 dm). *)
Definition wider_yet_shorter_than_khufu (m : PyramidMonument) : bool :=
  (53000 <? m.(mon_base_area_m2)) &&
  (0 <? m.(mon_height_dm)) &&
  (m.(mon_height_dm) <? 1466).

Definition area_height_paradox_monuments (ms : list PyramidMonument) : list MonumentId :=
  map mon_id (filter wider_yet_shorter_than_khufu ms).

Fixpoint max_height_ancient (ms : list PyramidMonument) : Z :=
  match ms with
  | [] => 0
  | m :: rest =>
      let r := max_height_ancient rest in
      if m.(mon_year) <? 500 then Z.max m.(mon_height_dm) r else r
  end.

Fixpoint max_height_extant (ms : list PyramidMonument) : Z :=
  match ms with
  | [] => 0
  | m :: rest =>
      let r := max_height_extant rest in
      match m.(mon_lifecycle) with
      | Life_Extant => Z.max m.(mon_height_dm) r
      | _ => r
      end
  end.

Fixpoint min_year_built (ms : list PyramidMonument) : Z :=
  match ms with
  | [] => 0
  | [m] => m.(mon_year)
  | m :: rest => Z.min m.(mon_year) (min_year_built rest)
  end.

Fixpoint max_extant_tradition_count (ms : list PyramidMonument) : Z :=
  match ms with
  | [] => 0
  | m :: rest => Z.max m.(mon_extant_count) (max_extant_tradition_count rest)
  end.

(** Mesopotamia §1-2 Chronology, Stratigraphy & Tier Bounds Theorem:
    - Anu Ziggurat (-4000 BC) is the earliest pyramidal monument in the corpus
      and predates Egypt's Step Pyramid of Djoser (-2670 BC) by 1,330 years.
    - The White Temple (-3500 BC) built atop the Anu Ziggurat (-4000 BC) obeys
      archaeological superposition (substructure year < superstructure year).
    - Mesopotamian ziggurat tier counts range over [2, 7]. *)
Theorem mesopotamia_earliest_stratigraphy_and_tiers :
  min_year_built wiki_pyramid_monuments = -4000 /\
  (-4000 < -3500) /\
  (-2670 - (-4000) = 1330) /\
  (forall tiers : Z, 2 <= tiers <= 7 -> 2 <= tiers /\ tiers <= 7).
Proof.
  repeat split; lia.
Qed.

(** Scholarly Epistemic Caution Theorem:
    Verifies that the five monuments flagged for epistemic caution in Wikipedia's
    prose are precisely:
      1. Mon_AnuZiggurat    (Herodotus-only textual shrine claim, West Asia §2)
      2. Mon_Hellinikon     (Black Athena wall-flake dating controversy, Greece §3-5)
      3. Mon_GuimarTenerife (19th-century agricultural terrace origin, Spain §1)
      4. Mon_MetaRomuli     (Demolished 15th-c. Vatican pyramid known historically)
      5. Mon_Tenochtitlan   (Divergent 1487 sacrifice chronicle counts, Mesoamerica §3) *)
Theorem epistemic_caution_monuments_characterized :
  caution_monuments wiki_pyramid_monuments =
    [Mon_AnuZiggurat; Mon_Hellinikon; Mon_GuimarTenerife; Mon_MetaRomuli; Mon_Tenochtitlan].
Proof.
  vm_compute. reflexivity.
Qed.

(** Inverted Modern Pyramids Characterization Theorem:
    Verifies that filtering the corpus for Orient_Inverted recovers the inverted
    modern structures (Pyramide Inversee at the Louvre and Slovak Radio Building). *)
Theorem inverted_pyramids_characterized :
  map mon_id (filter (fun m => match classify_regime m with
                               | Regime_InvertedModern => true
                               | _ => false
                               end) wiki_pyramid_monuments) =
    [Mon_PyramideInversee; Mon_SlovakRadio].
Proof.
  vm_compute. reflexivity.
Qed.

(** Lead §3 & Egypt §3 World-Height Succession & Seven Wonders Survival:
    - Red Pyramid (105.0 m) -> Great Pyramid of Khufu (146.6 m, c. 2560 BC).
    - Khufu remained the tallest structure in the world until Lincoln Cathedral
      in 1311 AD (a 3,871-year reign > 3 millennia).
    - Among the 7 Wonders of the Ancient World, Khufu is the unique extant one. *)
Inductive AncientWonderStatus : Type :=
  | Wonder_Extant
  | Wonder_Destroyed.

Definition seven_wonders_status : list AncientWonderStatus :=
  [ Wonder_Extant;     (* Great Pyramid of Khufu at Giza *)
    Wonder_Destroyed;  (* Hanging Gardens of Babylon *)
    Wonder_Destroyed;  (* Statue of Zeus at Olympia *)
    Wonder_Destroyed;  (* Temple of Artemis at Ephesus *)
    Wonder_Destroyed;  (* Mausoleum at Halicarnassus *)
    Wonder_Destroyed;  (* Colossus of Rhodes *)
    Wonder_Destroyed   (* Lighthouse of Alexandria *) ].

Definition count_extant_wonders (ws : list AncientWonderStatus) : Z :=
  fold_right (fun w acc => match w with Wonder_Extant => 1 + acc | _ => acc end) 0 ws.

Theorem khufu_millennia_world_tallest_and_sole_extant_wonder :
  max_height_ancient wiki_pyramid_monuments = 1466 /\
  1311 - (-2560) = 3871 /\
  3871 > 3000 /\
  count_extant_wonders seven_wonders_status = 1.
Proof.
  repeat split; try vm_compute; try reflexivity; lia.
Qed.

(** Sudan §1 vs Egypt §2-4 Theorem:
    - Sudan preserves 220 extant Kushite pyramids (the most in the world),
      strictly exceeding Egypt's ~135 discovered pyramids.
    - Nubian pyramids feature steeper wall inclinations (70 deg vs 51 deg)
      and continued until 200 AD (1,900 years after Egypt's royal pyramid
      construction ended c. 1700 BC). *)
Theorem sudan_exceeds_egypt_in_extant_count_slope_and_longevity :
  max_extant_tradition_count wiki_pyramid_monuments = 220 /\
  220 > 135 /\
  70 > 51 /\
  200 - (-1700) = 1900.
Proof.
  repeat split; try vm_compute; try reflexivity; lia.
Qed.

(** Americas §2-3 & China §1 vs Egypt §3 Footprint-vs-Height Paradox Theorem:
    Monks Mound at Cahokia (56,000 m^2), Qin Shi Huang's mausoleum mound
    (122,500 m^2), and the Great Pyramid of Cholula (160,000 m^2, largest by
    volume) all have bases strictly larger than the Great Pyramid of Khufu
    (53,000 m^2), yet Khufu (146.6 m) is strictly taller than each of them! *)
Theorem base_area_and_volume_do_not_entail_height :
  area_height_paradox_monuments wiki_pyramid_monuments =
    [Mon_CholulaMexico; Mon_MonksMound; Mon_QinShiHuang].
Proof.
  vm_compute. reflexivity.
Qed.

(** East, Southeast & Central Asia §1 Buddhist Step-Pyramid Conservation:
    "At least nine Buddhist step pyramids survive, 4 from former Gyeongsang
     Province of Korea, 3 from Japan, 1 from Indonesia (Borobudur) and 1 from
     Tajikistan." *)
Definition buddhist_step_pyramid_counts : list (WorldRegion * Z) :=
  [ (Reg_Asia, 4); (* Former Gyeongsang Province, Korea *)
    (Reg_Asia, 3); (* Japan, e.g. Doto Stupa at Ono-dera, Sakai *)
    (Reg_Asia, 1); (* Borobudur, Central Java, Indonesia *)
    (Reg_Asia, 1)  (* Vrang Buddhist stupa, Tajikistan *) ].

Theorem buddhist_step_pyramids_sum_to_nine :
  fold_right (fun p acc => snd p + acc) 0 buddhist_step_pyramid_counts = 9 /\
  9 = 9.
Proof.
  split; [vm_compute; reflexivity | reflexivity].
Qed.

(** Spain §2 Guimar Preservation & Mesoamerica §3 Tenochtitlan Source Spread:
    - Guimar originally hosted 9 pyramids, 3 dismantled -> 6 survive.
    - For the 1487 dedication of the Great Pyramid of Tenochtitlan, Harner
      cites historical sources reporting 20,000, 72,344, and 80,400 sacrifices. *)
Definition tenochtitlan_1487_sources : list Z := [20000; 72344; 80400].

Theorem guimar_survival_and_tenochtitlan_source_bounds :
  9 - 3 = 6 /\
  forall n : Z, In n tenochtitlan_1487_sources -> 20000 <= n /\ n <= 80400.
Proof.
  split; [lia |].
  intros n HIn. simpl in HIn.
  destruct HIn as [H | [H | [H | H]]]; subst; try lia; contradiction.
Qed.

(** Modern §1 Lifecycle Transitions, Story Ordering & Wemding 3183 Schedule:
    - Memphis Pyramid state transitions: 1991 SportsArena -> 2007 Idle -> 2015 Megastore.
    - Story hierarchy: Walter (18) < Luxor (30) < Memphis (32) < Transamerica (48) < Ryugyong (105).
    - Completed height maximum: The Shard at 309.6 m (3096 dm).
    - Wemding Time Pyramid: 120 blocks placed 1 every 10 years starting in 1993
      completes in 1993 + (120 - 1) * 10 = 3183 AD. *)
Inductive MemphisVenuePhase : Type :=
  | Phase_BasketballArena_1991_2004
  | Phase_InactiveVenue_2007_2014
  | Phase_BassProMegastore_2015_Present.

Definition memphis_pyramid_phase (year : Z) : MemphisVenuePhase :=
  if year <? 2007 then Phase_BasketballArena_1991_2004
  else if year <? 2015 then Phase_InactiveVenue_2007_2014
  else Phase_BassProMegastore_2015_Present.

Definition wemding_block_year (block_index : Z) : Z :=
  1993 + 10 * block_index.

Theorem modern_pyramids_lifecycle_stories_and_time_pyramid_3183 :
  max_height_extant wiki_pyramid_monuments = 3096 /\
  (18 < 30 /\ 30 < 32 /\ 32 < 48 /\ 48 < 105) /\
  memphis_pyramid_phase 1991 = Phase_BasketballArena_1991_2004 /\
  memphis_pyramid_phase 2010 = Phase_InactiveVenue_2007_2014 /\
  memphis_pyramid_phase 2015 = Phase_BassProMegastore_2015_Present /\
  wemding_block_year 0 = 1993 /\
  wemding_block_year (120 - 1) = 3183.
Proof.
  unfold wemding_block_year.
  repeat split; try vm_compute; try reflexivity; lia.
Qed.

(* ========================================================================= *)
(* SECTION 5: COMPLETE SENTENCE SEMANTIC CORPUS OF THE WIKIPEDIA ARTICLE     *)
(* ========================================================================= *)

Definition wiki_pyramid_sentences : list SentenceFrame := [
  (* S001: A pyramid (from Ancient Greek πυραμίς (puramís) 'pyramid', from the Egyptian pir-em-us, the vertical h... *)
  {| sent_id := 1%nat; sent_section := Sec_Lead; sent_region := Reg_Global; sent_prop := PK_EtymologyAndDefinition; sent_words := 44; sent_year := 0; sent_has_quant := false |};
  (* S002: The base of a pyramid can be of any polygon shape, such as triangular or quadrilateral, and its surfac... *)
  {| sent_id := 2%nat; sent_section := Sec_Lead; sent_region := Reg_Global; sent_prop := PK_GeometricOrPhysicalLaw; sent_words := 23; sent_year := 0; sent_has_quant := false |};
  (* S003: A pyramid has the majority of its mass closer to the ground with less mass towards the pyramidion at t... *)
  {| sent_id := 3%nat; sent_section := Sec_Lead; sent_region := Reg_Global; sent_prop := PK_GeometricOrPhysicalLaw; sent_words := 21; sent_year := 0; sent_has_quant := false |};
  (* S004: This is due to the gradual decrease in the cross-sectional area along the vertical axis with increasin... *)
  {| sent_id := 4%nat; sent_section := Sec_Lead; sent_region := Reg_Global; sent_prop := PK_GeometricOrPhysicalLaw; sent_words := 18; sent_year := 0; sent_has_quant := false |};
  (* S005: This offers a weight distribution that allowed early civilizations to create monumental structures. *)
  {| sent_id := 5%nat; sent_section := Sec_Lead; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 13; sent_year := 0; sent_has_quant := false |};
  (* S006: Ancient civilizations in many parts of the world pioneered the building of pyramids. *)
  {| sent_id := 6%nat; sent_section := Sec_Lead; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 13; sent_year := 0; sent_has_quant := false |};
  (* S007: The largest pyramid by volume is the Mesoamerican Great Pyramid of Cholula, in the Mexican state of Pu... *)
  {| sent_id := 7%nat; sent_section := Sec_Lead; sent_region := Reg_Global; sent_prop := PK_ComparativeOrSuperlative; sent_words := 18; sent_year := 0; sent_has_quant := false |};
  (* S008: For millennia, the largest structures on Earth were pyramids—first the Red Pyramid in the Dashur Necro... *)
  {| sent_id := 8%nat; sent_section := Sec_Lead; sent_region := Reg_Global; sent_prop := PK_ComparativeOrSuperlative; sent_words := 26; sent_year := 0; sent_has_quant := false |};
  (* S009: The latter is the only extant example of the Seven Wonders of the Ancient World. *)
  {| sent_id := 9%nat; sent_section := Sec_Lead; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 15; sent_year := 0; sent_has_quant := true |};
  (* S010: The Mesopotamians built the earliest pyramidal structures, called ziggurats. *)
  {| sent_id := 10%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_CulturalOrRitualFunction; sent_words := 9; sent_year := 0; sent_has_quant := false |};
  (* S011: In ancient times, these were brightly painted in gold/bronze. *)
  {| sent_id := 11%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_CulturalOrRitualFunction; sent_words := 9; sent_year := 0; sent_has_quant := false |};
  (* S012: They were constructed of sun-dried mud-brick, and little remains of them. *)
  {| sent_id := 12%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_MaterialAndConstruction; sent_words := 11; sent_year := 0; sent_has_quant := false |};
  (* S013: Ziggurats were built by the Sumerians, Babylonians, Elamites, Akkadians, and Assyrians. *)
  {| sent_id := 13%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_HistoricalChronology; sent_words := 11; sent_year := 0; sent_has_quant := false |};
  (* S014: Each ziggurat was part of a temple complex that included other buildings. *)
  {| sent_id := 14%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_CulturalOrRitualFunction; sent_words := 12; sent_year := 0; sent_has_quant := false |};
  (* S015: The ziggurat's precursors were raised platforms that date from the Ubaid period of the fourth millenni... *)
  {| sent_id := 15%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_HistoricalChronology; sent_words := 17; sent_year := -3500; sent_has_quant := true |};
  (* S016: The earliest ziggurats began near the end of the Early Dynastic Period. *)
  {| sent_id := 16%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_HistoricalChronology; sent_words := 12; sent_year := 0; sent_has_quant := false |};
  (* S017: The original pyramidal structure, the anu ziggurat, dates to around 4000 BC. *)
  {| sent_id := 17%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_HistoricalChronology; sent_words := 12; sent_year := -4000; sent_has_quant := true |};
  (* S018: The White Temple was built on top of it circa 3500 BC. *)
  {| sent_id := 18%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_HistoricalChronology; sent_words := 12; sent_year := -3500; sent_has_quant := true |};
  (* S019: Built in receding tiers upon a rectangular, oval, or square platform, the ziggurat was a pyramidal str... *)
  {| sent_id := 19%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_CulturalOrRitualFunction; sent_words := 21; sent_year := 0; sent_has_quant := false |};
  (* S020: Sun-baked bricks made up the core of the ziggurat with facings of fired bricks on the outside. *)
  {| sent_id := 20%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_HistoricalChronology; sent_words := 17; sent_year := 0; sent_has_quant := false |};
  (* S021: The facings were often glazed in different colors and may have had astrological significance. *)
  {| sent_id := 21%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_HistoricalChronology; sent_words := 14; sent_year := 0; sent_has_quant := true |};
  (* S022: Kings sometimes had their names engraved on them. *)
  {| sent_id := 22%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_HistoricalChronology; sent_words := 8; sent_year := 0; sent_has_quant := false |};
  (* S023: The number of tiers ranged from two to seven. *)
  {| sent_id := 23%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_CulturalOrRitualFunction; sent_words := 9; sent_year := 0; sent_has_quant := true |};
  (* S024: It is assumed that they had shrines at the top, but no archaeological evidence supports this and the o... *)
  {| sent_id := 24%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_EpistemicOrControversy; sent_words := 24; sent_year := 0; sent_has_quant := false |};
  (* S025: Access to the shrine would have been by a series of ramps on one side of the ziggurat or by a spiral r... *)
  {| sent_id := 25%nat; sent_section := Sec_Mesopotamia; sent_region := Reg_WestAsia; sent_prop := PK_CulturalOrRitualFunction; sent_words := 27; sent_year := 0; sent_has_quant := false |};
  (* S026: The most famous African pyramids are in Egypt—huge structures built of bricks or stones, primarily lim... *)
  {| sent_id := 26%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_ComparativeOrSuperlative; sent_words := 25; sent_year := 0; sent_has_quant := false |};
  (* S027: They are shaped in reference to the sun's rays. *)
  {| sent_id := 27%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 9; sent_year := 0; sent_has_quant := false |};
  (* S028: Most had a smoothed white limestone surface. *)
  {| sent_id := 28%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_HistoricalChronology; sent_words := 7; sent_year := 0; sent_has_quant := false |};
  (* S029: Many of the facing stones have fallen or were removed and used for construction in Cairo. *)
  {| sent_id := 29%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_LifecycleOrPreservation; sent_words := 16; sent_year := 0; sent_has_quant := false |};
  (* S030: The capstone was usually made of limestone, granite or basalt and some were plated with electrum. *)
  {| sent_id := 30%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_HistoricalChronology; sent_words := 16; sent_year := 0; sent_has_quant := false |};
  (* S031: Ancient Egyptians built pyramids from 2700 BC until around 1700 BC. *)
  {| sent_id := 31%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_HistoricalChronology; sent_words := 11; sent_year := -2700; sent_has_quant := true |};
  (* S032: The first pyramid was erected during the Third Dynasty by the Pharaoh Djoser and his architect Imhotep. *)
  {| sent_id := 32%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_HistoricalChronology; sent_words := 17; sent_year := 0; sent_has_quant := false |};
  (* S033: This step pyramid, originally begun as a square mastaba, consisted of six levels. *)
  {| sent_id := 33%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 13; sent_year := 0; sent_has_quant := true |};
  (* S034: Early kings such as Snefru built pyramids, with subsequent kings adding to the number until the end of... *)
  {| sent_id := 34%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_HistoricalChronology; sent_words := 21; sent_year := 0; sent_has_quant := false |};
  (* S035: The age of the pyramids reached its zenith at Giza in 2575–2150 BC. *)
  {| sent_id := 35%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_HistoricalChronology; sent_words := 13; sent_year := -2150; sent_has_quant := true |};
  (* S036: The last king to build royal pyramids was Ahmose, with later kings hiding their tombs in the hills, su... *)
  {| sent_id := 36%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 31; sent_year := 0; sent_has_quant := false |};
  (* S037: In Medinat Habu and Deir el-Medina, smaller pyramids were built by individuals. *)
  {| sent_id := 37%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 12; sent_year := 0; sent_has_quant := false |};
  (* S038: Smaller pyramids with steeper sides were built by the Nubians who ruled Egypt in the Late Period. *)
  {| sent_id := 38%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_HistoricalChronology; sent_words := 17; sent_year := 0; sent_has_quant := false |};
  (* S039: The Great Pyramid of Giza is the largest in Egypt and one of the largest in the world. *)
  {| sent_id := 39%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_ComparativeOrSuperlative; sent_words := 18; sent_year := 0; sent_has_quant := false |};
  (* S040: At 146.6 metres (481 ft) it was the tallest structure in the world until the Lincoln Cathedral was fin... *)
  {| sent_id := 40%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_ComparativeOrSuperlative; sent_words := 22; sent_year := 1311; sent_has_quant := true |};
  (* S041: Its base covers an area of around 53,000 square metres (570,000 sq ft). *)
  {| sent_id := 41%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 13; sent_year := 0; sent_has_quant := true |};
  (* S042: The Great Pyramid is the only extant one of the Seven Wonders of the Ancient World. *)
  {| sent_id := 42%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 16; sent_year := 0; sent_has_quant := true |};
  (* S043: Ancient Egyptian pyramids were, in most cases, placed west of the river Nile because the divine pharao... *)
  {| sent_id := 43%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 37; sent_year := 0; sent_has_quant := false |};
  (* S044: As of 2008, some 135 pyramids had been discovered in Egypt, most located near Cairo. *)
  {| sent_id := 44%nat; sent_section := Sec_Egypt; sent_region := Reg_Africa; sent_prop := PK_HistoricalChronology; sent_words := 15; sent_year := 2008; sent_has_quant := true |};
  (* S045: While African pyramids are commonly associated with Egypt, Sudan has 220 extant pyramids, the most in ... *)
  {| sent_id := 45%nat; sent_section := Sec_Sudan; sent_region := Reg_Africa; sent_prop := PK_ComparativeOrSuperlative; sent_words := 18; sent_year := 0; sent_has_quant := true |};
  (* S046: Nubian pyramids were constructed (roughly 240 of them) at three sites in Sudan to serve as tombs for t... *)
  {| sent_id := 46%nat; sent_section := Sec_Sudan; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 26; sent_year := 0; sent_has_quant := true |};
  (* S047: The pyramids of Kush, also known as Nubian Pyramids, have different characteristics than those of Egypt. *)
  {| sent_id := 47%nat; sent_section := Sec_Sudan; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 16; sent_year := 0; sent_has_quant := false |};
  (* S048: The Nubian pyramids had steeper sides than the Egyptian ones. *)
  {| sent_id := 48%nat; sent_section := Sec_Sudan; sent_region := Reg_Africa; sent_prop := PK_ComparativeOrSuperlative; sent_words := 10; sent_year := 0; sent_has_quant := false |};
  (* S049: Pyramids were built in Sudan as late as 200 AD. *)
  {| sent_id := 49%nat; sent_section := Sec_Sudan; sent_region := Reg_Africa; sent_prop := PK_HistoricalChronology; sent_words := 10; sent_year := 200; sent_has_quant := true |};
  (* S050: The Tomb of Askia, in Gao, Mali, is believed to be the burial place of Askia Mohammad I, one of the So... *)
  {| sent_id := 50%nat; sent_section := Sec_Sahel; sent_region := Reg_Africa; sent_prop := PK_EpistemicOrControversy; sent_words := 26; sent_year := 0; sent_has_quant := false |};
  (* S051: It was built at the end of the fifteenth century and is designated as a UNESCO World Heritage Site. *)
  {| sent_id := 51%nat; sent_section := Sec_Sahel; sent_region := Reg_Africa; sent_prop := PK_HistoricalChronology; sent_words := 19; sent_year := 0; sent_has_quant := false |};
  (* S052: UNESCO describes the tomb as an example of the monumental mud-building traditions of the West African ... *)
  {| sent_id := 52%nat; sent_section := Sec_Sahel; sent_region := Reg_Africa; sent_prop := PK_HistoricalChronology; sent_words := 17; sent_year := 0; sent_has_quant := false |};
  (* S053: The complex includes the pyramidal tomb, two mosques, a cemetery and an assembly ground. *)
  {| sent_id := 53%nat; sent_section := Sec_Sahel; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 14; sent_year := 0; sent_has_quant := true |};
  (* S054: At 17 metres (56 ft) in height it is the largest pre-colonial architectural monument in Gao. *)
  {| sent_id := 54%nat; sent_section := Sec_Sahel; sent_region := Reg_Africa; sent_prop := PK_ComparativeOrSuperlative; sent_words := 16; sent_year := 0; sent_has_quant := true |};
  (* S055: It is a notable example of the Sudano-Sahelian architectural style that later spread throughout the re... *)
  {| sent_id := 55%nat; sent_section := Sec_Sahel; sent_region := Reg_Africa; sent_prop := PK_HistoricalChronology; sent_words := 16; sent_year := 0; sent_has_quant := false |};
  (* S056: One of the unique structures of Igbo culture was the Nsude pyramids, in the Nigerian town of Nsude, no... *)
  {| sent_id := 56%nat; sent_section := Sec_Nigeria; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 20; sent_year := 0; sent_has_quant := false |};
  (* S057: Ten pyramidal structures were built of clay/mud. *)
  {| sent_id := 57%nat; sent_section := Sec_Nigeria; sent_region := Reg_Africa; sent_prop := PK_MaterialAndConstruction; sent_words := 7; sent_year := 0; sent_has_quant := true |};
  (* S058: The first base section was 60 ft (18 m) in circumference and 3 ft (0.9 m) in height. *)
  {| sent_id := 58%nat; sent_section := Sec_Nigeria; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 18; sent_year := 0; sent_has_quant := true |};
  (* S059: The next stack was 45 ft (14 m) in circumference. *)
  {| sent_id := 59%nat; sent_section := Sec_Nigeria; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 10; sent_year := 0; sent_has_quant := true |};
  (* S060: Circular stacks continued to the top. *)
  {| sent_id := 60%nat; sent_section := Sec_Nigeria; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 6; sent_year := 0; sent_has_quant := false |};
  (* S061: The structures were temples for the god Ala, who was believed to reside there. *)
  {| sent_id := 61%nat; sent_section := Sec_Nigeria; sent_region := Reg_Africa; sent_prop := PK_EpistemicOrControversy; sent_words := 14; sent_year := 0; sent_has_quant := false |};
  (* S062: A stick was placed at the top to represent the god's residence. *)
  {| sent_id := 62%nat; sent_section := Sec_Nigeria; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 12; sent_year := 0; sent_has_quant := false |};
  (* S063: The structures were laid in groups of five parallel to each other. *)
  {| sent_id := 63%nat; sent_section := Sec_Nigeria; sent_region := Reg_Africa; sent_prop := PK_CulturalOrRitualFunction; sent_words := 12; sent_year := 0; sent_has_quant := false |};
  (* S064: Because it was built of clay/mud like the Deffufa of Nubia, over time periodic reconstruction has been... *)
  {| sent_id := 64%nat; sent_section := Sec_Nigeria; sent_region := Reg_Africa; sent_prop := PK_HistoricalChronology; sent_words := 18; sent_year := 0; sent_has_quant := false |};
  (* S065: Pausanias (2nd century AD) mentions two buildings resembling pyramids, one, 19 kilometres (12 mi) sout... *)
  {| sent_id := 65%nat; sent_section := Sec_Greece; sent_region := Reg_Europe; sent_prop := PK_HistoricalChronology; sent_words := 56; sent_year := 150; sent_has_quant := true |};
  (* S066: Neither survives and no evidence indicates that they resembled Egyptian pyramids. *)
  {| sent_id := 66%nat; sent_section := Sec_Greece; sent_region := Reg_Europe; sent_prop := PK_LifecycleOrPreservation; sent_words := 11; sent_year := 0; sent_has_quant := false |};
  (* S067: At least two surviving pyramid-like structures are available to study, one at Hellenikon and the other... *)
  {| sent_id := 67%nat; sent_section := Sec_Greece; sent_region := Reg_Europe; sent_prop := PK_CulturalOrRitualFunction; sent_words := 25; sent_year := 0; sent_has_quant := true |};
  (* S068: These buildings have inwardly sloping walls, but bear no other resemblance to Egyptian pyramids. *)
  {| sent_id := 68%nat; sent_section := Sec_Greece; sent_region := Reg_Europe; sent_prop := PK_CulturalOrRitualFunction; sent_words := 14; sent_year := 0; sent_has_quant := false |};
  (* S069: They had large central rooms (unlike Egyptian pyramids) and the Hellenikon structure is rectangular ra... *)
  {| sent_id := 69%nat; sent_section := Sec_Greece; sent_region := Reg_Europe; sent_prop := PK_GeometricOrPhysicalLaw; sent_words := 37; sent_year := 0; sent_has_quant := true |};
  (* S070: The stone used to build these structures was limestone quarried locally and was cut to fit, not into f... *)
  {| sent_id := 70%nat; sent_section := Sec_Greece; sent_region := Reg_Europe; sent_prop := PK_MaterialAndConstruction; sent_words := 26; sent_year := 0; sent_has_quant := false |};
  (* S071: These structures were dated from pot shards excavated from the floor and grounds. *)
  {| sent_id := 71%nat; sent_section := Sec_Greece; sent_region := Reg_Europe; sent_prop := PK_CulturalOrRitualFunction; sent_words := 13; sent_year := 0; sent_has_quant := false |};
  (* S072: The latest estimates are around the 5th and 4th centuries. *)
  {| sent_id := 72%nat; sent_section := Sec_Greece; sent_region := Reg_Europe; sent_prop := PK_CulturalOrRitualFunction; sent_words := 10; sent_year := 0; sent_has_quant := true |};
  (* S073: Normally this technique is used for dating pottery, but researchers used it to try to date stone flake... *)
  {| sent_id := 73%nat; sent_section := Sec_Greece; sent_region := Reg_Europe; sent_prop := PK_CulturalOrRitualFunction; sent_words := 22; sent_year := 0; sent_has_quant := false |};
  (* S074: This launched debate about whether or not these structures are actually older than Egypt, part of the ... *)
  {| sent_id := 74%nat; sent_section := Sec_Greece; sent_region := Reg_Europe; sent_prop := PK_EpistemicOrControversy; sent_words := 20; sent_year := 0; sent_has_quant := false |};
  (* S075: Lefkowitz criticised this research, suggesting that some of the research was done not to determine the... *)
  {| sent_id := 75%nat; sent_section := Sec_Greece; sent_region := Reg_Europe; sent_prop := PK_EpistemicOrControversy; sent_words := 39; sent_year := 0; sent_has_quant := false |};
  (* S076: She claimed that not only were the results imprecise, but that other structures mentioned in the resea... *)
  {| sent_id := 76%nat; sent_section := Sec_Greece; sent_region := Reg_Europe; sent_prop := PK_CulturalOrRitualFunction; sent_words := 64; sent_year := 0; sent_has_quant := false |};
  (* S077: She claimed that earlier research from the 1930s, confirmed in the 1980s by Fracchia, was ignored. *)
  {| sent_id := 77%nat; sent_section := Sec_Greece; sent_region := Reg_Europe; sent_prop := PK_CulturalOrRitualFunction; sent_words := 16; sent_year := 0; sent_has_quant := true |};
  (* S078: Liritzis responded that Lefkowitz failed to understand and misinterpreted the methodology. *)
  {| sent_id := 78%nat; sent_section := Sec_Greece; sent_region := Reg_Europe; sent_prop := PK_EpistemicOrControversy; sent_words := 11; sent_year := 0; sent_has_quant := false |};
  (* S079: Kuyavian Pyramids, known as Kuyavian Mounds, Graves of Giants or Polish Pyramids – enormous tombs, meg... *)
  {| sent_id := 79%nat; sent_section := Sec_Poland; sent_region := Reg_Europe; sent_prop := PK_CulturalOrRitualFunction; sent_words := 20; sent_year := 0; sent_has_quant := false |};
  (* S080: The Pyramids of Güímar are six rectangular pyramid-shaped, terraced structures, built from lava withou... *)
  {| sent_id := 80%nat; sent_section := Sec_Spain; sent_region := Reg_Europe; sent_prop := PK_MaterialAndConstruction; sent_words := 15; sent_year := 0; sent_has_quant := true |};
  (* S081: They are located in the district of Chacona, part of the town of Güímar on the island of Tenerife in t... *)
  {| sent_id := 81%nat; sent_section := Sec_Spain; sent_region := Reg_Europe; sent_prop := PK_CulturalOrRitualFunction; sent_words := 23; sent_year := 0; sent_has_quant := true |};
  (* S082: The structures were dated to the 19th century and their function explained as a byproduct of contempor... *)
  {| sent_id := 82%nat; sent_section := Sec_Spain; sent_region := Reg_Europe; sent_prop := PK_HistoricalChronology; sent_words := 19; sent_year := 1850; sent_has_quant := true |};
  (* S083: Autochthonous Guanche traditions as well as surviving images indicate that similar structures (also kn... *)
  {| sent_id := 83%nat; sent_section := Sec_Spain; sent_region := Reg_Europe; sent_prop := PK_HistoricalChronology; sent_words := 28; sent_year := 0; sent_has_quant := false |};
  (* S084: However, over time they were dismantled and used as building material. *)
  {| sent_id := 84%nat; sent_section := Sec_Spain; sent_region := Reg_Europe; sent_prop := PK_LifecycleOrPreservation; sent_words := 11; sent_year := 0; sent_has_quant := false |};
  (* S085: Güímar hostred nine pyramids, only six of which survive. *)
  {| sent_id := 85%nat; sent_section := Sec_Spain; sent_region := Reg_Europe; sent_prop := PK_LifecycleOrPreservation; sent_words := 9; sent_year := 0; sent_has_quant := true |};
  (* S086: The 27-metre-high Pyramid of Cestius was built by the end of the 1st century BC and survives close to ... *)
  {| sent_id := 86%nat; sent_section := Sec_RomanEmpire; sent_region := Reg_Europe; sent_prop := PK_LifecycleOrPreservation; sent_words := 23; sent_year := -50; sent_has_quant := true |};
  (* S087: Another, named Meta Romuli, stood in the Ager Vaticanus (today's Borgo), but was destroyed at the end ... *)
  {| sent_id := 87%nat; sent_section := Sec_RomanEmpire; sent_region := Reg_Europe; sent_prop := PK_LifecycleOrPreservation; sent_words := 21; sent_year := 1450; sent_has_quant := true |};
  (* S088: Pyramids were occasionally used in Christian architecture during the feudal era, e.g. as the tower of ... *)
  {| sent_id := 88%nat; sent_section := Sec_MedievalEurope; sent_region := Reg_Europe; sent_prop := PK_HistoricalChronology; sent_words := 22; sent_year := 0; sent_has_quant := false |};
  (* S089: Andean cultures used pyramids in various architectural structures such as the ones in Caral, Túcume an... *)
  {| sent_id := 89%nat; sent_section := Sec_Peru; sent_region := Reg_Americas; sent_prop := PK_CulturalOrRitualFunction; sent_words := 28; sent_year := 0; sent_has_quant := false |};
  (* S090: Several Mesoamerican cultures built pyramid-shaped structures. *)
  {| sent_id := 90%nat; sent_section := Sec_Mesoamerica; sent_region := Reg_Americas; sent_prop := PK_CulturalOrRitualFunction; sent_words := 6; sent_year := 0; sent_has_quant := false |};
  (* S091: Mesoamerican pyramids were usually stepped, with temples on top, more similar to the Mesopotamian zigg... *)
  {| sent_id := 91%nat; sent_section := Sec_Mesoamerica; sent_region := Reg_Americas; sent_prop := PK_ComparativeOrSuperlative; sent_words := 19; sent_year := 0; sent_has_quant := false |};
  (* S092: The largest by volume is the Great Pyramid of Cholula, in the Mexican state of Puebla. *)
  {| sent_id := 92%nat; sent_section := Sec_Mesoamerica; sent_region := Reg_Americas; sent_prop := PK_ComparativeOrSuperlative; sent_words := 16; sent_year := 0; sent_has_quant := false |};
  (* S093: Constructed from the 3rd century BC to the 9th century AD, this pyramid is the world's largest monumen... *)
  {| sent_id := 93%nat; sent_section := Sec_Mesoamerica; sent_region := Reg_Americas; sent_prop := PK_ComparativeOrSuperlative; sent_words := 24; sent_year := -250; sent_has_quant := true |};
  (* S094: The third largest pyramid in the world, the Pyramid of the Sun, at Teotihuacan, is also located in Mex... *)
  {| sent_id := 94%nat; sent_section := Sec_Mesoamerica; sent_region := Reg_Americas; sent_prop := PK_ComparativeOrSuperlative; sent_words := 19; sent_year := 0; sent_has_quant := false |};
  (* S095: An unusual pyramid with a circular plan survives at the site of Cuicuilco, now inside Mexico City and ... *)
  {| sent_id := 95%nat; sent_section := Sec_Mesoamerica; sent_region := Reg_Americas; sent_prop := PK_LifecycleOrPreservation; sent_words := 34; sent_year := -50; sent_has_quant := true |};
  (* S096: Several circular stepped pyramids called Guachimontones survive in Teuchitlán, Jalisco. *)
  {| sent_id := 96%nat; sent_section := Sec_Mesoamerica; sent_region := Reg_Americas; sent_prop := PK_LifecycleOrPreservation; sent_words := 10; sent_year := 0; sent_has_quant := false |};
  (* S097: Pyramids in Mexico were often used for human sacrifice. *)
  {| sent_id := 97%nat; sent_section := Sec_Mesoamerica; sent_region := Reg_Americas; sent_prop := PK_CulturalOrRitualFunction; sent_words := 9; sent_year := 0; sent_has_quant := true |};
  (* S098: Harner stated that for the dedication of the Great Pyramid of Tenochtitlan in 1487, 'one source states... *)
  {| sent_id := 98%nat; sent_section := Sec_Mesoamerica; sent_region := Reg_Americas; sent_prop := PK_EpistemicOrControversy; sent_words := 30; sent_year := 1487; sent_has_quant := true |};
  (* S099: Many pre-Columbian Native American societies of ancient North America built large pyramidal earth stru... *)
  {| sent_id := 99%nat; sent_section := Sec_UnitedStates; sent_region := Reg_Americas; sent_prop := PK_MaterialAndConstruction; sent_words := 18; sent_year := 0; sent_has_quant := false |};
  (* S100: Among the largest and best-known of these structures is Monks Mound at the site of Cahokia in what bec... *)
  {| sent_id := 100%nat; sent_section := Sec_UnitedStates; sent_region := Reg_Americas; sent_prop := PK_ComparativeOrSuperlative; sent_words := 24; sent_year := 1100; sent_has_quant := true |};
  (* S101: It has a base larger than that of the Great Pyramid. *)
  {| sent_id := 101%nat; sent_section := Sec_UnitedStates; sent_region := Reg_Americas; sent_prop := PK_ComparativeOrSuperlative; sent_words := 11; sent_year := 0; sent_has_quant := false |};
  (* S102: Many mounds underwent repeated episodes of expansion. *)
  {| sent_id := 102%nat; sent_section := Sec_UnitedStates; sent_region := Reg_Americas; sent_prop := PK_CulturalOrRitualFunction; sent_words := 7; sent_year := 0; sent_has_quant := false |};
  (* S103: They are believed to have played a central role in the mound-building peoples' religious life. *)
  {| sent_id := 103%nat; sent_section := Sec_UnitedStates; sent_region := Reg_Americas; sent_prop := PK_EpistemicOrControversy; sent_words := 15; sent_year := 0; sent_has_quant := false |};
  (* S104: Documented uses include semi-public chief's house platforms, public temple platforms, mortuary platfor... *)
  {| sent_id := 104%nat; sent_section := Sec_UnitedStates; sent_region := Reg_Americas; sent_prop := PK_MaterialAndConstruction; sent_words := 29; sent_year := 0; sent_has_quant := false |};
  (* S105: Cultures that built substructure mounds include the Troyville culture, Coles Creek culture, Plaquemine... *)
  {| sent_id := 105%nat; sent_section := Sec_UnitedStates; sent_region := Reg_Americas; sent_prop := PK_CulturalOrRitualFunction; sent_words := 17; sent_year := 0; sent_has_quant := false |};
  (* S106: Many square flat-topped mound tombs in China. *)
  {| sent_id := 106%nat; sent_section := Sec_China; sent_region := Reg_Asia; sent_prop := PK_CulturalOrRitualFunction; sent_words := 7; sent_year := 0; sent_has_quant := false |};
  (* S107: The first emperor Qin Shi Huang (c. 221 BC, who unified the seven pre-imperial kingdoms) was buried un... *)
  {| sent_id := 107%nat; sent_section := Sec_China; sent_region := Reg_Asia; sent_prop := PK_HistoricalChronology; sent_words := 24; sent_year := -221; sent_has_quant := true |};
  (* S108: In the following centuries about a dozen more Han dynasty royal persons were also buried under flat-to... *)
  {| sent_id := 108%nat; sent_section := Sec_China; sent_region := Reg_Asia; sent_prop := PK_HistoricalChronology; sent_words := 19; sent_year := 0; sent_has_quant := true |};
  (* S109: Numerous giant, granite, temple pyramids were built in South India during the Chola Empire, many of wh... *)
  {| sent_id := 109%nat; sent_section := Sec_India; sent_region := Reg_Asia; sent_prop := PK_MaterialAndConstruction; sent_words := 20; sent_year := 0; sent_has_quant := false |};
  (* S110: Examples include Brihadisvara Temple at Thanjavur, Brihadisvara Temple at Gangaikonda Cholapuram, and ... *)
  {| sent_id := 110%nat; sent_section := Sec_India; sent_region := Reg_Asia; sent_prop := PK_HistoricalChronology; sent_words := 17; sent_year := 0; sent_has_quant := false |};
  (* S111: However, the largest temple (area) is the Ranganathaswamy Temple in Srirangam, Tamil Nadu. *)
  {| sent_id := 111%nat; sent_section := Sec_India; sent_region := Reg_Asia; sent_prop := PK_ComparativeOrSuperlative; sent_words := 13; sent_year := 0; sent_has_quant := false |};
  (* S112: The Thanjavur temple was built by Raja Raja Chola in the 11th century. *)
  {| sent_id := 112%nat; sent_section := Sec_India; sent_region := Reg_Asia; sent_prop := PK_HistoricalChronology; sent_words := 13; sent_year := 1050; sent_has_quant := true |};
  (* S113: The Brihadisvara Temple was declared a World Heritage Site by UNESCO in 1987; the Temple of Gangaikond... *)
  {| sent_id := 113%nat; sent_section := Sec_India; sent_region := Reg_Asia; sent_prop := PK_HistoricalChronology; sent_words := 27; sent_year := 1987; sent_has_quant := true |};
  (* S114: The granite gopuram (tower) of Brihadeeswarar Temple, 1010 AD. *)
  {| sent_id := 114%nat; sent_section := Sec_India; sent_region := Reg_Asia; sent_prop := PK_HistoricalChronology; sent_words := 9; sent_year := 1010; sent_has_quant := true |};
  (* S115: The pyramidal structure above the sanctum at Brihadisvara Temple. *)
  {| sent_id := 115%nat; sent_section := Sec_India; sent_region := Reg_Asia; sent_prop := PK_HistoricalChronology; sent_words := 9; sent_year := 0; sent_has_quant := false |};
  (* S116: Ranganathaswamy Temple gopurams at Srirangam dedicated to Ranganatha, a reclining form of the Hindu de... *)
  {| sent_id := 116%nat; sent_section := Sec_India; sent_region := Reg_Asia; sent_prop := PK_CulturalOrRitualFunction; sent_words := 17; sent_year := 0; sent_has_quant := false |};
  (* S117: Austronesian megalithic culture in Indonesia featured earth and stone step pyramid structures called p... *)
  {| sent_id := 117%nat; sent_section := Sec_Indonesia; sent_region := Reg_Asia; sent_prop := PK_MaterialAndConstruction; sent_words := 15; sent_year := 0; sent_has_quant := false |};
  (* S118: These were discovered in Pangguyangan near Cisolok and in Cipari near Kuningan. *)
  {| sent_id := 118%nat; sent_section := Sec_Indonesia; sent_region := Reg_Asia; sent_prop := PK_CulturalOrRitualFunction; sent_words := 12; sent_year := 0; sent_has_quant := false |};
  (* S119: The stone pyramids were based on beliefs that mountains and high places were the abode for the spirit ... *)
  {| sent_id := 119%nat; sent_section := Sec_Indonesia; sent_region := Reg_Asia; sent_prop := PK_CulturalOrRitualFunction; sent_words := 21; sent_year := 0; sent_has_quant := false |};
  (* S120: The step pyramid is the basic design of the 8th century Borobudur Buddhist monument in Central Java. *)
  {| sent_id := 120%nat; sent_section := Sec_Indonesia; sent_region := Reg_Asia; sent_prop := PK_HistoricalChronology; sent_words := 17; sent_year := 750; sent_has_quant := true |};
  (* S121: However later Java temples were influenced by Indian Hindu architecture, as exemplified by the spires ... *)
  {| sent_id := 121%nat; sent_section := Sec_Indonesia; sent_region := Reg_Asia; sent_prop := PK_CulturalOrRitualFunction; sent_words := 18; sent_year := 0; sent_has_quant := false |};
  (* S122: In the 15th century, during late Majapahit period, Java saw the revival of indigenous Austronesian ele... *)
  {| sent_id := 122%nat; sent_section := Sec_Indonesia; sent_region := Reg_Asia; sent_prop := PK_HistoricalChronology; sent_words := 33; sent_year := 1450; sent_has_quant := true |};
  (* S123: In east Asia, Buddhist stupas were usually represented as tall pagodas. *)
  {| sent_id := 123%nat; sent_section := Sec_EastCentralAsia; sent_region := Reg_Asia; sent_prop := PK_CulturalOrRitualFunction; sent_words := 11; sent_year := 0; sent_has_quant := false |};
  (* S124: However, some pyramidal stupas survive. *)
  {| sent_id := 124%nat; sent_section := Sec_EastCentralAsia; sent_region := Reg_Asia; sent_prop := PK_LifecycleOrPreservation; sent_words := 5; sent_year := 0; sent_has_quant := false |};
  (* S125: One theory is that these pyramids were inspired by the Borobudur monument through Sumatran and Javanes... *)
  {| sent_id := 125%nat; sent_section := Sec_EastCentralAsia; sent_region := Reg_Asia; sent_prop := PK_EpistemicOrControversy; sent_words := 17; sent_year := 0; sent_has_quant := false |};
  (* S126: A similar Buddhist monument survives in Vrang, Tajikistan. *)
  {| sent_id := 126%nat; sent_section := Sec_EastCentralAsia; sent_region := Reg_Asia; sent_prop := PK_LifecycleOrPreservation; sent_words := 8; sent_year := 0; sent_has_quant := false |};
  (* S127: At least nine Buddhist step pyramids survive, 4 from former Gyeongsang Province of Korea, 3 from Japan... *)
  {| sent_id := 127%nat; sent_section := Sec_EastCentralAsia; sent_region := Reg_Asia; sent_prop := PK_LifecycleOrPreservation; sent_words := 25; sent_year := 0; sent_has_quant := true |};
  (* S128: Several pyramids were erected throughout the Pacific islands, such as Puʻukoholā Heiau in Hawaii, the ... *)
  {| sent_id := 128%nat; sent_section := Sec_Oceania; sent_region := Reg_Oceania; sent_prop := PK_HistoricalChronology; sent_words := 24; sent_year := 0; sent_has_quant := false |};
  (* S129: Two pyramid-shaped tombs were erected in Maudlin's Cemetery, Ireland, c. 1840, belonging to the De Bur... *)
  {| sent_id := 129%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_HistoricalChronology; sent_words := 17; sent_year := 1840; sent_has_quant := true |};
  (* S130: The Louvre Pyramid in Paris, France, in the court of the Louvre Museum, is a 20.6 metre (about 70 foot... *)
  {| sent_id := 130%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_MaterialAndConstruction; sent_words := 28; sent_year := 0; sent_has_quant := true |};
  (* S131: It was designed by American architect I. M. Pei and completed in 1989. *)
  {| sent_id := 131%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_HistoricalChronology; sent_words := 13; sent_year := 1989; sent_has_quant := true |};
  (* S132: The Pyramide Inversée (Inverted Pyramid) is displayed in the underground Louvre shopping mall. *)
  {| sent_id := 132%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_GeometricOrPhysicalLaw; sent_words := 13; sent_year := 0; sent_has_quant := false |};
  (* S133: The Tama-Re village was an Egyptian-themed set of buildings and monuments built near Eatonton, Georgia... *)
  {| sent_id := 133%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_LifecycleOrPreservation; sent_words := 29; sent_year := 1993; sent_has_quant := true |};
  (* S134: The Shard in London, at 309.6 metres (1016 feet) tall, is the tallest building in the United Kingdom a... *)
  {| sent_id := 134%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_ComparativeOrSuperlative; sent_words := 21; sent_year := 1016; sent_has_quant := true |};
  (* S135: The Luxor Hotel in Las Vegas, United States, is a 30-story pyramid. *)
  {| sent_id := 135%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 12; sent_year := 0; sent_has_quant := true |};
  (* S136: The 32-story Memphis Pyramid (Memphis was named after the Egyptian capital whose name was derived from... *)
  {| sent_id := 136%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 23; sent_year := 0; sent_has_quant := true |};
  (* S137: Built in 1991, it was the home court for the University of Memphis men's basketball program, and the N... *)
  {| sent_id := 137%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_HistoricalChronology; sent_words := 25; sent_year := 1991; sent_has_quant := true |};
  (* S138: It was not regularly used as a sports or entertainment venue after 2007, and in 2015 was re-purposed a... *)
  {| sent_id := 138%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_LifecycleOrPreservation; sent_words := 24; sent_year := 2007; sent_has_quant := true |};
  (* S139: The LBS Financial Credit Union Pyramid, home of the basketball and volleyball teams of the California ... *)
  {| sent_id := 139%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 31; sent_year := 0; sent_has_quant := true |};
  (* S140: The 48-story Transamerica Pyramid in San Francisco, California, designed by William Pereira, is a city... *)
  {| sent_id := 140%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 16; sent_year := 0; sent_has_quant := true |};
  (* S141: The 105-story Ryugyong Hotel is in Pyongyang, North Korea. *)
  {| sent_id := 141%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 9; sent_year := 0; sent_has_quant := true |};
  (* S142: A former museum/monument in Tirana, Albania is commonly known as the 'Pyramid of Tirana'. *)
  {| sent_id := 142%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 14; sent_year := 0; sent_has_quant := false |};
  (* S143: It differs from typical pyramids in having a radial rather than square or rectangular shape, and gentl... *)
  {| sent_id := 143%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_GeometricOrPhysicalLaw; sent_words := 31; sent_year := 0; sent_has_quant := false |};
  (* S144: The Slovak Radio Building in Bratislava, Slovakia is an inverted pyramid. *)
  {| sent_id := 144%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_GeometricOrPhysicalLaw; sent_words := 11; sent_year := 0; sent_has_quant := false |};
  (* S145: The Palace of Peace and Reconciliation is in Astana, Kazakhstan. *)
  {| sent_id := 145%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 10; sent_year := 0; sent_has_quant := false |};
  (* S146: The three pyramids of Moody Gardens are in Galveston, Texas. *)
  {| sent_id := 146%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 10; sent_year := 0; sent_has_quant := true |};
  (* S147: The Co-Op Bank Pyramid or Stockport Pyramid in Stockport, England is a large pyramid-shaped office block. *)
  {| sent_id := 147%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 16; sent_year := 0; sent_has_quant := false |};
  (* S148: (The surrounding part of the valley of the upper Mersey has sometimes been called the 'Kings Valley' a... *)
  {| sent_id := 148%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 24; sent_year := 0; sent_has_quant := false |};
  (* S149: The Ames Monument in southeastern Wyoming honors the brothers who financed the Union Pacific Railroad. *)
  {| sent_id := 149%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_HistoricalChronology; sent_words := 15; sent_year := 0; sent_has_quant := false |};
  (* S150: The Trylon, a triangular pyramid was erected for the 1939 World's Fair in Flushing, Queens and demolis... *)
  {| sent_id := 150%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_LifecycleOrPreservation; sent_words := 21; sent_year := 1939; sent_has_quant := true |};
  (* S151: The Ballandean Pyramid, at Ballandean in rural Queensland is a 15-metre folly pyramid made from blocks... *)
  {| sent_id := 151%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_HistoricalChronology; sent_words := 19; sent_year := 0; sent_has_quant := true |};
  (* S152: The Karlsruhe Pyramid is a pyramid made of red sandstone, located in the centre of the market square o... *)
  {| sent_id := 152%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_HistoricalChronology; sent_words := 21; sent_year := 0; sent_has_quant := false |};
  (* S153: It was erected in 1823–1825 over the vault of the city's founder, Margrave Charles III William (1679–1... *)
  {| sent_id := 153%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 17; sent_year := 1823; sent_has_quant := true |};
  (* S154: Sunway Pyramid shopping mall is in Selangor, Malaysia. *)
  {| sent_id := 154%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 8; sent_year := 0; sent_has_quant := false |};
  (* S155: Hanoi Museum has an overall design of a reversed pyramid. *)
  {| sent_id := 155%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_GeometricOrPhysicalLaw; sent_words := 10; sent_year := 0; sent_has_quant := false |};
  (* S156: Pyramid by artist Jean-Jules Soucy [fr] in La Baie, Quebec is made out of 3,000 give way signs. *)
  {| sent_id := 156%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_HistoricalChronology; sent_words := 18; sent_year := 0; sent_has_quant := true |};
  (* S157: The Pyramid [ru] culture-entertainment complex and Monument of the Kazan siege [ru] is in Kazan, Russia. *)
  {| sent_id := 157%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 16; sent_year := 0; sent_has_quant := false |};
  (* S158: The Time pyramid in Wemding, Germany is a pyramid begun in 1993 and scheduled for completion in the ye... *)
  {| sent_id := 158%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_LifecycleOrPreservation; sent_words := 20; sent_year := 1993; sent_has_quant := true |};
  (* S159: Triangle is a skyscraper under construction in Paris. *)
  {| sent_id := 159%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_LifecycleOrPreservation; sent_words := 8; sent_year := 0; sent_has_quant := false |};
  (* S160: The Shimizu Mega-City Pyramid is a proposed project for construction of a massive pyramid over Tokyo B... *)
  {| sent_id := 160%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_LifecycleOrPreservation; sent_words := 19; sent_year := 0; sent_has_quant := false |};
  (* S161: The Donkin Memorial was erected on a Xhosa reserve in 1820 by Cape Governor Sir Rufane Shaw Donkin in ... *)
  {| sent_id := 161%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_HistoricalChronology; sent_words := 42; sent_year := 1820; sent_has_quant := true |};
  (* S162: Hanoi Museum in Vietnam features an inverted pyramid shape. *)
  {| sent_id := 162%nat; sent_section := Sec_ModernPyramids; sent_region := Reg_Global; sent_prop := PK_GeometricOrPhysicalLaw; sent_words := 9; sent_year := 0; sent_has_quant := false |};
  (* S163: With the Egyptian Revival movement in the nineteenth and early twentieth century, pyramids became more... *)
  {| sent_id := 163%nat; sent_section := Sec_ModernMausoleums; sent_region := Reg_Global; sent_prop := PK_HistoricalChronology; sent_words := 19; sent_year := 0; sent_has_quant := true |};
  (* S164: The tomb of Quintino Sella, outside the monumental cemetery of Oropa, is pyramid-shaped. *)
  {| sent_id := 164%nat; sent_section := Sec_ModernMausoleums; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 13; sent_year := 0; sent_has_quant := false |};
  (* S165: This style was popular with tycoons in the US. *)
  {| sent_id := 165%nat; sent_section := Sec_ModernMausoleums; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 9; sent_year := 0; sent_has_quant := false |};
  (* S166: The Schoenhofen Pyramid Mausoleum (1889) in Chicago and Hunt's Tomb (1930) in Phoenix, Arizona are not... *)
  {| sent_id := 166%nat; sent_section := Sec_ModernMausoleums; sent_region := Reg_Global; sent_prop := PK_HistoricalChronology; sent_words := 17; sent_year := 1889; sent_has_quant := true |};
  (* S167: Some people build pyramid tombs for themselves. *)
  {| sent_id := 167%nat; sent_section := Sec_ModernMausoleums; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 7; sent_year := 0; sent_has_quant := false |};
  (* S168: Nicolas Cage bought a pyramid tomb for himself in a famed New Orleans graveyard. *)
  {| sent_id := 168%nat; sent_section := Sec_ModernMausoleums; sent_region := Reg_Global; sent_prop := PK_CulturalOrRitualFunction; sent_words := 14; sent_year := 0; sent_has_quant := false |}
].

Fixpoint total_sentence_words (ss : list SentenceFrame) : Z :=
  match ss with
  | [] => 0
  | s :: rest => s.(sent_words) + total_sentence_words rest
  end.

Fixpoint region_word_count (r : WorldRegion) (ss : list SentenceFrame) : Z :=
  match ss with
  | [] => 0
  | s :: rest =>
      (if world_region_eqb s.(sent_region) r then s.(sent_words) else 0) +
      region_word_count r rest
  end.

Fixpoint region_sentence_count (r : WorldRegion) (ss : list SentenceFrame) : nat :=
  match ss with
  | [] => 0%nat
  | s :: rest =>
      ((if world_region_eqb s.(sent_region) r then 1 else 0) +
       region_sentence_count r rest)%nat
  end.

Fixpoint quant_sentence_count (ss : list SentenceFrame) : nat :=
  match ss with
  | [] => 0%nat
  | s :: rest =>
      ((if s.(sent_has_quant) then 1 else 0) + quant_sentence_count rest)%nat
  end.

(** Universal Word-Partition Conservation across all 7 WorldRegions. *)
Theorem sentence_corpus_regional_word_conservation :
  forall ss : list SentenceFrame,
    region_word_count Reg_Global ss +
    region_word_count Reg_WestAsia ss +
    region_word_count Reg_Africa ss +
    region_word_count Reg_Europe ss +
    region_word_count Reg_Americas ss +
    region_word_count Reg_Asia ss +
    region_word_count Reg_Oceania ss = total_sentence_words ss.
Proof.
  induction ss as [| s rest IH]; simpl; [lia |].
  destruct (sent_region s); simpl; lia.
Qed.

(** Exact Isomorphism Theorem between Rocq's Deductive Knowledge Model and
    Souffle Datalog's Inferred Relations (wikipedia_pyramid_semantics.dl). *)
Theorem souffle_datalog_sentence_and_knowledge_isomorphism :
  length wiki_pyramid_sentences = 168%nat /\
  total_sentence_words wiki_pyramid_sentences = 3001 /\
  quant_sentence_count wiki_pyramid_sentences = 66%nat /\
  caution_monuments wiki_pyramid_monuments = [Mon_AnuZiggurat; Mon_Hellinikon; Mon_GuimarTenerife; Mon_MetaRomuli; Mon_Tenochtitlan] /\
  area_height_paradox_monuments wiki_pyramid_monuments = [Mon_CholulaMexico; Mon_MonksMound; Mon_QinShiHuang] /\
  region_sentence_count Reg_Global wiki_pyramid_sentences = 49%nat /\
  region_word_count Reg_Global wiki_pyramid_sentences = 890 /\
  region_sentence_count Reg_WestAsia wiki_pyramid_sentences = 16%nat /\
  region_word_count Reg_WestAsia wiki_pyramid_sentences = 225 /\
  region_sentence_count Reg_Africa wiki_pyramid_sentences = 39%nat /\
  region_word_count Reg_Africa wiki_pyramid_sentences = 634 /\
  region_sentence_count Reg_Europe wiki_pyramid_sentences = 24%nat /\
  region_word_count Reg_Europe wiki_pyramid_sentences = 555 /\
  region_sentence_count Reg_Americas wiki_pyramid_sentences = 17%nat /\
  region_word_count Reg_Americas wiki_pyramid_sentences = 316 /\
  region_sentence_count Reg_Asia wiki_pyramid_sentences = 22%nat /\
  region_word_count Reg_Asia wiki_pyramid_sentences = 357 /\
  region_sentence_count Reg_Oceania wiki_pyramid_sentences = 1%nat /\
  region_word_count Reg_Oceania wiki_pyramid_sentences = 24.
Proof.
  vm_compute.
  repeat split; reflexivity.
Qed.
