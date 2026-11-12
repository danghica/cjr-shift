(** Executed mathematical examples; no new general algebraic laws requested. *)
From Coq Require Import ZArith List.
From Tracker Require Import Model WorkingTimeModel.
Import ListNotations Model WorkingTimeModel.
Open Scope Z_scope.
Definition sample_metadata normal rests night ps := Metadata 1 true true 0 300000 false true [] normal rests night ps.
Definition sample_period code s e calendar scheme := Period code s e calendar 0 0 1 scheme false.
Example weekly_exact_limit : finding_code (assess_period (State [(0,48960)] None)
 (sample_metadata [] [] [] []) [(0,48960)] (sample_period 101 0 171360 171360 0)) = 0.
Proof. vm_compute. reflexivity. Qed.
Example weekly_one_minute_over : finding_code (assess_period (State [(0,48961)] None)
 (sample_metadata [] [] [] []) [(0,48961)] (sample_period 101 0 171360 171360 0)) = 101.
Proof. vm_compute. reflexivity. Qed.
Example daily_exact_rest : finding_code (assess_period (State [(0,780)] None)
 (sample_metadata [] [] [] []) [(0,780)] (sample_period 102 0 1440 1440 0)) = 0.
Proof. vm_compute. reflexivity. Qed.
Example daily_one_minute_short : finding_code (assess_period (State [(0,781)] None)
 (sample_metadata [] [] [] []) [(0,781)] (sample_period 102 0 1440 1440 0)) = 102.
Proof. vm_compute. reflexivity. Qed.
Example midnight_pieces_are_continuous_work : finding_code (assess_period (State [(1430,1440);(1440,1500)] None)
 (sample_metadata [] [] [] []) [(1430,1440);(1440,1500)] (sample_period 102 1430 2870 1440 0)) = 0.
Proof. vm_compute. reflexivity. Qed.
Example weekly_rest_includes_additional_daily_rest : finding_code (assess_period (State [(0,7980)] None)
 (sample_metadata [] [] [] []) [(0,7980)] (sample_period 103 0 10080 10080 1)) = 0.
Proof. vm_compute. reflexivity. Qed.
Example weekly_rest_one_minute_short : finding_code (assess_period (State [(0,7981)] None)
 (sample_metadata [] [] [] []) [(0,7981)] (sample_period 103 0 10080 10080 1)) = 103.
Proof. vm_compute. reflexivity. Qed.
Example fortnight_single_long_gap_satisfies_two_period_option : finding_code (assess_period (State [(0,16620)] None)
 (sample_metadata [] [] [] []) [(0,16620)] (sample_period 103 0 20160 20160 2)) = 0.
Proof. vm_compute. reflexivity. Qed.
Example night_average_exact_limit : finding_code (assess_period (State [(0,48960)] None)
 (sample_metadata [(0,48960)] [(100000,124480)] [(0,60)] []) [(0,48960)] (sample_period 105 0 171360 171360 0)) = 0.
Proof. vm_compute. reflexivity. Qed.
Example night_average_one_minute_over : finding_code (assess_period (State [(0,48961)] None)
 (sample_metadata [(0,48961)] [(100000,124480)] [(0,60)] []) [(0,48961)] (sample_period 105 0 171360 171360 0)) = 105.
Proof. vm_compute. reflexivity. Qed.
Example hazardous_exact_limit : finding_code (assess_period (State [(0,480)] None)
 (sample_metadata [] [] [(0,60)] []) [(0,480)] (sample_period 106 0 1440 1440 0)) = 0.
Proof. vm_compute. reflexivity. Qed.
Example hazardous_one_minute_over : finding_code (assess_period (State [(0,481)] None)
 (sample_metadata [] [] [(0,60)] []) [(0,481)] (sample_period 106 0 1440 1440 0)) = 106.
Proof. vm_compute. reflexivity. Qed.
Example pending_shift_makes_affected_period_incomplete : finding_code (assess_period (State [] (Some 100))
 (sample_metadata [] [] [] []) [] (sample_period 102 0 1440 1440 0)) = 21.
Proof. vm_compute. reflexivity. Qed.
Example a_single_rule_is_not_complete_coverage : report_code (validate_working_time (State [] None) 0 1440
 (Metadata 1 true true 0 300000 true true [] [] [] [] [sample_period 102 0 1440 1440 0])) = 21.
Proof. vm_compute. reflexivity. Qed.
