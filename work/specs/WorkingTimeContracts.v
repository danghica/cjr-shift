From Coq Require Import String List ZArith Lia.
From Tracker Require Import Tracker Model Pure Runtime Contracts Operations Public Validation WorkingTimeModel WorkingTimeSource WorkingTimeRuntime.
From Tracker Require Export WorkingTimeRules.
From iris.prelude Require Import options.
Import ListNotations Model WorkingTimeModel.
Local Open Scope string_scope.
Local Open Scope Z_scope.
Lemma wtFirstViolation_exec fs : executes (invoke wtFirstViolation_val [findingsv fs]) (intv (first_violation fs)).
Proof.
 induction fs as [|f fs IH].
 all: unfold invoke,wtFirstViolation_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 eapply ExLet; [run|]; normalize.
 - cbn [first_violation]. solve [execute ltac:(fail)].
 - cbn [first_violation]. eapply ExIfFalse; [run|].
   eapply ExLet with (av := intv (first_violation fs)).
   + eapply call_exec; [run|exact IH].
   + normalize. eapply ite_expression with (b := 100 <=? finding_code f); [wt_formula wt_known|].
     destruct (100 <=? finding_code f).
     * eapply ite_expression with (b := first_violation fs =? 0); [wt_formula wt_known|].
       destruct (first_violation fs =? 0).
       -- wt_formula wt_known.
       -- eapply call_exec; [wt_formula wt_known|apply wtMin_exec].
     * constructor.
Qed.
Lemma wtSummary_exec fs complete : executes (invoke wtSummary_val [findingsv fs;boolv complete]) (intv (summary fs complete)).
Proof.
 unfold invoke,wtSummary_val. eapply ExApp; [constructor|constructor|]. normalize.
 do 2 (eapply ExLet; [run|]; normalize).
 unfold summary. eapply ExLet with (av := intv (first_violation fs)).
 - eapply call_exec; [run|apply wtFirstViolation_exec].
 - normalize. eapply ite_expression with (b := negb (first_violation fs =? 0)); [wt_formula wt_known|].
   destruct (negb (first_violation fs =? 0)); [constructor|].
   eapply ite_expression with (b := existsb (fun f => finding_code f =? 20) fs); [eapply call_exec; [run|apply wtHasCode_exec]|].
   destruct (existsb (fun f => finding_code f =? 20) fs); [constructor|].
   eapply ite_expression with (b := existsb (fun f => finding_code f =? 22) fs); [eapply call_exec; [run|apply wtHasCode_exec]|].
   destruct (existsb (fun f => finding_code f =? 22) fs); [constructor|].
   apply ite_int_expression; [wt_formula ltac:(apply wtHasCode_exec)|constructor|constructor].
Qed.
Lemma wtValidMetadata_exec st m lower upper :
 executes (invoke wtValidMetadata_val [statev st;metadatav m;intv lower;intv upper]) (boolv (valid_metadata st m lower upper)).
Proof.
 unfold invoke,wtValidMetadata_val. eapply ExApp; [constructor|constructor|]. normalize.
 do 4 (eapply ExLet; [run|]; normalize).
 unfold valid_metadata. wt_formula wt_known.
Qed.
Lemma wtSupported_exec m : executes (invoke wtSupported_val [metadatav m]) (boolv (supported_metadata m)).
Proof.
 unfold invoke,wtSupported_val. eapply ExApp; [constructor|constructor|]. normalize.
 eapply ExLet; [run|]. normalize. unfold supported_metadata. wt_formula ltac:(fail).
Qed.
Lemma wtHasRule_exec ps r : executes (invoke wtHasRule_val [periodsv ps;intv r]) (boolv (existsb (fun p => rule p =? r) ps)).
Proof.
 induction ps as [|p ps IH].
 all: unfold invoke,wtHasRule_val at 1; eapply ExApp; [constructor|constructor|]; normalize;
 do 2 (eapply ExLet; [run|]; normalize).
 - simpl. solve [execute ltac:(fail)].
 - cbn [existsb]. destruct (Z.eqb_spec (rule p) r); solve [execute ltac:(exact IH)].
Qed.
Lemma wtCompletePeriods_exec ps : executes (invoke wtCompletePeriods_val [periodsv ps]) (boolv (complete_periods ps)).
Proof.
 unfold invoke,wtCompletePeriods_val. eapply ExApp; [constructor|constructor|]. normalize.
 eapply ExLet; [run|]. normalize. unfold complete_periods. cbn [forallb].
 repeat rewrite andb_true_r. repeat rewrite andb_assoc. wt_formula ltac:(apply wtHasRule_exec).
Qed.
Lemma validateWorkingTime_exec st lower upper m : pending_valid st ->
 executes (invoke validateWorkingTime_val [statev st;intv lower;intv upper;metadatav m])
          (reportv (validate_working_time st lower upper m)).
Proof.
 intros Hp. unfold invoke,validateWorkingTime_val at 1. eapply ExApp; [constructor|constructor|]. normalize.
 do 4 (eapply ExLet; [run|]; normalize).
 unfold validate_working_time.
 eapply ite_expression with (b := negb (valid_metadata st m lower upper));
 [wt_formula ltac:(apply wtValidMetadata_exec)|].
 destruct (negb (valid_metadata st m lower upper)).
 - unfold reportv. cbn [findings report_code breaks_assessed]. wt_formula ltac:(apply wtEmptyFindings_exec).
 - eapply ite_expression with (b := negb (supported_metadata m)); [wt_formula ltac:(apply wtSupported_exec)|].
   destruct (negb (supported_metadata m)).
   + unfold reportv. cbn [findings report_code breaks_assessed]. wt_formula ltac:(apply wtEmptyFindings_exec).
   + eapply ExLet with (av := findingsv (map (assess_period st m (merge_work (shifts st) (other_work m))) (periods m))).
     * eapply call_exec; [wt_formula wt_known|apply wtAssessAll_exec; exact Hp].
     * normalize. unfold reportv. cbn [findings report_code breaks_assessed].
       wt_formula ltac:(first [apply wtSummary_exec|apply wtCompletePeriods_exec]).
Qed.
Definition working_time_port name args := erase wt_layouts (link_functions wt_layouts [] wt_functions)
 (GECall name [] (map GEVal args)).
Lemma working_time_port_exec name args f result :
 glookup name wt_runtime = Some f -> executes (invoke f args) result -> executes (working_time_port name args) result.
Proof.
 intros Hlookup Hrun. unfold working_time_port. rewrite wt_linked. cbn [erase]. unfold resolve. rewrite Hlookup.
 eapply call_exec; [|exact Hrun]. unfold gpack. rewrite map_map.
 change (executes (Struct [] (map Val args)) (StructV args)). exact (pack_exec [] args).
Qed.
Theorem validateWorkingTime_correct `{!cjrGS Σ} `{!invGS_gen HasLc Σ} st lower upper m : pending_valid st ->
 ⊢ WP working_time_port "validateWorkingTime" [statev st;intv lower;intv upper;metadatav m]
 {{ v, ⌜v = reportv (validate_working_time st lower upper m)⌝ }}.
Proof. intros Hp. apply executes_wp. eapply working_time_port_exec; [reflexivity|apply validateWorkingTime_exec; exact Hp]. Qed.
