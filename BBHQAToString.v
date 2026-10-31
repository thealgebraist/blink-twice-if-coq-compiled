(******************************************************************************)
(*                                                                            *)
(*                 BBH COMPOSITIONAL SURFACE REALIZER (to_string)             *)
(*                                                                            *)
(*  THE ONLY MODULE IN THE BBH QA FORMALIZATION THAT IMPORTS String.          *)
(*  Renders pure QuestionADT, AnswerADT, and SuiteScorecard values to         *)
(*  human-readable text strictly by composing atomic constructor token maps   *)
(*  and recursive structural combinators — zero hardcoded benchmark sentences.*)
(*                                                                            *)
(******************************************************************************)

From Stdlib Require Import ZArith.
From Stdlib Require Import List.
From Stdlib Require Import String.
From Stdlib Require Import Ascii.
Require Import BBHQADomainAndSolvers.
Require Import BBHQABenchmarkSuite.
Import ListNotations.
Open Scope string_scope.
Open Scope Z_scope.

(* ========================================================================= *)
(* 1. ATOMIC PRIMITIVE & INTEGER FORMATTERS                                  *)
(* ========================================================================= *)

Definition digit_to_string (d : Z) : string :=
  if d =? 0 then "0" else if d =? 1 then "1" else if d =? 2 then "2"
  else if d =? 3 then "3" else if d =? 4 then "4" else if d =? 5 then "5"
  else if d =? 6 then "6" else if d =? 7 then "7" else if d =? 8 then "8"
  else "9".

Fixpoint pos_digits_to_string (fuel : nat) (n : Z) : string :=
  match fuel with
  | O => ""
  | S rest =>
      if n <? 10 then digit_to_string n
      else pos_digits_to_string rest (n / 10) ++ digit_to_string (n mod 10)
  end.

Definition z_to_string (n : Z) : string :=
  if n =? 0 then "0"
  else if n <? 0 then "-" ++ pos_digits_to_string 24 (- n)
  else pos_digits_to_string 24 n.

Definition bool_to_string (b : bool) : string :=
  if b then "True" else "False".

Definition yesno_to_string (b : bool) : string :=
  if b then "Yes" else "No".

Fixpoint string_list_to_string (sep : string) (xs : list string) : string :=
  match xs with
  | [] => ""
  | [x] => x
  | x :: rest => x ++ sep ++ string_list_to_string sep rest
  end.

Definition option3_to_string (o : Option3) : string :=
  match o with Opt3_A => "(A)" | Opt3_B => "(B)" | Opt3_C => "(C)" end.

Definition option4_to_string (o : Option4) : string :=
  match o with Opt4_A => "(A)" | Opt4_B => "(B)" | Opt4_C => "(C)" | Opt4_D => "(D)" end.

(* ========================================================================= *)
(* 2. ATOMIC DOMAIN LEXICON TOKENIZERS                                       *)
(* ========================================================================= *)

Definition rel_dir_to_string (d : RelMoveDir) : string :=
  match d with
  | Move_Forward => "forward" | Move_Backward => "backward"
  | Move_Left => "left"       | Move_Right => "right"
  end.

Definition nav_instr_to_string (ins : NavInstruction) : string :=
  match ins with
  | Nav_AlwaysFaceForward => "face_forward"
  | Nav_TurnLeft          => "turn_left"
  | Nav_TurnRight         => "turn_right"
  | Nav_TurnAround        => "turn_around"
  | Nav_Step d n          => "step(" ++ rel_dir_to_string d ++ "," ++ z_to_string n ++ ")"
  end.

Definition speaker_to_string (s : SpeakerADT) : string :=
  match s with
  | Sp_Alejandro => "Alejandro"
  | Sp_Alexis => "Alexis"
  | Sp_Amberly => "Amberly"
  | Sp_Andree => "Andree"
  | Sp_Antwan => "Antwan"
  | Sp_Audrie => "Audrie"
  | Sp_Bernita => "Bernita"
  | Sp_Christie => "Christie"
  | Sp_Conception => "Conception"
  | Sp_Crista => "Crista"
  | Sp_Dallas => "Dallas"
  | Sp_Delbert => "Delbert"
  | Sp_Delfina => "Delfina"
  | Sp_Elanor => "Elanor"
  | Sp_Fidel => "Fidel"
  | Sp_Fletcher => "Fletcher"
  | Sp_Gwenn => "Gwenn"
  | Sp_Helene => "Helene"
  | Sp_Inga => "Inga"
  | Sp_Jamey => "Jamey"
  | Sp_Jaymie => "Jaymie"
  | Sp_Jerry => "Jerry"
  | Sp_Jim => "Jim"
  | Sp_Ka => "Ka"
  | Sp_Kandi => "Kandi"
  | Sp_Kristian => "Kristian"
  | Sp_Leda => "Leda"
  | Sp_Lorine => "Lorine"
  | Sp_Maybelle => "Maybelle"
  | Sp_Michael => "Michael"
  | Sp_Michaela => "Michaela"
  | Sp_Millicent => "Millicent"
  | Sp_Millie => "Millie"
  | Sp_Osvaldo => "Osvaldo"
  | Sp_Phoebe => "Phoebe"
  | Sp_Rashida => "Rashida"
  | Sp_Raymond => "Raymond"
  | Sp_Ryan => "Ryan"
  | Sp_Sal => "Sal"
  | Sp_Shalonda => "Shalonda"
  | Sp_Shaunda => "Shaunda"
  | Sp_Shenna => "Shenna"
  | Sp_Sherrie => "Sherrie"
  | Sp_Sima => "Sima"
  | Sp_Tamika => "Tamika"
  | Sp_Teressa => "Teressa"
  | Sp_Vernell => "Vernell"
  | Sp_Vina => "Vina"
  | Sp_Willian => "Willian"
  | Sp_Yoland => "Yoland"
  end.

Definition polarity_to_string (p : TruthPolarity) : string :=
  match p with Pol_Truth => "truth" | Pol_Lies => "lies" end.

Definition testimony_to_string (c : TestimonyClause) : string :=
  match c with
  | TC_Fact s p     => speaker_to_string s ++ ":" ++ polarity_to_string p
  | TC_Says a b p   => speaker_to_string a ++ "->" ++ speaker_to_string b ++ ":" ++ polarity_to_string p
  end.

Definition swap_agent_to_string (a : SwapAgent) : string :=
  match a with Ag_Alice => "Alice" | Ag_Bob => "Bob" | Ag_Claire => "Claire" end.

Definition held_object_to_string (h : HeldObjectADT) : string :=
  match h with
  | HO_Benchwarmer => "benchwarmer"
  | HO_BlackBall => "black ball"
  | HO_BlueBall => "blue ball"
  | HO_BluePresent => "blue present"
  | HO_BrownBall => "brown ball"
  | HO_BrownPresent => "brown present"
  | HO_Catch22 => "catch 2 2"
  | HO_CenterMidfielder => "center midfielder"
  | HO_Cheerleader => "cheerleader"
  | HO_FellowshipOfTheRing => "fellowship of the ring"
  | HO_Frankenstein => "frankenstein"
  | HO_Fullback => "fullback"
  | HO_Goalkeeper => "goalkeeper"
  | HO_GreatGatsby => "great gatsby"
  | HO_GreenBall => "green ball"
  | HO_GreenPresent => "green present"
  | HO_Helga => "helga"
  | HO_HoundOfTheBaskervilles => "hound of the baskervilles"
  | HO_Izzi => "izzi"
  | HO_Jamie => "jamie"
  | HO_Karl => "karl"
  | HO_LeftMidfielder => "left midfielder"
  | HO_LeftWinger => "left winger"
  | HO_Lola => "lola"
  | HO_Lolita => "lolita"
  | HO_Melissa => "melissa"
  | HO_MobyDick => "moby dick"
  | HO_Odyssey => "odyssey"
  | HO_Ophelia => "ophelia"
  | HO_OrangeBall => "orange ball"
  | HO_Patrick => "patrick"
  | HO_Pearl => "pearl"
  | HO_PinkBall => "pink ball"
  | HO_PurpleBall => "purple ball"
  | HO_PurplePresent => "purple present"
  | HO_RedBall => "red ball"
  | HO_RedPresent => "red present"
  | HO_RightMidfielder => "right midfielder"
  | HO_RightWinger => "right winger"
  | HO_Rodrigo => "rodrigo"
  | HO_Sam => "sam"
  | HO_Striker => "striker"
  | HO_Ulysses => "ulysses"
  | HO_WhiteBall => "white ball"
  | HO_WhitePresent => "white present"
  | HO_YellowBall => "yellow ball"
  | HO_YellowPresent => "yellow present"
  end.

Definition swap_to_string (sw : TranspositionSwap) : string :=
  swap_agent_to_string sw.(swap_lhs) ++ "<->" ++ swap_agent_to_string sw.(swap_rhs).

Definition ranked_object_to_string (r : RankedObjectADT) : string :=
  match r with
  | RO_Ada => "ada"
  | RO_Amy => "amy"
  | RO_Ana => "ana"
  | RO_Apples => "apples"
  | RO_BlackBook => "black book"
  | RO_BlueBook => "blue book"
  | RO_BlueJay => "blue jay"
  | RO_BrownBook => "brown book"
  | RO_Bus => "bus"
  | RO_Cantaloupes => "cantaloupes"
  | RO_Cardinal => "cardinal"
  | RO_Convertible => "convertible"
  | RO_Crow => "crow"
  | RO_Dan => "dan"
  | RO_Eli => "eli"
  | RO_Eve => "eve"
  | RO_Falcon => "falcon"
  | RO_GrayBook => "gray book"
  | RO_GreenBook => "green book"
  | RO_Hatchback => "hatchback"
  | RO_Hawk => "hawk"
  | RO_Hummingbird => "hummingbird"
  | RO_Joe => "joe"
  | RO_Kiwis => "kiwis"
  | RO_Limousine => "limousine"
  | RO_Loquats => "loquats"
  | RO_Mangoes => "mangoes"
  | RO_Mel => "mel"
  | RO_Minivan => "minivan"
  | RO_Motorcyle => "motorcyle"
  | RO_Mya => "mya"
  | RO_OrangeBook => "orange book"
  | RO_Oranges => "oranges"
  | RO_Owl => "owl"
  | RO_Peaches => "peaches"
  | RO_Pears => "pears"
  | RO_Plums => "plums"
  | RO_PurpleBook => "purple book"
  | RO_Quail => "quail"
  | RO_Raven => "raven"
  | RO_RedBook => "red book"
  | RO_Rob => "rob"
  | RO_Robin => "robin"
  | RO_Sedan => "sedan"
  | RO_StationWagon => "station wagon"
  | RO_Tractor => "tractor"
  | RO_Truck => "truck"
  | RO_Watermelons => "watermelons"
  | RO_WhiteBook => "white book"
  | RO_YellowBook => "yellow book"
  end.

Definition rank_slot_to_string (s : RankSlot) : string :=
  match s with Slot_First => "first" | Slot_Middle => "second" | Slot_Last => "last" end.

Definition order_constraint_to_string (c : OrderConstraint) : string :=
  match c with
  | OC_Before a b  => ranked_object_to_string a ++ " < " ++ ranked_object_to_string b
  | OC_After a b   => ranked_object_to_string a ++ " > " ++ ranked_object_to_string b
  | OC_PinSlot a s => ranked_object_to_string a ++ " @ " ++ rank_slot_to_string s
  end.

Definition taxon_to_string (t : OntologyTaxon) : string :=
  match t with
  | Tax_MusicalInstrument => "musical_instruments"
  | Tax_Fruit             => "fruits"
  | Tax_Vegetable         => "vegetables"
  | Tax_Animal            => "animals"
  | Tax_ArtifactOther     => "artifacts"
  end.

Definition entity_noun_to_string (n : EntityNounADT) : string :=
  match n with
  | EN_Accordion => "accordion"
  | EN_Apple => "apple"
  | EN_Banana => "banana"
  | EN_Bear => "bear"
  | EN_Bed => "bed"
  | EN_Blackberry => "blackberry"
  | EN_Cabbage => "cabbage"
  | EN_Car => "car"
  | EN_Carrot => "carrot"
  | EN_Cat => "cat"
  | EN_Cauliflower => "cauliflower"
  | EN_Chair => "chair"
  | EN_Chicken => "chicken"
  | EN_Clarinet => "clarinet"
  | EN_Couch => "couch"
  | EN_Cow => "cow"
  | EN_Dog => "dog"
  | EN_Donkey => "donkey"
  | EN_Drum => "drum"
  | EN_Duck => "duck"
  | EN_Fish => "fish"
  | EN_Flute => "flute"
  | EN_Fridge => "fridge"
  | EN_Frog => "frog"
  | EN_Garlic => "garlic"
  | EN_Goat => "goat"
  | EN_Grape => "grape"
  | EN_HeadOfBroccoli => "head of broccoli"
  | EN_Lamp => "lamp"
  | EN_LettuceHead => "lettuce head"
  | EN_Microwave => "microwave"
  | EN_Mouse => "mouse"
  | EN_Nectarine => "nectarine"
  | EN_Onion => "onion"
  | EN_Orange => "orange"
  | EN_Oven => "oven"
  | EN_Peach => "peach"
  | EN_Piano => "piano"
  | EN_Pig => "pig"
  | EN_Plum => "plum"
  | EN_Potato => "potato"
  | EN_Rabbit => "rabbit"
  | EN_Raspberry => "raspberry"
  | EN_Snail => "snail"
  | EN_Snake => "snake"
  | EN_StalkOfCelery => "stalk of celery"
  | EN_Stove => "stove"
  | EN_Strawberry => "strawberry"
  | EN_Table => "table"
  | EN_Toaster => "toaster"
  | EN_Trombone => "trombone"
  | EN_Trumpet => "trumpet"
  | EN_Violin => "violin"
  | EN_Yam => "yam"
  end.

Fixpoint bool_expr_to_string (e : BoolExprADT) : string :=
  match e with
  | BE_Const b   => bool_to_string b
  | BE_Not e1    => "not(" ++ bool_expr_to_string e1 ++ ")"
  | BE_And e1 e2 => "(" ++ bool_expr_to_string e1 ++ " and " ++ bool_expr_to_string e2 ++ ")"
  | BE_Or  e1 e2 => "(" ++ bool_expr_to_string e1 ++ " or " ++ bool_expr_to_string e2 ++ ")"
  end.

Fixpoint arith_expr_to_string (e : ArithExprADT) : string :=
  match e with
  | AE_Lit n     => z_to_string n
  | AE_Neg e1    => "-(" ++ arith_expr_to_string e1 ++ ")"
  | AE_Add e1 e2 => "(" ++ arith_expr_to_string e1 ++ " + " ++ arith_expr_to_string e2 ++ ")"
  | AE_Sub e1 e2 => "(" ++ arith_expr_to_string e1 ++ " - " ++ arith_expr_to_string e2 ++ ")"
  | AE_Mul e1 e2 => "(" ++ arith_expr_to_string e1 ++ " * " ++ arith_expr_to_string e2 ++ ")"
  end.

Definition person_to_string (p : PersonADT) : string :=
  match p with
  | Per_Andrew => "Andrew"
  | Per_Anthony => "Anthony"
  | Per_Ashley => "Ashley"
  | Per_Betty => "Betty"
  | Per_David => "David"
  | Per_Elizabeth => "Elizabeth"
  | Per_Emily => "Emily"
  | Per_Hannah => "Hannah"
  | Per_James => "James"
  | Per_Jason => "Jason"
  | Per_Jennifer => "Jennifer"
  | Per_Jessica => "Jessica"
  | Per_John => "John"
  | Per_Kimberly => "Kimberly"
  | Per_Leslie => "Leslie"
  | Per_Linda => "Linda"
  | Per_Lisa => "Lisa"
  | Per_Mark => "Mark"
  | Per_Mary => "Mary"
  | Per_Michael => "Michael"
  | Per_Nancy => "Nancy"
  | Per_Richard => "Richard"
  | Per_Samantha => "Samantha"
  | Per_Sarah => "Sarah"
  | Per_Sean => "Sean"
  | Per_Steven => "Steven"
  | Per_Susan => "Susan"
  | Per_Thomas => "Thomas"
  | Per_Tiffany => "Tiffany"
  | Per_William => "William"
  end.

Definition venue_to_string (v : VenueADT) : string :=
  match v with
  | Ven_AmusementPark => "amusement park"
  | Ven_ArtShow => "art show"
  | Ven_ArtStudio => "art studio"
  | Ven_Bakery => "bakery"
  | Ven_BasketballCourt => "basketball court"
  | Ven_Beach => "beach"
  | Ven_Bookstore => "bookstore"
  | Ven_ClothingStore => "clothing store"
  | Ven_CoffeeShop => "coffee shop"
  | Ven_ConstructionSite => "construction site"
  | Ven_DanceStudio => "dance studio"
  | Ven_FootballField => "football field"
  | Ven_GasStation => "gas station"
  | Ven_Library => "library"
  | Ven_Market => "market"
  | Ven_Movies => "movies"
  | Ven_Museum => "museum"
  | Ven_OrchestraHall => "orchestra hall"
  | Ven_Park => "park"
  | Ven_PhysicsClassroom => "physics classroom"
  | Ven_Restaurant => "restaurant"
  | Ven_SoccerField => "soccer field"
  | Ven_SwimmingPool => "swimming pool"
  end.

Definition activity_to_string (a : ObservedActivity) : string :=
  match a with
  | Act_AttendingClassAtSchool => "attending class at school"
  | Act_BuyingBikeAtBikeShop => "buying bike at bike shop"
  | Act_BuyingClothesAtMall => "buying clothes at mall"
  | Act_BuyingCookiesAtBakery => "buying cookies at bakery"
  | Act_BuyingLunchAtDeli => "buying lunch at deli"
  | Act_BuyingPhoneAtElectronicsStore => "buying phone at electronics store"
  | Act_DrivingToWaterPark => "driving to water park"
  | Act_FixingComputerAtElectronicStore => "fixing computer at electronic store"
  | Act_GettingCoffeeAtCafe => "getting coffee at cafe"
  | Act_PlayingTennisAtTennisCourt => "playing tennis at tennis court"
  | Act_ReadingAtLibrary => "reading at library"
  | Act_SittingOnRooftop => "sitting on rooftop"
  | Act_StretchingAtYogaStudio => "stretching at yoga studio"
  | Act_TakingPhotosNearEiffelTower => "taking photos near eiffel tower"
  | Act_TakingPhotosNearLeaningTowerOfPisa => "taking photos near leaning tower of pisa"
  | Act_WaitingAtAirport => "waiting at airport"
  | Act_WaitingAtTrainStation => "waiting at train station"
  | Act_WalkingInGarden => "walking in garden"
  | Act_WalkingTowardsStatueOfLiberty => "walking towards statue of liberty"
  | Act_WatchingMovieAtTheater => "watching movie at theater"
  | Act_WorkingAtOffice => "working at office"
  | Act_WorkingOutAtGym => "working out at gym"
  end.

Definition interval_to_string (w : TimeInterval) : string :=
  "[" ++ z_to_string w.(ti_start) ++ ":00-" ++ z_to_string w.(ti_end) ++ ":00]".

Definition schedule_constraint_to_string (c : ScheduleConstraint) : string :=
  match c with
  | SC_WokeUpAt h       => "wake@" ++ z_to_string h
  | SC_ClosedBefore h   => "closed_before@" ++ z_to_string h
  | SC_ClosedAfter h    => "closed_after@" ++ z_to_string h
  | SC_Observed w a s e => person_to_string w ++ ":" ++ activity_to_string a ++ "@" ++
                           z_to_string s ++ "-" ++ z_to_string e
  end.

(* ========================================================================= *)
(* 3. COMPOSITIONAL QUESTION, ANSWER & SCORECARD PRETTY-PRINTERS             *)
(* ========================================================================= *)

Definition domain_id_to_string (d : TaskDomainId) : string :=
  match d with
  | Dom_Navigate         => "navigate"
  | Dom_WebOfLies        => "web_of_lies"
  | Dom_SwapTracking     => "tracking_shuffled_objects_three_objects"
  | Dom_LogicalDeduction => "logical_deduction_three_objects"
  | Dom_ObjectCounting   => "object_counting"
  | Dom_BooleanExpr      => "boolean_expressions"
  | Dom_MultistepArith   => "multistep_arithmetic_two"
  | Dom_TemporalSeq      => "temporal_sequences"
  end.

Definition solver_mode_to_string (m : SolverMode) : string :=
  match m with
  | Mode_Operational => "operational"
  | Mode_Algebraic   => "algebraic"
  end.

Definition question_to_string (q : QuestionADT) : string :=
  match q with
  | Q_Navigate prog =>
      "Q_Navigate[" ++ string_list_to_string "; " (map nav_instr_to_string prog) ++ "]"
  | Q_WebOfLies kb target =>
      "Q_WebOfLies[" ++ string_list_to_string "; " (map testimony_to_string kb) ++
      " ? " ++ speaker_to_string target ++ "]"
  | Q_SwapTracking _ init swaps queried _ =>
      "Q_SwapTracking[Alice=" ++ held_object_to_string init.(hold_alice) ++
      ", Bob=" ++ held_object_to_string init.(hold_bob) ++
      ", Claire=" ++ held_object_to_string init.(hold_claire) ++
      "; swaps=" ++ string_list_to_string ", " (map swap_to_string swaps) ++
      " ? " ++ swap_agent_to_string queried ++ "]"
  | Q_LogicalDeduction _ _ premises _ =>
      "Q_LogicalDeduction[" ++ string_list_to_string "; " (map order_constraint_to_string premises) ++ "]"
  | Q_ObjectCounting inv tgt =>
      let t_str := match tgt with
                   | CQT_AllObjects => "all_objects"
                   | CQT_Taxon t    => taxon_to_string t
                   end in
      "Q_ObjectCounting[" ++
      string_list_to_string ", " (map (fun e => z_to_string e.(inv_qty) ++ " " ++ entity_noun_to_string e.(inv_noun)) inv) ++
      " ? " ++ t_str ++ "]"
  | Q_BooleanExpr f =>
      "Q_BooleanExpr[" ++ bool_expr_to_string f ++ "]"
  | Q_MultistepArith e =>
      "Q_MultistepArith[" ++ arith_expr_to_string e ++ "]"
  | Q_TemporalSeq ag ven facts _ =>
      "Q_TemporalSeq[" ++ person_to_string ag ++ " -> " ++ venue_to_string ven ++
      " | " ++ string_list_to_string "; " (map schedule_constraint_to_string facts) ++ "]"
  end.

Definition answer_to_string (a : AnswerADT) : string :=
  match a with
  | Ans_YesNo b         => yesno_to_string b
  | Ans_Truth b         => bool_to_string b
  | Ans_Count n         => z_to_string n
  | Ans_IntVal n        => z_to_string n
  | Ans_HeldChoice c it => option3_to_string c ++ " " ++ held_object_to_string it
  | Ans_OrderChoice c   => option3_to_string c
  | Ans_TimeChoice c w  => option4_to_string c ++ " " ++ interval_to_string w
  | Ans_Undetermined    => "undetermined"
  end.

Definition benchmark_item_to_string (it : QABenchmarkItem) : string :=
  "#" ++ z_to_string (Z.of_nat it.(qbi_id)) ++ " [" ++
  domain_id_to_string it.(qbi_domain) ++ "] " ++
  question_to_string it.(qbi_question) ++ " => " ++
  answer_to_string it.(qbi_gold).

Definition scorecard_to_string (sc : SuiteScorecard) : string :=
  z_to_string sc.(sc_passed) ++ "/" ++ z_to_string sc.(sc_total) ++
  " (failed=" ++ z_to_string sc.(sc_failed) ++ ")".

Theorem answer_to_string_mode_invariant :
  forall (m1 m2 : SolverMode) (q : QuestionADT),
    answer_to_string (compute_answer m1 q) = answer_to_string (compute_answer m2 q).
Proof.
  intros m1 m2 q.
  destruct m1, m2; try reflexivity.
  - rewrite universal_multi_paradigm_qa_equivalence. reflexivity.
  - rewrite <- universal_multi_paradigm_qa_equivalence. reflexivity.
Qed.

Theorem formatted_bbh_2000_scorecard_verified :
  scorecard_to_string (evaluate_qa_suite Mode_Operational bbh_all_2000_suite) =
  scorecard_to_string {| sc_total := 2000; sc_passed := 2000; sc_failed := 0 |}
  /\ scorecard_to_string (evaluate_qa_suite Mode_Algebraic bbh_all_2000_suite) =
  scorecard_to_string {| sc_total := 2000; sc_passed := 2000; sc_failed := 0 |}.
Proof.
  destruct bbh_all_2000_dual_engine_100_percent_verified as [Hop Halg].
  rewrite Hop, Halg. split; reflexivity.
Qed.
