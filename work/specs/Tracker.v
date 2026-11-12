(** Immutable work-time tracker, authored in the checked CJR generic layer.
    All explicit system interactions belong to adapters. Lists use immutable
    value nodes and tail closures, avoiding a sentinel object or mutable heap. *)
From Coq Require Import String List ZArith.
From cjr Require Import generic_laws.
From cjr.examples Require Import generic_print cj_print.
Import ListNotations.
Local Open Scope string_scope.
Definition list_ty := GTNamed "ShiftList" [].
Definition state_ty := GTNamed "TrackerState" [].
Definition result_ty := GTNamed "TrackerResult" [].
Definition tracker_layouts := [
 GLayout "ShiftList" GStruct [] [("empty",GTBool);("start",GTInt);("finish",GTInt);("rest",GTArrow GTUnit list_ty)];
 GLayout "TrackerState" GStruct [] [("pieces",list_ty);("pending",GTInt)];
 GLayout "TrackerResult" GStruct [] [("code",GTInt);("state",state_ty);("rows",list_ty)];
 GLayout "TrackerSession" GStruct [] [("state",state_ty);("candidate",state_ty);("waiting",GTBool);("code",GTInt)]].

Definition emptyPieces_fn := GFunction "emptyPieces" None [] [] (GTNamed "ShiftList" [])
  (GEConstruct (GTNamed "ShiftList" []) [(GEVal (LitV (LitBool true))); (GEVal (LitV (LitInt (0)))); (GEVal (LitV (LitInt (0)))); (GELam "unused" GTUnit (GTNamed "ShiftList" []) (GECall "emptyPieces" [] []))]).

Definition consPiece_fn := GFunction "consPiece" None [] [("pieceStart",GTInt); ("pieceEnd",GTInt); ("restPieces",GTNamed "ShiftList" [])] (GTNamed "ShiftList" [])
  (GEConstruct (GTNamed "ShiftList" []) [(GEVal (LitV (LitBool false))); (GEVar "pieceStart"); (GEVar "pieceEnd"); (GELam "unused" GTUnit (GTNamed "ShiftList" []) (GEVar "restPieces"))]).

Definition nextMidnight_fn := GFunction "nextMidnight" None [] [("minute",GTInt)] (GTInt)
  (GEBinOp PlusOp (GEBinOp MinusOp (GEVar "minute") (GEBinOp RemOp (GEVar "minute") (GEVal (LitV (LitInt (1440)))))) (GEVal (LitV (LitInt (1440))))).

Definition minMinute_fn := GFunction "minMinute" None [] [("leftMinute",GTInt); ("rightMinute",GTInt)] (GTInt)
  (GEIf (GEBinOp LeOp (GEVar "leftMinute") (GEVar "rightMinute")) (GEVar "leftMinute") (GEVar "rightMinute")).

Definition overlaps_fn := GFunction "overlaps" None [] [("pieces",GTNamed "ShiftList" []); ("startMinute",GTInt); ("endMinute",GTInt)] (GTBool)
  (GEIf (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 0) (GEVal (LitV (LitBool false))) (GEIf (GEBinOp AndOp (GEIf (GEBinOp LeOp (GEVar "endMinute") (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 1)) (GEVal (LitV (LitBool false))) (GEVal (LitV (LitBool true)))) (GEIf (GEBinOp LeOp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 2) (GEVar "startMinute")) (GEVal (LitV (LitBool false))) (GEVal (LitV (LitBool true))))) (GEVal (LitV (LitBool true))) (GECall "overlaps" [] [(GEApp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 3) (GEVal (LitV LitUnit))); (GEVar "startMinute"); (GEVar "endMinute")]))).

Definition endsAfter_fn := GFunction "endsAfter" None [] [("pieces",GTNamed "ShiftList" []); ("startMinute",GTInt)] (GTBool)
  (GEIf (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 0) (GEVal (LitV (LitBool false))) (GEIf (GEIf (GEBinOp LeOp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 2) (GEVar "startMinute")) (GEVal (LitV (LitBool false))) (GEVal (LitV (LitBool true)))) (GEVal (LitV (LitBool true))) (GECall "endsAfter" [] [(GEApp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 3) (GEVal (LitV LitUnit))); (GEVar "startMinute")]))).

Definition splitOnto_fn := GFunction "splitOnto" None [] [("startMinute",GTInt); ("endMinute",GTInt); ("restPieces",GTNamed "ShiftList" [])] (GTNamed "ShiftList" [])
  (GEIf (GEBinOp LeOp (GEVar "endMinute") (GEVar "startMinute")) (GEVar "restPieces") (GELet (Some "boundary") (GECall "minMinute" [] [(GECall "nextMidnight" [] [(GEVar "startMinute")]); (GEVar "endMinute")]) (GECall "consPiece" [] [(GEVar "startMinute"); (GEVar "boundary"); (GECall "splitOnto" [] [(GEVar "boundary"); (GEVar "endMinute"); (GEVar "restPieces")])]))).

Definition insertDaily_fn := GFunction "insertDaily" None [] [("pieces",GTNamed "ShiftList" []); ("startMinute",GTInt); ("endMinute",GTInt)] (GTNamed "ShiftList" [])
  (GEIf (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 0) (GECall "splitOnto" [] [(GEVar "startMinute"); (GEVar "endMinute"); (GEVar "pieces")]) (GEIf (GEBinOp LeOp (GEVar "startMinute") (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 1)) (GECall "splitOnto" [] [(GEVar "startMinute"); (GEVar "endMinute"); (GEVar "pieces")]) (GECall "consPiece" [] [(GEField (GTNamed "ShiftList" []) (GEVar "pieces") 1); (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 2); (GECall "insertDaily" [] [(GEApp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 3) (GEVal (LitV LitUnit))); (GEVar "startMinute"); (GEVar "endMinute")])]))).

Definition selectPieces_fn := GFunction "selectPieces" None [] [("pieces",GTNamed "ShiftList" []); ("lowerMinute",GTInt); ("upperMinute",GTInt); ("intersect",GTBool)] (GTNamed "ShiftList" [])
  (GEIf (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 0) (GEVar "pieces") (GELet (Some "selectedTail") (GECall "selectPieces" [] [(GEApp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 3) (GEVal (LitV LitUnit))); (GEVar "lowerMinute"); (GEVar "upperMinute"); (GEVar "intersect")]) (GEIf (GEIf (GEVar "intersect") (GEBinOp AndOp (GEIf (GEBinOp LeOp (GEVar "upperMinute") (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 1)) (GEVal (LitV (LitBool false))) (GEVal (LitV (LitBool true)))) (GEIf (GEBinOp LeOp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 2) (GEVar "lowerMinute")) (GEVal (LitV (LitBool false))) (GEVal (LitV (LitBool true))))) (GEBinOp AndOp (GEBinOp LeOp (GEVar "lowerMinute") (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 1)) (GEBinOp LeOp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 2) (GEVar "upperMinute")))) (GECall "consPiece" [] [(GEField (GTNamed "ShiftList" []) (GEVar "pieces") 1); (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 2); (GEVar "selectedTail")]) (GEVar "selectedTail")))).

Definition hasStart_fn := GFunction "hasStart" None [] [("pieces",GTNamed "ShiftList" []); ("startMinute",GTInt)] (GTBool)
  (GEIf (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 0) (GEVal (LitV (LitBool false))) (GEIf (GEBinOp EqOp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 1) (GEVar "startMinute")) (GEVal (LitV (LitBool true))) (GECall "hasStart" [] [(GEApp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 3) (GEVal (LitV LitUnit))); (GEVar "startMinute")]))).

Definition removeStart_fn := GFunction "removeStart" None [] [("pieces",GTNamed "ShiftList" []); ("startMinute",GTInt)] (GTNamed "ShiftList" [])
  (GEIf (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 0) (GEVar "pieces") (GEIf (GEBinOp EqOp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 1) (GEVar "startMinute")) (GECall "removeStart" [] [(GEApp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 3) (GEVal (LitV LitUnit))); (GEVar "startMinute")]) (GECall "consPiece" [] [(GEField (GTNamed "ShiftList" []) (GEVar "pieces") 1); (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 2); (GECall "removeStart" [] [(GEApp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 3) (GEVal (LitV LitUnit))); (GEVar "startMinute")])]))).

Definition validPieces_fn := GFunction "validPieces" None [] [("pieces",GTNamed "ShiftList" []); ("previousEnd",GTInt); ("pendingMinute",GTInt)] (GTBool)
  (GEIf (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 0) (GEVal (LitV (LitBool true))) (GEIf (GEBinOp AndOp (GEBinOp AndOp (GEBinOp LeOp (GEVal (LitV (LitInt (0)))) (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 1)) (GEBinOp LeOp (GEVar "previousEnd") (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 1))) (GEBinOp AndOp (GEIf (GEBinOp LeOp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 2) (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 1)) (GEVal (LitV (LitBool false))) (GEVal (LitV (LitBool true)))) (GEBinOp LeOp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 2) (GECall "nextMidnight" [] [(GEField (GTNamed "ShiftList" []) (GEVar "pieces") 1)])))) (GEIf (GEIf (GEBinOp EqOp (GEVar "pendingMinute") (GEVal (LitV (LitInt (-1))))) (GEVal (LitV (LitBool true))) (GEBinOp LeOp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 2) (GEVar "pendingMinute"))) (GECall "validPieces" [] [(GEApp (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 3) (GEVal (LitV LitUnit))); (GEField (GTNamed "ShiftList" []) (GEVar "pieces") 2); (GEVar "pendingMinute")]) (GEVal (LitV (LitBool false)))) (GEVal (LitV (LitBool false))))).

Definition emptyState_fn := GFunction "emptyState" None [] [] (GTNamed "TrackerState" [])
  (GEConstruct (GTNamed "TrackerState" []) [(GECall "emptyPieces" [] []); (GEVal (LitV (LitInt (-1))))]).

Definition validState_fn := GFunction "validState" None [] [("tracker",GTNamed "TrackerState" [])] (GTBool)
  (GEBinOp AndOp (GEBinOp LeOp (GEVal (LitV (LitInt (-1)))) (GEField (GTNamed "TrackerState" []) (GEVar "tracker") 1)) (GECall "validPieces" [] [(GEField (GTNamed "TrackerState" []) (GEVar "tracker") 0); (GEVal (LitV (LitInt (0)))); (GEField (GTNamed "TrackerState" []) (GEVar "tracker") 1)])).

Definition addPair_fn := GFunction "addPair" None [] [("tracker",GTNamed "TrackerState" []); ("startMinute",GTInt); ("endMinute",GTInt)] (GTNamed "TrackerResult" [])
  (GEIf (GEIf (GEBinOp LeOp (GEVal (LitV (LitInt (0)))) (GEVar "startMinute")) (GEVal (LitV (LitBool false))) (GEVal (LitV (LitBool true)))) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (1)))); (GEVar "tracker"); (GECall "emptyPieces" [] [])]) (GEIf (GEBinOp LeOp (GEVar "endMinute") (GEVar "startMinute")) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (2)))); (GEVar "tracker"); (GECall "emptyPieces" [] [])]) (GEIf (GEIf (GEBinOp EqOp (GEField (GTNamed "TrackerState" []) (GEVar "tracker") 1) (GEVal (LitV (LitInt (-1))))) (GEVal (LitV (LitBool false))) (GEIf (GEBinOp LeOp (GEVar "endMinute") (GEField (GTNamed "TrackerState" []) (GEVar "tracker") 1)) (GEVal (LitV (LitBool false))) (GEVal (LitV (LitBool true))))) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (4)))); (GEVar "tracker"); (GECall "emptyPieces" [] [])]) (GEIf (GECall "overlaps" [] [(GEField (GTNamed "TrackerState" []) (GEVar "tracker") 0); (GEVar "startMinute"); (GEVar "endMinute")]) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (3)))); (GEVar "tracker"); (GECall "emptyPieces" [] [])]) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (0)))); (GEConstruct (GTNamed "TrackerState" []) [(GECall "insertDaily" [] [(GEField (GTNamed "TrackerState" []) (GEVar "tracker") 0); (GEVar "startMinute"); (GEVar "endMinute")]); (GEField (GTNamed "TrackerState" []) (GEVar "tracker") 1)]); (GECall "emptyPieces" [] [])]))))).

Definition startShift_fn := GFunction "startShift" None [] [("tracker",GTNamed "TrackerState" []); ("startMinute",GTInt)] (GTNamed "TrackerResult" [])
  (GEIf (GEIf (GEBinOp LeOp (GEVal (LitV (LitInt (0)))) (GEVar "startMinute")) (GEVal (LitV (LitBool false))) (GEVal (LitV (LitBool true)))) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (1)))); (GEVar "tracker"); (GECall "emptyPieces" [] [])]) (GEIf (GEIf (GEBinOp EqOp (GEField (GTNamed "TrackerState" []) (GEVar "tracker") 1) (GEVal (LitV (LitInt (-1))))) (GEVal (LitV (LitBool false))) (GEVal (LitV (LitBool true)))) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (4)))); (GEVar "tracker"); (GECall "emptyPieces" [] [])]) (GEIf (GECall "endsAfter" [] [(GEField (GTNamed "TrackerState" []) (GEVar "tracker") 0); (GEVar "startMinute")]) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (4)))); (GEVar "tracker"); (GECall "emptyPieces" [] [])]) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (0)))); (GEConstruct (GTNamed "TrackerState" []) [(GEField (GTNamed "TrackerState" []) (GEVar "tracker") 0); (GEVar "startMinute")]); (GECall "emptyPieces" [] [])])))).

Definition endShift_fn := GFunction "endShift" None [] [("tracker",GTNamed "TrackerState" []); ("endMinute",GTInt)] (GTNamed "TrackerResult" [])
  (GEIf (GEBinOp EqOp (GEField (GTNamed "TrackerState" []) (GEVar "tracker") 1) (GEVal (LitV (LitInt (-1))))) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (5)))); (GEVar "tracker"); (GECall "emptyPieces" [] [])]) (GELet (Some "completed") (GECall "addPair" [] [(GEConstruct (GTNamed "TrackerState" []) [(GEField (GTNamed "TrackerState" []) (GEVar "tracker") 0); (GEVal (LitV (LitInt (-1))))]); (GEField (GTNamed "TrackerState" []) (GEVar "tracker") 1); (GEVar "endMinute")]) (GEIf (GEBinOp EqOp (GEField (GTNamed "TrackerResult" []) (GEVar "completed") 0) (GEVal (LitV (LitInt (0))))) (GEVar "completed") (GEConstruct (GTNamed "TrackerResult" []) [(GEField (GTNamed "TrackerResult" []) (GEVar "completed") 0); (GEVar "tracker"); (GECall "emptyPieces" [] [])])))).

Definition queryContained_fn := GFunction "queryContained" None [] [("tracker",GTNamed "TrackerState" []); ("lowerMinute",GTInt); ("upperMinute",GTInt)] (GTNamed "TrackerResult" [])
  (GEIf (GEIf (GEBinOp LeOp (GEVal (LitV (LitInt (0)))) (GEVar "lowerMinute")) (GEVal (LitV (LitBool false))) (GEVal (LitV (LitBool true)))) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (1)))); (GEVar "tracker"); (GECall "emptyPieces" [] [])]) (GEIf (GEBinOp LeOp (GEVar "upperMinute") (GEVar "lowerMinute")) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (2)))); (GEVar "tracker"); (GECall "emptyPieces" [] [])]) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (0)))); (GEVar "tracker"); (GECall "selectPieces" [] [(GEField (GTNamed "TrackerState" []) (GEVar "tracker") 0); (GEVar "lowerMinute"); (GEVar "upperMinute"); (GEVal (LitV (LitBool false)))])]))).

Definition queryIntersecting_fn := GFunction "queryIntersecting" None [] [("tracker",GTNamed "TrackerState" []); ("lowerMinute",GTInt); ("upperMinute",GTInt)] (GTNamed "TrackerResult" [])
  (GEIf (GEIf (GEBinOp LeOp (GEVal (LitV (LitInt (0)))) (GEVar "lowerMinute")) (GEVal (LitV (LitBool false))) (GEVal (LitV (LitBool true)))) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (1)))); (GEVar "tracker"); (GECall "emptyPieces" [] [])]) (GEIf (GEBinOp LeOp (GEVar "upperMinute") (GEVar "lowerMinute")) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (2)))); (GEVar "tracker"); (GECall "emptyPieces" [] [])]) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (0)))); (GEVar "tracker"); (GECall "selectPieces" [] [(GEField (GTNamed "TrackerState" []) (GEVar "tracker") 0); (GEVar "lowerMinute"); (GEVar "upperMinute"); (GEVal (LitV (LitBool true)))])]))).

Definition deleteShift_fn := GFunction "deleteShift" None [] [("tracker",GTNamed "TrackerState" []); ("startMinute",GTInt)] (GTNamed "TrackerResult" [])
  (GEIf (GEIf (GEBinOp LeOp (GEVal (LitV (LitInt (0)))) (GEVar "startMinute")) (GEVal (LitV (LitBool false))) (GEVal (LitV (LitBool true)))) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (1)))); (GEVar "tracker"); (GECall "emptyPieces" [] [])]) (GEIf (GECall "hasStart" [] [(GEField (GTNamed "TrackerState" []) (GEVar "tracker") 0); (GEVar "startMinute")]) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (0)))); (GEConstruct (GTNamed "TrackerState" []) [(GECall "removeStart" [] [(GEField (GTNamed "TrackerState" []) (GEVar "tracker") 0); (GEVar "startMinute")]); (GEField (GTNamed "TrackerState" []) (GEVar "tracker") 1)]); (GECall "emptyPieces" [] [])]) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (6)))); (GEVar "tracker"); (GECall "emptyPieces" [] [])]))).

Definition initializeStore_fn := GFunction "initializeStore" None [] [("loaded",GTNamed "TrackerState" [])] (GTNamed "TrackerSession" [])
  (GEIf (GECall "validState" [] [(GEVar "loaded")]) (GEConstruct (GTNamed "TrackerSession" []) [(GEVar "loaded"); (GEVar "loaded"); (GEVal (LitV (LitBool false))); (GEVal (LitV (LitInt (0))))]) (GELet (Some "empty") (GECall "emptyState" [] []) (GEConstruct (GTNamed "TrackerSession" []) [(GEVar "empty"); (GEVar "empty"); (GEVal (LitV (LitBool false))); (GEVal (LitV (LitInt (7))))]))).

Definition stageChange_fn := GFunction "stageChange" None [] [("session",GTNamed "TrackerSession" []); ("change",GTNamed "TrackerResult" [])] (GTNamed "TrackerSession" [])
  (GEIf (GEBinOp EqOp (GEField (GTNamed "TrackerResult" []) (GEVar "change") 0) (GEVal (LitV (LitInt (0))))) (GEConstruct (GTNamed "TrackerSession" []) [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEField (GTNamed "TrackerResult" []) (GEVar "change") 1); (GEVal (LitV (LitBool true))); (GEVal (LitV (LitInt (0))))]) (GEConstruct (GTNamed "TrackerSession" []) [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEVal (LitV (LitBool false))); (GEField (GTNamed "TrackerResult" []) (GEVar "change") 0)])).

Definition prepareAddPair_fn := GFunction "prepareAddPair" None [] [("session",GTNamed "TrackerSession" []); ("startMinute",GTInt); ("endMinute",GTInt)] (GTNamed "TrackerSession" [])
  (GEIf (GEField (GTNamed "TrackerSession" []) (GEVar "session") 2) (GEConstruct (GTNamed "TrackerSession" []) [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEField (GTNamed "TrackerSession" []) (GEVar "session") 1); (GEField (GTNamed "TrackerSession" []) (GEVar "session") 2); (GEVal (LitV (LitInt (8))))]) (GECall "stageChange" [] [(GEVar "session"); (GECall "addPair" [] [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEVar "startMinute"); (GEVar "endMinute")])])).

Definition prepareStartShift_fn := GFunction "prepareStartShift" None [] [("session",GTNamed "TrackerSession" []); ("startMinute",GTInt)] (GTNamed "TrackerSession" [])
  (GEIf (GEField (GTNamed "TrackerSession" []) (GEVar "session") 2) (GEConstruct (GTNamed "TrackerSession" []) [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEField (GTNamed "TrackerSession" []) (GEVar "session") 1); (GEField (GTNamed "TrackerSession" []) (GEVar "session") 2); (GEVal (LitV (LitInt (8))))]) (GECall "stageChange" [] [(GEVar "session"); (GECall "startShift" [] [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEVar "startMinute")])])).

Definition prepareEndShift_fn := GFunction "prepareEndShift" None [] [("session",GTNamed "TrackerSession" []); ("endMinute",GTInt)] (GTNamed "TrackerSession" [])
  (GEIf (GEField (GTNamed "TrackerSession" []) (GEVar "session") 2) (GEConstruct (GTNamed "TrackerSession" []) [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEField (GTNamed "TrackerSession" []) (GEVar "session") 1); (GEField (GTNamed "TrackerSession" []) (GEVar "session") 2); (GEVal (LitV (LitInt (8))))]) (GECall "stageChange" [] [(GEVar "session"); (GECall "endShift" [] [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEVar "endMinute")])])).

Definition prepareDeleteShift_fn := GFunction "prepareDeleteShift" None [] [("session",GTNamed "TrackerSession" []); ("startMinute",GTInt)] (GTNamed "TrackerSession" [])
  (GEIf (GEField (GTNamed "TrackerSession" []) (GEVar "session") 2) (GEConstruct (GTNamed "TrackerSession" []) [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEField (GTNamed "TrackerSession" []) (GEVar "session") 1); (GEField (GTNamed "TrackerSession" []) (GEVar "session") 2); (GEVal (LitV (LitInt (8))))]) (GECall "stageChange" [] [(GEVar "session"); (GECall "deleteShift" [] [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEVar "startMinute")])])).

Definition completeStore_fn := GFunction "completeStore" None [] [("session",GTNamed "TrackerSession" []); ("succeeded",GTBool)] (GTNamed "TrackerSession" [])
  (GEIf (GEField (GTNamed "TrackerSession" []) (GEVar "session") 2) (GEIf (GEVar "succeeded") (GEConstruct (GTNamed "TrackerSession" []) [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 1); (GEField (GTNamed "TrackerSession" []) (GEVar "session") 1); (GEVal (LitV (LitBool false))); (GEVal (LitV (LitInt (0))))]) (GEConstruct (GTNamed "TrackerSession" []) [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEVal (LitV (LitBool false))); (GEVal (LitV (LitInt (9))))])) (GEConstruct (GTNamed "TrackerSession" []) [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEField (GTNamed "TrackerSession" []) (GEVar "session") 1); (GEVal (LitV (LitBool false))); (GEVal (LitV (LitInt (10))))])).

Definition readContained_fn := GFunction "readContained" None [] [("session",GTNamed "TrackerSession" []); ("lowerMinute",GTInt); ("upperMinute",GTInt)] (GTNamed "TrackerResult" [])
  (GEIf (GEField (GTNamed "TrackerSession" []) (GEVar "session") 2) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (8)))); (GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GECall "emptyPieces" [] [])]) (GECall "queryContained" [] [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEVar "lowerMinute"); (GEVar "upperMinute")])).

Definition readIntersecting_fn := GFunction "readIntersecting" None [] [("session",GTNamed "TrackerSession" []); ("lowerMinute",GTInt); ("upperMinute",GTInt)] (GTNamed "TrackerResult" [])
  (GEIf (GEField (GTNamed "TrackerSession" []) (GEVar "session") 2) (GEConstruct (GTNamed "TrackerResult" []) [(GEVal (LitV (LitInt (8)))); (GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GECall "emptyPieces" [] [])]) (GECall "queryIntersecting" [] [(GEField (GTNamed "TrackerSession" []) (GEVar "session") 0); (GEVar "lowerMinute"); (GEVar "upperMinute")])).

Definition tracker_functions := [emptyPieces_fn; consPiece_fn; nextMidnight_fn; minMinute_fn; overlaps_fn; endsAfter_fn; splitOnto_fn; insertDaily_fn; selectPieces_fn; hasStart_fn; removeStart_fn; validPieces_fn; emptyState_fn; validState_fn; addPair_fn; startShift_fn; endShift_fn; queryContained_fn; queryIntersecting_fn; deleteShift_fn; initializeStore_fn; stageChange_fn; prepareAddPair_fn; prepareStartShift_fn; prepareEndShift_fn; prepareDeleteShift_fn; completeStore_fn; readContained_fn; readIntersecting_fn].

Definition tracker_program := GProgram tracker_layouts tracker_functions (GECall "emptyState" [] []).

Example tracker_source_checked : check_program tracker_program = [].
Proof. vm_compute. reflexivity. Qed.

Definition tracker_source := generic_source tracker_program.

(** Library emission uses the existing printer; omit only its standalone main. *)
Definition tracker_library :=
 match check_program tracker_program with
 | [] => "// Generated from Tracker.v by the CJR printer; do not edit." ++ nl ++
         cat_all (map (print_layout tracker_layouts tracker_functions) tracker_layouts) ++
         cat_all (map (print_function tracker_layouts) tracker_functions)
 | errors => "unsupported generic program: " ++ comma errors
 end.
