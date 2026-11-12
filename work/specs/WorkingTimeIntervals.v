(** Refinement of the CJR assessment engine to its pure mathematical model. *)
From Coq Require Import String List ZArith Lia.
From Tracker Require Import Tracker Model Pure Runtime Contracts Operations Public Validation WorkingTimeModel WorkingTimeSource WorkingTimeRuntime.
From iris.prelude Require Import options.
Import ListNotations Model WorkingTimeModel.
Local Open Scope string_scope.
Local Open Scope Z_scope.
Definition periodv p := StructV [boolv false;intv (rule p);intv (from_minute p);intv (to_minute p);intv (calendar_minutes p);intv (extra_from p);intv (extra_to p);intv (evidence p);intv (rest_scheme p);boolv (daily_rest_overlap p);RecV None (Some "unused") (Val (LitV LitUnit))].
Definition pnilv := StructV [boolv true;intv 0;intv 0;intv 0;intv 0;intv 0;intv 0;intv 0;intv 0;boolv false;RecV None (Some "unused") (App (Val wtEmptyPeriods_val) (Struct [] []))].
Definition pnodev p rest := StructV [boolv false;intv (rule p);intv (from_minute p);intv (to_minute p);intv (calendar_minutes p);intv (extra_from p);intv (extra_to p);intv (evidence p);intv (rest_scheme p);boolv (daily_rest_overlap p);RecV None (Some "unused") (Val rest)].
Fixpoint periodsv ps := match ps with [] => pnilv | p::ps => pnodev p (periodsv ps) end.
Definition metadatav m := StructV [intv (jurisdiction m);boolv (adult m);boolv (ordinary_regime m);intv (coverage_from m);intv (coverage_to m);boolv (period_coverage_complete m);boolv (elapsed_work_known m);listv (other_work m);listv (normal_work m);listv (weekly_rest m);listv (night_work m);periodsv (periods m)].
Definition findingv f := StructV [intv (finding_code f);intv (finding_rule f);intv (finding_from f);intv (finding_to f);intv (measured f);intv (limit f)].
Definition fnilv := StructV [boolv true;findingv (Finding 0 0 0 0 0 0);RecV None (Some "unused") (App (Val wtEmptyFindings_val) (Struct [] []))].
Definition fnodev f rest := StructV [boolv false;findingv f;RecV None (Some "unused") (Val rest)].
Fixpoint findingsv fs := match fs with [] => fnilv | f::fs => fnodev f (findingsv fs) end.
Definition reportv r := StructV [intv (report_code r);findingsv (findings r);boolv (breaks_assessed r)].
Lemma periodsv_closed ps : closed_val (periodsv ps).
Proof. induction ps as [|p ps IH]; intros x w; simpl.
 - unfold pnilv. cbn -[wtEmptyPeriods_val]. repeat case_bool_decide; simpl; rewrite ?wtEmptyPeriods_closed; reflexivity.
 - unfold pnodev. cbn -[subst_val periodsv]. repeat case_bool_decide; simpl; rewrite ?IH; reflexivity.
Qed.
Lemma periodv_closed p : closed_val (periodv p).
Proof. intros x w. unfold periodv. cbn. repeat case_bool_decide; reflexivity. Qed.
Lemma pnodev_closed p rest : closed_val rest -> closed_val (pnodev p rest).
Proof. intros H x w. unfold pnodev. cbn -[subst_val]. repeat case_bool_decide; simpl; rewrite ?H; repeat case_bool_decide; reflexivity. Qed.
Lemma metadatav_closed m : closed_val (metadatav m).
Proof. unfold metadatav. apply structv_closed. repeat constructor; first [apply listv_closed|apply periodsv_closed|apply closed_lit]. Qed.
Lemma findingv_closed f : closed_val (findingv f).
Proof. unfold findingv. apply structv_closed. repeat constructor; apply closed_lit. Qed.
Lemma findingsv_closed fs : closed_val (findingsv fs).
Proof. induction fs as [|f fs IH]; intros x w; simpl.
 - unfold fnilv,findingv. cbn -[wtEmptyFindings_val]. repeat case_bool_decide; simpl; rewrite ?wtEmptyFindings_closed; reflexivity.
 - unfold fnodev. cbn -[findingv subst_val findingsv]. repeat case_bool_decide; simpl; rewrite ?findingv_closed ?IH; reflexivity.
Qed.
Lemma reportv_closed r : closed_val (reportv r).
Proof. unfold reportv. apply structv_closed. repeat constructor; first [apply findingsv_closed|apply closed_lit]. Qed.
Ltac wt_close := repeat first [rewrite emptyPieces_closed | rewrite consPiece_closed | rewrite nextMidnight_closed | rewrite minMinute_closed | rewrite overlaps_closed | rewrite endsAfter_closed | rewrite splitOnto_closed | rewrite insertDaily_closed | rewrite selectPieces_closed | rewrite hasStart_closed | rewrite removeStart_closed | rewrite validPieces_closed | rewrite emptyState_closed | rewrite validState_closed | rewrite addPair_closed | rewrite startShift_closed | rewrite endShift_closed | rewrite queryContained_closed | rewrite queryIntersecting_closed | rewrite deleteShift_closed | rewrite initializeStore_closed | rewrite stageChange_closed | rewrite prepareAddPair_closed | rewrite prepareStartShift_closed | rewrite prepareEndShift_closed | rewrite prepareDeleteShift_closed | rewrite completeStore_closed | rewrite readContained_closed | rewrite readIntersecting_closed | rewrite wtMax_closed | rewrite wtMin_closed | rewrite wtClip_closed | rewrite wtMinutes_closed | rewrite wtOrdered_closed | rewrite wtMerge_closed | rewrite wtLongestRest_closed | rewrite wtRestCount_closed | rewrite wtInside_closed | rewrite wtRestValid_closed | rewrite wtEmptyPeriods_closed | rewrite wtConsPeriod_closed | rewrite wtEmptyFindings_closed | rewrite wtConsFinding_closed | rewrite wtFinding_closed | rewrite wtPeriodKnown_closed | rewrite wtGoodPeriod_closed | rewrite wtGoodPeriods_closed | rewrite wtAssess_closed | rewrite wtAssessAll_closed | rewrite wtHasCode_closed | rewrite wtFirstViolation_closed | rewrite wtSummary_closed | rewrite wtValidMetadata_closed | rewrite wtSupported_closed | rewrite validateWorkingTime_closed | rewrite wtHasRule_closed | rewrite wtCompletePeriods_closed | rewrite wtWeekly_closed | rewrite wtDaily_closed | rewrite wtWeeklyRest_closed | rewrite wtAverageNight_closed | rewrite wtHazardNight_closed].
Ltac closed_value ::= first [apply metadatav_closed | apply periodsv_closed | apply periodv_closed | apply findingv_closed | apply findingsv_closed | apply reportv_closed | (apply pnodev_closed; closed_value) | assumption | apply closed_lit | apply listv_closed | apply statev_closed | apply nilv_closed | (apply nodev_closed;closed_value) | (apply structv_closed; repeat constructor; closed_value)].
Ltac normalize ::= repeat (progress (cbn -[subst_val intv boolv listv statev answerv nilv nodev periodv pnilv pnodev periodsv metadatav findingv fnilv fnodev findingsv reportv clip_minutes minutes_in ordered_intervals merge_work longest_rest rest_count all_inside all_rest period_known good_period assess_period valid_metadata supported_metadata first_violation summary validate_working_time period_last complete_periods assess_weekly assess_daily assess_weekly_rest assess_average_night assess_hazard_night emptyPieces_val consPiece_val nextMidnight_val minMinute_val overlaps_val endsAfter_val splitOnto_val insertDaily_val selectPieces_val hasStart_val removeStart_val validPieces_val emptyState_val validState_val addPair_val startShift_val endShift_val queryContained_val queryIntersecting_val deleteShift_val initializeStore_val stageChange_val prepareAddPair_val prepareStartShift_val prepareEndShift_val prepareDeleteShift_val completeStore_val readContained_val readIntersecting_val wtMax_val wtMin_val wtClip_val wtMinutes_val wtOrdered_val wtMerge_val wtLongestRest_val wtRestCount_val wtInside_val wtRestValid_val wtEmptyPeriods_val wtConsPeriod_val wtEmptyFindings_val wtConsFinding_val wtFinding_val wtPeriodKnown_val wtGoodPeriod_val wtGoodPeriods_val wtAssess_val wtAssessAll_val wtHasCode_val wtFirstViolation_val wtSummary_val wtValidMetadata_val wtSupported_val validateWorkingTime_val wtHasRule_val wtCompletePeriods_val wtWeekly_val wtDaily_val wtWeeklyRest_val wtAverageNight_val wtHazardNight_val]; wt_close; repeat case_bool_decide; simplify_eq; close_values)).
Lemma wtMax_exec a b : executes (invoke wtMax_val [intv a;intv b]) (intv (Z.max a b)).
Proof.
 unfold invoke,wtMax_val. eapply ExApp; [constructor|constructor|]. normalize.
 do 2 (eapply ExLet; [run|]; normalize).
 destruct (Z.leb_spec a b) as [Hle|Hgt].
 - rewrite (Z.max_r a b Hle). eapply ExIfTrue; [|run]. eapply ExBin; [run|run|]. calculate.
 - rewrite (Z.max_l a b ltac:(lia)). eapply ExIfFalse; [|run]. eapply ExBin; [run|run|]. calculate.
Qed.
Lemma wtMin_exec a b : executes (invoke wtMin_val [intv a;intv b]) (intv (Z.min a b)).
Proof.
 unfold invoke,wtMin_val. eapply ExApp; [constructor|constructor|]. normalize.
 do 2 (eapply ExLet; [run|]; normalize).
 destruct (Z.leb_spec a b) as [Hle|Hgt].
 - rewrite (Z.min_l a b Hle). eapply ExIfTrue; [|run]. eapply ExBin; [run|run|]. calculate.
 - rewrite (Z.min_r a b ltac:(lia)). eapply ExIfFalse; [|run]. eapply ExBin; [run|run|]. calculate.
Qed.
Lemma wtClip_exec s e a b : executes (invoke wtClip_val [intv s;intv e;intv a;intv b]) (intv (clip_minutes s e (a,b))).
Proof.
 unfold invoke,wtClip_val. eapply ExApp; [constructor|constructor|]. normalize.
 do 4 (eapply ExLet; [run|]; normalize).
 unfold clip_minutes,start,finish; simpl.
 solve [execute ltac:(first [apply wtMax_exec|apply wtMin_exec])].
Qed.
Lemma wtMinutes_exec xs s e : executes (invoke wtMinutes_val [listv xs;intv s;intv e]) (intv (minutes_in xs s e)).
Proof.
 induction xs as [|[a b] xs IH].
 all: unfold invoke,wtMinutes_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 3 (eapply ExLet; [run|]; normalize).
 - cbn [minutes_in]. solve [execute ltac:(fail)].
 - cbn [minutes_in]. solve [execute ltac:(first [apply wtClip_exec|exact IH])].
Qed.
Ltac wt_formula known := first [apply ExValue |
 (eapply ExField; [wt_formula known|reflexivity]) |
 (eapply le_expression; [wt_formula known|wt_formula known]) |
 (eapply eq_expression; [wt_formula known|wt_formula known]) |
 (eapply and_expression; [wt_formula known|wt_formula known]) |
 (eapply lt_expression; [wt_formula known|wt_formula known]) |
 (eapply ite_bool_expression; [wt_formula known|wt_formula known|wt_formula known]) |
 (eapply ExBin; [wt_formula known|wt_formula known|reflexivity]) |
 (eapply call_exec; [run|known])].
Lemma wtOrdered_exec xs previous : executes (invoke wtOrdered_val [listv xs;intv previous]) (boolv (ordered_intervals xs previous)).
Proof.
 revert previous. induction xs as [|[a b] xs IH]; intros previous.
 all: unfold invoke,wtOrdered_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 2 (eapply ExLet; [run|]; normalize).
 - cbn [ordered_intervals]. solve [execute ltac:(fail)].
 - eapply ExIfFalse; [run|]. cbn [ordered_intervals]. wt_formula ltac:(apply IH).
Qed.
Lemma wtMerge_exec xs ys : executes (invoke wtMerge_val [listv xs;listv ys]) (listv (merge_work xs ys)).
Proof.
 revert ys. induction xs as [|[a b] xs IH]; intros ys.
 - unfold invoke,wtMerge_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
   do 2 (eapply ExLet; [run|]; normalize). cbn [merge_work]. solve [execute ltac:(fail)].
 - induction ys as [|[c d] ys IHy].
   all: unfold invoke,wtMerge_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
   do 2 (eapply ExLet; [run|]; normalize).
   + cbn [merge_work]. solve [execute ltac:(fail)].
   + cbn [merge_work start fst]. destruct (Z.leb_spec a c) as [Hac|Hca]; cbn [listv].
     * eapply ExIfFalse; [run|]. eapply ExIfFalse; [run|].
       eapply ExIfTrue; [execute ltac:(fail)|].
       eapply call_exec; [|apply cons_exec; apply listv_closed].
       eapply ExStructNext; [run|simpl]. eapply ExStructNext; [run|simpl].
       eapply ExStructNext.
       -- eapply call_exec; [run|exact (IH ((c,d)::ys))].
       -- simpl. constructor.
     * solve [execute ltac:(exact IHy)].
Qed.
Lemma wtLongestRest_exec xs s e : executes (invoke wtLongestRest_val [listv xs;intv s;intv e]) (intv (longest_rest xs s e)).
Proof.
 revert s. induction xs as [|[a b] xs IH]; intros s.
 all: unfold invoke,wtLongestRest_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 3 (eapply ExLet; [run|]; normalize).
 - cbn [longest_rest]. solve [execute ltac:(apply wtMax_exec)].
 - cbn [longest_rest]. destruct (Z.leb_spec e a);
   solve [execute ltac:(first [apply wtMax_exec|exact (IH (Z.max s b))])].
Qed.
