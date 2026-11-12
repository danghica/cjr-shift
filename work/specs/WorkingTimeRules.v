From Coq Require Import String List ZArith Lia.
From Tracker Require Import Tracker Model Pure Runtime Contracts Operations Public Validation WorkingTimeModel WorkingTimeSource WorkingTimeRuntime.
From Tracker Require Export WorkingTimeBase.
From iris.prelude Require Import options.
Import ListNotations Model WorkingTimeModel.
Local Open Scope string_scope.
Local Open Scope Z_scope.
Lemma ite_int_expression c yes no b x y : executes c (boolv b) ->
 executes yes (intv x) -> executes no (intv y) ->
 executes (If c yes no) (intv (if b then x else y)).
Proof. destruct b; intros; [eapply ExIfTrue|eapply ExIfFalse]; eauto. Qed.
Ltac wt_formula known ::= first [apply ExValue | apply ExRec | apply ExStructDone |
 (eapply ExField; [wt_formula known|reflexivity]) |
 (eapply le_expression; [wt_formula known|wt_formula known]) |
 (eapply eq_expression; [wt_formula known|wt_formula known]) |
 (eapply and_expression; [wt_formula known|wt_formula known]) |
 (eapply lt_expression; [wt_formula known|wt_formula known]) |
 (eapply ite_int_expression; [wt_formula known|wt_formula known|wt_formula known]) |
 (eapply ite_bool_expression; [wt_formula known|wt_formula known|wt_formula known]) |
 (eapply ExBin; [wt_formula known|wt_formula known|reflexivity]) |
 (eapply ExStructNext; [wt_formula known|simpl;wt_formula known]) |
 (eapply call_exec; [wt_formula known|known])].
Lemma wtWeekly_exec m work p rest : closed_val rest ->
 executes (invoke wtWeekly_val [metadatav m;listv work;pnodev p rest]) (findingv (assess_weekly m work p)).
Proof.
 intros Hr. unfold invoke,wtWeekly_val. eapply ExApp; [constructor|constructor|]. normalize.
 do 3 (eapply ExLet; [run|]; normalize). unfold assess_weekly.
 eapply ite_expression with (b := negb ((0 <? calendar_minutes p) && ((extra_from p =? extra_to p) ||
      ((coverage_from m <=? extra_from p) && (extra_to p <=? coverage_to m))))); [wt_formula wt_known|].
 destruct (negb ((0 <? calendar_minutes p) && ((extra_from p =? extra_to p) ||
      ((coverage_from m <=? extra_from p) && (extra_to p <=? coverage_to m))))).
 - eapply call_exec; [wt_formula wt_known|apply (wtFinding_exec p rest); exact Hr].
 - eapply ExLet with (av := intv (minutes_in work (from_minute p) (to_minute p)+minutes_in work (extra_from p) (extra_to p))).
   + wt_formula wt_known.
   + normalize. eapply call_exec; [wt_formula wt_known|apply (wtFinding_exec p rest); exact Hr].
Qed.
Lemma wtDaily_exec work p rest : closed_val rest ->
 executes (invoke wtDaily_val [listv work;pnodev p rest]) (findingv (assess_daily work p)).
Proof.
 intros Hr. unfold invoke,wtDaily_val. eapply ExApp; [constructor|constructor|]. normalize.
 do 2 (eapply ExLet; [run|]; normalize). unfold assess_daily.
 eapply ExLet with (av := intv (longest_rest work (from_minute p) (to_minute p))).
 - wt_formula wt_known.
 - normalize. eapply call_exec; [wt_formula wt_known|apply (wtFinding_exec p rest); exact Hr].
Qed.
Lemma wtWeeklyRest_exec work p rest : closed_val rest ->
 executes (invoke wtWeeklyRest_val [listv work;pnodev p rest]) (findingv (assess_weekly_rest work p)).
Proof.
 intros Hr. unfold invoke,wtWeeklyRest_val. eapply ExApp; [constructor|constructor|]. normalize.
 do 2 (eapply ExLet; [run|]; normalize). unfold assess_weekly_rest.
 set (extra := if daily_rest_overlap p then 0 else 660).
 set (required := (if rest_scheme p =? 3 then 2880 else 1440)+extra).
 set (count := rest_count work (from_minute p) (to_minute p) required).
 set (amount := if (rest_scheme p =? 2) && (2880+extra <=? longest_rest work (from_minute p) (to_minute p)) then Z.max 2 count else count).
 set (needed := if rest_scheme p =? 2 then 2 else 1).
 eapply ExLet with (av := intv extra); [unfold extra; wt_formula wt_known|]. normalize.
 eapply ExLet with (av := intv required); [unfold required; wt_formula wt_known|]. normalize.
 eapply ExLet with (av := intv count); [unfold count; wt_formula wt_known|]. normalize.
 eapply ExLet with (av := intv amount); [unfold amount; wt_formula wt_known|]. normalize.
 eapply ExLet with (av := intv needed); [unfold needed; wt_formula wt_known|]. normalize.
 eapply call_exec; [wt_formula wt_known|apply (wtFinding_exec p rest); exact Hr].
Qed.
Lemma wtAverageNight_exec m p rest : closed_val rest ->
 executes (invoke wtAverageNight_val [metadatav m;pnodev p rest]) (findingv (assess_average_night m p)).
Proof.
 intros Hr. unfold invoke,wtAverageNight_val. eapply ExApp; [constructor|constructor|]. normalize.
 do 2 (eapply ExLet; [run|]; normalize). unfold assess_average_night.
 set (denominator := calendar_minutes p-minutes_in (weekly_rest m) (from_minute p) (to_minute p)).
 eapply ExLet with (av := intv denominator); [unfold denominator; wt_formula wt_known|]. normalize.
 eapply ite_expression with (b := denominator <=? 0); [wt_formula wt_known|].
 destruct (denominator <=? 0).
 - eapply call_exec; [wt_formula wt_known|apply (wtFinding_exec p rest); exact Hr].
 - eapply ExLet with (av := intv (minutes_in (normal_work m) (from_minute p) (to_minute p))); [wt_formula wt_known|]. normalize.
   eapply call_exec; [wt_formula wt_known|apply (wtFinding_exec p rest); exact Hr].
Qed.
Lemma wtHazardNight_exec m work p rest : closed_val rest ->
 executes (invoke wtHazardNight_val [metadatav m;listv work;pnodev p rest]) (findingv (assess_hazard_night m work p)).
Proof.
 intros Hr. unfold invoke,wtHazardNight_val. eapply ExApp; [constructor|constructor|]. normalize.
 do 3 (eapply ExLet; [run|]; normalize). unfold assess_hazard_night.
 eapply ite_expression with (b := minutes_in (night_work m) (from_minute p) (to_minute p) =? 0); [wt_formula wt_known|].
 destruct (minutes_in (night_work m) (from_minute p) (to_minute p) =? 0).
 - eapply call_exec; [wt_formula wt_known|apply (wtFinding_exec p rest); exact Hr].
 - eapply ExLet with (av := intv (minutes_in work (from_minute p) (to_minute p))); [wt_formula wt_known|]. normalize.
   eapply call_exec; [wt_formula wt_known|apply (wtFinding_exec p rest); exact Hr].
Qed.
Lemma wtAssess_exec st m work p rest : pending_valid st -> closed_val rest ->
 executes (invoke wtAssess_val [statev st;metadatav m;listv work;pnodev p rest]) (findingv (assess_period st m work p)).
Proof.
 intros Hp Hr. unfold invoke,wtAssess_val. eapply ExApp; [constructor|constructor|]. normalize.
 do 4 (eapply ExLet; [run|]; normalize). unfold assess_period.
 eapply ite_expression with (b := evidence p =? 2); [wt_formula wt_known|].
 destruct (evidence p =? 2).
 - eapply call_exec; [wt_formula wt_known|apply (wtFinding_exec p rest); exact Hr].
 - eapply ite_expression with (b := evidence p =? 3); [wt_formula wt_known|].
   destruct (evidence p =? 3).
   + eapply call_exec; [wt_formula wt_known|apply (wtFinding_exec p rest); exact Hr].
   + eapply ite_expression with (b := negb ((evidence p =? 1) && period_known st m p)); [wt_formula ltac:(wt_assess_known st m p rest Hp Hr)|].
     destruct (negb ((evidence p =? 1) && period_known st m p)).
     * eapply call_exec; [wt_formula wt_known|apply (wtFinding_exec p rest); exact Hr].
     * eapply ite_expression with (b := rule p =? 101); [wt_formula wt_known|]. destruct (rule p =? 101).
       -- eapply call_exec; [wt_formula wt_known|apply (wtWeekly_exec m work p rest); exact Hr].
       -- eapply ite_expression with (b := rule p =? 102); [wt_formula wt_known|]. destruct (rule p =? 102).
          ++ eapply call_exec; [wt_formula wt_known|apply (wtDaily_exec work p rest); exact Hr].
          ++ eapply ite_expression with (b := rule p =? 103); [wt_formula wt_known|]. destruct (rule p =? 103).
             ** eapply call_exec; [wt_formula wt_known|apply (wtWeeklyRest_exec work p rest); exact Hr].
             ** eapply ite_expression with (b := rule p =? 105); [wt_formula wt_known|]. destruct (rule p =? 105).
                --- eapply call_exec; [wt_formula wt_known|apply (wtAverageNight_exec m p rest); exact Hr].
                --- eapply call_exec; [wt_formula wt_known|apply (wtHazardNight_exec m work p rest); exact Hr].
Qed.

Lemma wtAssessAll_exec st m work ps : pending_valid st ->
 executes (invoke wtAssessAll_val [statev st;metadatav m;listv work;periodsv ps])
          (findingsv (map (assess_period st m work) ps)).
Proof.
 intros Hp. induction ps as [|p ps IH].
 all: unfold invoke,wtAssessAll_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 4 (eapply ExLet; [run|]; normalize).
 - simpl. solve [execute ltac:(apply wtEmptyFindings_exec)].
 - cbn [map findingsv]. eapply ExIfFalse; [run|].
   eapply call_exec; [|apply (wtConsFinding_exec (assess_period st m work p) (findingsv (map (assess_period st m work) ps))); apply findingsv_closed].
   eapply ExStructNext.
   + eapply call_exec; [run|apply (wtAssess_exec st m work p (periodsv ps)); auto using periodsv_closed].
   + simpl. eapply ExStructNext.
     * eapply call_exec; [run|exact IH].
     * simpl. constructor.
Qed.
Lemma wtHasCode_exec fs c : executes (invoke wtHasCode_val [findingsv fs;intv c]) (boolv (existsb (fun f => finding_code f =? c) fs)).
Proof.
 induction fs as [|f fs IH].
 all: unfold invoke,wtHasCode_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 2 (eapply ExLet; [run|]; normalize).
 - simpl. solve [execute ltac:(fail)].
 - simpl. destruct (Z.eqb_spec (finding_code f) c); solve [execute ltac:(exact IH)].
Qed.
