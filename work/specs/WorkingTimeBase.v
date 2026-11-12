From Coq Require Import String List ZArith Lia.
From Tracker Require Import Tracker Model Pure Runtime Contracts Operations Public Validation WorkingTimeModel WorkingTimeSource WorkingTimeRuntime.
From Tracker Require Export WorkingTimeIntervals.
From iris.prelude Require Import options.
Import ListNotations Model WorkingTimeModel.
Local Open Scope string_scope.
Local Open Scope Z_scope.
Lemma wtRestCount_exec xs s e required : executes (invoke wtRestCount_val [listv xs;intv s;intv e;intv required]) (intv (rest_count xs s e required)).
Proof.
 revert s. induction xs as [|[a b] xs IH]; intros s.
 all: unfold invoke,wtRestCount_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 4 (eapply ExLet; [run|]; normalize).
 - cbn [rest_count]. destruct (Z.leb_spec required (e-s)); solve [execute ltac:(fail)].
 - cbn [rest_count]. destruct (Z.leb_spec e a); destruct (Z.leb_spec required (e-s)); destruct (Z.leb_spec required (a-s));
   solve [execute ltac:(first [apply wtMax_exec|exact (IH (Z.max s b))])].
Unshelve. all: exact (intv 0).
Qed.
Lemma wtInside_exec xs ys : executes (invoke wtInside_val [listv xs;listv ys]) (boolv (all_inside xs ys)).
Proof.
 induction xs as [|[a b] xs IH].
 all: unfold invoke,wtInside_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 2 (eapply ExLet; [run|]; normalize).
 - unfold all_inside. simpl. solve [execute ltac:(fail)].
 - eapply ExIfFalse; [run|]. unfold all_inside in *. simpl. wt_formula ltac:(first [apply wtMinutes_exec|exact IH]).
Qed.
Lemma wtRestValid_exec xs ys : executes (invoke wtRestValid_val [listv xs;listv ys]) (boolv (all_rest xs ys)).
Proof.
 induction xs as [|[a b] xs IH].
 all: unfold invoke,wtRestValid_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 2 (eapply ExLet; [run|]; normalize).
 - unfold all_rest. simpl. solve [execute ltac:(fail)].
 - eapply ExIfFalse; [run|]. unfold all_rest in *. simpl. wt_formula ltac:(first [apply wtMinutes_exec|exact IH]).
Qed.
Lemma wtEmptyPeriods_exec : executes (invoke wtEmptyPeriods_val []) pnilv.
Proof. unfold invoke,wtEmptyPeriods_val. eapply ExApp; [constructor|constructor|]. normalize. unfold pnilv. run. Qed.
Lemma wtEmptyFindings_exec : executes (invoke wtEmptyFindings_val []) fnilv.
Proof. unfold invoke,wtEmptyFindings_val. eapply ExApp; [constructor|constructor|]. normalize. unfold fnilv,findingv. run. Qed.
Lemma wtConsFinding_exec f rest : closed_val rest ->
 executes (invoke wtConsFinding_val [findingv f;rest]) (fnodev f rest).
Proof. intros H. unfold invoke,wtConsFinding_val. eapply ExApp; [constructor|constructor|]. normalize.
 do 2 (eapply ExLet; [run|]; normalize). unfold fnodev. normalize. run. Qed.
Lemma wtFinding_exec p rest c a b : closed_val rest ->
 executes (invoke wtFinding_val [pnodev p rest;intv c;intv a;intv b]) (findingv (finding_for p c a b)).
Proof. intros H. unfold invoke,wtFinding_val. eapply ExApp; [constructor|constructor|]. normalize.
 do 4 (eapply ExLet; [run|]; normalize). unfold findingv,finding_for. simpl. run. Qed.
Lemma wtPeriodKnown_exec st m p rest : pending_valid st -> closed_val rest ->
 executes (invoke wtPeriodKnown_val [statev st;metadatav m;pnodev p rest]) (boolv (period_known st m p)).
Proof.
 intros Hp Hr. destruct st as [xs pending0]. destruct pending0 as [pending0|].
 all: unfold invoke,wtPeriodKnown_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 3 (eapply ExLet; [run|]; normalize);
 eapply ExLet with (av := intv (period_last p)).
 all: try solve [unfold period_last; destruct (Z.eqb_spec (rule p) 101); execute ltac:(apply wtMax_exec)].
 all: normalize; unfold period_known; cbn [pending]; eapply and_expression.
 all: try solve [wt_formula ltac:(fail)].
 - cbn [pending_valid pending] in Hp. eapply ExIfFalse; [execute ltac:(fail)|wt_formula ltac:(fail)].
 - eapply ExIfTrue; [execute ltac:(fail)|constructor].
Qed.
Lemma wtGoodPeriod_exec p rest : closed_val rest ->
 executes (invoke wtGoodPeriod_val [pnodev p rest]) (boolv (good_period p)).
Proof.
 intros Hr. unfold invoke,wtGoodPeriod_val. eapply ExApp; [constructor|constructor|]. normalize.
 eapply ExLet; [run|]. normalize. unfold good_period. wt_formula ltac:(fail).
Qed.
Lemma wtGoodPeriods_exec ps lower upper : executes (invoke wtGoodPeriods_val [periodsv ps;intv lower;intv upper])
 (boolv (forallb (fun p => good_period p && (from_minute p <? upper) && (lower <? to_minute p)) ps)).
Proof.
 induction ps as [|p ps IH].
 all: unfold invoke,wtGoodPeriods_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 3 (eapply ExLet; [run|]; normalize).
 - simpl. solve [execute ltac:(fail)].
 - cbn [forallb]. eapply ExIfFalse; [run|]. eapply and_expression.
   + wt_formula ltac:(apply (wtGoodPeriod_exec p (periodsv ps)); apply periodsv_closed).
   + eapply call_exec; [run|exact IH].
Qed.

Ltac wt_known := first [
 (eapply executes_result; [apply wtPeriodKnown_exec; assumption|congruence]) |
 (apply wtFinding_exec; closed_value) | apply wtMinutes_exec | apply wtLongestRest_exec |
 apply wtRestCount_exec | apply wtMax_exec | apply wtMin_exec |
 apply wtOrdered_exec | apply wtMerge_exec | apply wtInside_exec | apply wtRestValid_exec | apply wtGoodPeriods_exec].
Ltac wt_assess_known st m p rest Hp Hr := first [
 use_execution (wtPeriodKnown_exec st m p rest Hp Hr) |
 (apply (wtFinding_exec p rest); exact Hr) | wt_known].
